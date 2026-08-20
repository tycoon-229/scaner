import 'package:camera/camera.dart';
import 'package:dynamsoft_capture_vision_flutter/dynamsoft_capture_vision_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:poc_multi_scan/config/license_keys.dart';
import 'package:poc_multi_scan/utils/scan_entries.dart';
import 'package:poc_multi_scan/utils/scan_monitor.dart';
import 'package:poc_multi_scan/widgets/scan_result_widget.dart';
import 'package:poc_multi_scan/widgets/camera_scanner/camera_scanner.dart';
import 'package:poc_multi_scan/widgets/scanner_camera_preview.dart';
import 'package:poc_multi_scan/widgets/scanner_live_scaffold.dart';
import 'package:poc_multi_scan/widgets/scanner_message.dart';

/// Optimized DynamsoftTab wiring [CameraScannerWidget] to [CaptureVisionRouter]
/// for ultra-fast, non-laggy live camera barcode decoding.
class DynamsoftTab extends StatefulWidget {
  const DynamsoftTab({super.key});

  @override
  State<DynamsoftTab> createState() => _DynamsoftTabState();
}

class _DynamsoftTabState extends State<DynamsoftTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final ScannerUIController _scannerController = ScannerUIController();
  final ScanMonitor _monitor = ScanMonitor(engineName: 'Dynamsoft');

  /// Key-Value pairs list for multi scan results:
  /// * `entry.key`   -> formatName (e.g. 'QR_CODE', 'EAN_13')
  /// * `entry.value` -> decoded text string
  final List<ScanEntry> _scannedEntries = <ScanEntry>[];

  /// Single scan result (Key = formatName, Value = text)
  ScanEntry? _singleResult;

  ScanMode _scanMode = ScanMode.single;
  bool _showMultiResultScreen = false;

  /// Prevents re-entrant captures
  bool _isCaptureRunning = false;

  // ──────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ──────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _scannerController.addListener(_onControllerChanged);
    _monitor.startSession(modeLabel: _modeLabel);
    _initDynamsoft();
  }

  Future<void> _initDynamsoft() async {
    try {
      await LicenseManager.initLicense(LicenseKeys.dynamsoft);
    } catch (e) {
      debugPrint('[DynamsoftTab] initLicense error: $e');
    }
  }

  @override
  void dispose() {
    _scannerController
      ..removeListener(_onControllerChanged)
      ..dispose();
    CaptureVisionRouter.instance.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  /// Restarts the camera stream and laser animation when switching tabs.
  Future<void> restartCameraLaser() async {
    await _scannerController.restartCameraLaser();
    if (mounted) {
      setState(() {
        _singleResult = null;
        _clearMultiResults();
      });
      _monitor.startSession(modeLabel: _modeLabel);
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Frame handler
  // ──────────────────────────────────────────────────────────────────────────

  Future<bool?> _handleFrame(CameraImage image, Rect? cropRect) async {
    if (_isCaptureRunning) return false;
    _isCaptureRunning = true;

    final ScanMonitorOperation operation = _monitor.startDecode(
      source: ScanMonitorSource.liveCamera,
      modeLabel: _modeLabel,
    );
    bool hasDecodedCode = false;

    try {
      // 1. Build ImageData (Fast memory copy with optional cropping, zero Isolate overhead)
      final ImageData? imageData = _buildImageData(image, cropRect);
      if (imageData == null) return false;

      // 2. Decode with Dynamsoft using SpeedFirst template for live stream
      final CapturedResult result = await CaptureVisionRouter.instance.capture(
        imageData,
        EnumPresetTemplate.readBarcodesSpeedFirst,
      );

      // 3. Extract barcodes
      final List<BarcodeResultItem> barcodes =
          result.decodedBarcodesResult?.items ?? <BarcodeResultItem>[];
      if (barcodes.isEmpty) return false;

      hasDecodedCode = true;
      if (_scanMode == ScanMode.single) {
        // Single: take first → show result → pause camera
        final BarcodeResultItem first = barcodes.first;
        _monitor.recordResults(uniqueCount: 1);
        if (mounted) {
          setState(() {
            _singleResult = MapEntry<String, String>(
              first.formatString,
              first.text,
            );
          });
        }
        return true; // CameraScannerWidget auto-pauses stream
      } else {
        // Multi: accumulate unique barcodes
        bool hasNew = false;
        int newCodeCount = 0;
        int duplicateCodeCount = 0;
        for (final BarcodeResultItem b in barcodes) {
          final MapEntry<String, String> e = MapEntry<String, String>(
            b.formatString,
            b.text,
          );
          if (addUniqueScanEntry(_scannedEntries, e)) {
            hasNew = true;
            newCodeCount++;
          } else {
            duplicateCodeCount++;
          }
        }
        _monitor.recordResults(
          uniqueCount: newCodeCount,
          duplicateCount: duplicateCodeCount,
        );
        if (hasNew && mounted) setState(() {});
        return false;
      }
    } catch (e) {
      debugPrint('[DynamsoftTab] capture error: $e');
      return false;
    } finally {
      operation.finish(success: hasDecodedCode);
      _isCaptureRunning = false;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Gallery handler
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _handleGalleryImage(String path) async {
    // Stop the live stream first so CaptureVisionRouter is free for a file decode.
    await _scannerController.pauseStream();
    _monitor.startSession(modeLabel: '$_modeLabel / Gallery');
    final ScanMonitorOperation operation = _monitor.startDecode(
      source: ScanMonitorSource.galleryImage,
      modeLabel: '$_modeLabel / Gallery',
    );
    bool hasDecodedCode = false;

    try {
      // captureFile works on an image path — no ImageData conversion needed.
      final CapturedResult result = await CaptureVisionRouter.instance
          .captureFile(
            path,
            EnumPresetTemplate.readBarcodesReadRateFirst, // best accuracy for still images
          );

      final List<BarcodeResultItem> barcodes =
          result.decodedBarcodesResult?.items ?? <BarcodeResultItem>[];

      if (!mounted) return;

      if (barcodes.isNotEmpty) {
        hasDecodedCode = true;
        _monitor.recordResults(uniqueCount: 1);
        setState(() {
          _singleResult = ScanEntry(
            barcodes.first.formatString,
            barcodes.first.text,
          );
        });
      } else {
        showScannerMessage(context, 'No valid code found in the image');
        _resumeScan();
      }
    } catch (e) {
      debugPrint('[DynamsoftTab] gallery decode error: $e');
      if (mounted) showScannerMessage(context, 'Failed to read image: $e');
      _resumeScan();
    } finally {
      operation.finish(success: hasDecodedCode);
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // CameraImage → Dynamsoft ImageData (Optimized & Cropped)
  // ──────────────────────────────────────────────────────────────────────────

  ImageData? _buildImageData(CameraImage image, Rect? cropRect) {
    try {
      switch (image.format.group) {
        case ImageFormatGroup.yuv420:
          int cropLeft = 0;
          int cropTop = 0;
          int cropWidth = image.width;
          int cropHeight = image.height;

          if (cropRect != null) {
            cropLeft = cropRect.left.round().clamp(0, image.width - 1);
            cropTop = cropRect.top.round().clamp(0, image.height - 1);
            cropWidth = cropRect.width.round().clamp(1, image.width - cropLeft);
            cropHeight = cropRect.height.round().clamp(1, image.height - cropTop);
          }

          // Ensure even dimensions for 4:2:0 YUV alignment
          if (cropWidth % 2 != 0) cropWidth--;
          if (cropHeight % 2 != 0) cropHeight--;

          final int ySize = cropWidth * cropHeight;
          final Uint8List nv21 = Uint8List(ySize + (ySize ~/ 2));

          final Uint8List yPlane = image.planes[0].bytes;
          final Uint8List uPlane = image.planes[1].bytes;
          final Uint8List vPlane = image.planes[2].bytes;

          final int yRowStride = image.planes[0].bytesPerRow;
          final int uvRowStride = image.planes[1].bytesPerRow;
          final int uvPixelStride = image.planes[1].bytesPerPixel ?? 1;

          // 1. Copy Y plane (cropped)
          for (int row = 0; row < cropHeight; row++) {
            final int srcOffset = (cropTop + row) * yRowStride + cropLeft;
            final int dstOffset = row * cropWidth;
            nv21.setRange(
              dstOffset,
              dstOffset + cropWidth,
              yPlane,
              srcOffset,
            );
          }

          // 2. Interleave V, U → NV21 (cropped)
          int nv21Offset = ySize;
          final int uvCropTop = cropTop ~/ 2;
          final int uvCropLeft = cropLeft ~/ 2;
          final int uvCropHeight = cropHeight ~/ 2;
          final int uvCropWidth = cropWidth ~/ 2;

          for (int row = 0; row < uvCropHeight; row++) {
            final int rowStart = (uvCropTop + row) * uvRowStride;
            for (int col = 0; col < uvCropWidth; col++) {
              final int uvIndex = rowStart + (uvCropLeft + col) * uvPixelStride;
              if (uvIndex < vPlane.length &&
                  uvIndex < uPlane.length &&
                  nv21Offset + 1 < nv21.length) {
                nv21[nv21Offset++] = vPlane[uvIndex];
                nv21[nv21Offset++] = uPlane[uvIndex];
              }
            }
          }

          return ImageData(
            bytes: nv21,
            width: cropWidth,
            height: cropHeight,
            stride: cropWidth,
            format: EnumImagePixelFormat.nv21,
            orientation: 0,
          );

        case ImageFormatGroup.bgra8888:
          // iOS BGRA format
          return ImageData(
            bytes: image.planes[0].bytes,
            width: image.width,
            height: image.height,
            stride: image.planes[0].bytesPerRow,
            format: EnumImagePixelFormat.abgr8888,
            orientation: 0,
          );

        default:
          return null;
      }
    } catch (e) {
      debugPrint('[DynamsoftTab] _buildImageData error: $e');
      return null;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Build
  // ──────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // 1. Single Scan result screen
    if (_scanMode == ScanMode.single && _singleResult != null) {
      return ScanResultPage(
        results: <ScanEntry>[_singleResult!],
        monitorSnapshot: _monitor.snapshot(resultCount: 1),
        onScanAgain: () {
          setState(() => _singleResult = null);
          _monitor.startSession(modeLabel: _modeLabel);
          _resumeScan();
        },
      );
    }

    // 2. Multi Scan result screen
    if (_scanMode == ScanMode.multiscan && _showMultiResultScreen) {
      return ScanResultPage(
        results: _scannedEntries,
        monitorSnapshot: _monitor.snapshot(resultCount: _scannedEntries.length),
        onScanAgain: () {
          setState(_clearMultiResults);
          _monitor.startSession(modeLabel: _modeLabel);
          _resumeScan();
        },
      );
    }

    return ScannerLiveScaffold(
      preview: ScannerCameraPreview(
        tabIndex: 1,
        controller: _scannerController,
        scanMode: _scanMode,
        resolution: ResolutionPreset.high,
        scanDelay: const Duration(milliseconds: 50),
        frameIntervalMs: _scanMode == ScanMode.single ? 150 : 200,
        onFrameCaptured: _handleFrame,
        onGalleryImageSelected: _handleGalleryImage,
        onControllerCreated: (CameraController? cam, Exception? err) {
          if (err != null && mounted) {
            showScannerMessage(context, 'Camera error: $err');
          }
        },
      ),
      scanMode: _scanMode,
      resultCount: _scannedEntries.length,
      onShowResults: _showMultiResults,
      onModeChanged: _changeMode,
      onGalleryImageSelected: _handleGalleryImage,
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Helpers
  // ──────────────────────────────────────────────────────────────────────────

  void _resumeScan() {
    _scannerController.resumeStream(
      (CameraImage image) => _handleFrame(image, null),
    );
  }

  void _changeMode(ScanMode mode) {
    setState(() {
      _scanMode = mode;
      _singleResult = null;
      _clearMultiResults();
    });
    _monitor.startSession(modeLabel: _modeLabel);
  }

  void _clearMultiResults() {
    _scannedEntries.clear();
    _showMultiResultScreen = false;
  }

  void _showMultiResults() {
    setState(() => _showMultiResultScreen = true);
  }

  String get _modeLabel {
    return _scanMode == ScanMode.single ? 'Single Code' : 'Multi Code';
  }
}
