import 'package:camera/camera.dart';
import 'package:dynamsoft_capture_vision_flutter/dynamsoft_capture_vision_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';

import 'package:poc_multi_scan/config/license_keys.dart';
import 'package:poc_multi_scan/extensions/code_format_extensions.dart';
import 'package:poc_multi_scan/services/native_scanners/gs1/gs1_composite_assembler.dart';
import 'package:poc_multi_scan/utils/scan_entries.dart';
import 'package:poc_multi_scan/utils/scan_monitor.dart';
import 'package:poc_multi_scan/widgets/scan_result_widget.dart';
import 'package:poc_multi_scan/widgets/camera_scanner/camera_scanner.dart';
import 'package:poc_multi_scan/widgets/scanner_camera_preview.dart';
import 'package:poc_multi_scan/widgets/scanner_live_scaffold.dart';
import 'package:poc_multi_scan/widgets/scanner_message.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Top-level isolate helper (must be outside class for compute())
// ─────────────────────────────────────────────────────────────────────────────

/// Data passed into the isolate for YUV → NV21 conversion.
class _ConvertParams {
  const _ConvertParams({
    required this.yBytes,
    required this.uBytes,
    required this.vBytes,
    required this.yRowStride,
    required this.uvPixelStride,
    required this.width,
    required this.height,
  });

  final Uint8List yBytes;
  final Uint8List uBytes;
  final Uint8List vBytes;
  final int yRowStride;
  final int uvPixelStride;
  final int width;
  final int height;
}

/// Runs in a background isolate — no Flutter UI code allowed here.
Uint8List _yuv420ToNv21Isolate(_ConvertParams p) {
  final int ySize = p.width * p.height;
  final Uint8List nv21 = Uint8List(ySize + ySize ~/ 2);

  // Copy Y plane row by row (handles non-contiguous strides)
  for (int row = 0; row < p.height; row++) {
    nv21.setRange(
      row * p.width,
      row * p.width + p.width,
      p.yBytes,
      row * p.yRowStride,
    );
  }

  // Interleave V, U → NV21
  int offset = ySize;
  for (int i = 0; i < p.uBytes.length; i += p.uvPixelStride) {
    if (offset + 1 >= nv21.length) break;
    nv21[offset++] = p.vBytes[i];
    nv21[offset++] = p.uBytes[i];
  }

  return nv21;
}

// ─────────────────────────────────────────────────────────────────────────────
// DynamsoftTab
// ─────────────────────────────────────────────────────────────────────────────

/// Demo tab wiring [CameraScannerWidget] to [CaptureVisionRouter]
/// for frame-by-frame Dynamsoft barcode decoding.
///
/// All heavy work (YUV conversion) is offloaded to a background isolate
/// via [compute] so the camera preview stays smooth.
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
  final Gs1CompositeAssembler _gs1CompositeAssembler =
      const Gs1CompositeAssembler();

  /// Key-Value pairs list for multi scan results:
  /// * `entry.key`   -> formatName (e.g. 'QR_CODE', 'EAN_13')
  /// * `entry.value` -> decoded text string
  final List<ScanEntry> _scannedEntries = <ScanEntry>[];

  /// Single scan result (Key = formatName, Value = text)
  ScanEntry? _singleResult;
  ScanEntry? _pendingLinearCarrier;
  DateTime? _pendingLinearCarrierAt;

  ScanMode _scanMode = ScanMode.single;
  bool _showMultiResultScreen = false;

  /// Prevents re-entrant captures (belt-and-suspenders on top of
  /// [CameraScannerWidget]'s own _isProcessing guard).
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
      debugPrint('[DynamsoftTab] License initialized successfully.');
      for (final String templateName in <String>[
        EnumPresetTemplate.readBarcodesReadRateFirst,
        EnumPresetTemplate.readBarcodes,
        EnumPresetTemplate.defaultTemplate,
      ]) {
        try {
          final SimplifiedCaptureVisionSettings? settings =
              await CaptureVisionRouter.instance.getSimplifiedSettings(
                templateName,
              );
          if (settings?.barcodeSettings != null) {
            settings!.barcodeSettings!.barcodeFormatIds = EnumBarcodeFormat.all;
            settings.barcodeSettings!.expectedBarcodesCount = 0;
            settings.barcodeSettings!.localizationModes = <EnumLocalizationMode>[
              EnumLocalizationMode.connectedBlocks,
              EnumLocalizationMode.lines,
              EnumLocalizationMode.statistics,
              EnumLocalizationMode.scanDirectly,
            ];
            settings.barcodeSettings!.deblurModes = <EnumDeblurMode>[
              EnumDeblurMode.directBinarization,
              EnumDeblurMode.thresholdBinarization,
              EnumDeblurMode.deepAnalysis,
            ];
            settings.barcodeSettings!.scaleDownThreshold = 2048;
            await CaptureVisionRouter.instance.updateSettings(
              templateName,
              settings,
            );
            debugPrint(
              '[DynamsoftTab] Updated template "$templateName": formats=${settings.barcodeSettings!.barcodeFormatIds}, count=${settings.barcodeSettings!.expectedBarcodesCount}',
            );
          }
        } catch (e) {
          debugPrint('[DynamsoftTab] Error updating template "$templateName": $e');
        }
      }
    } catch (e) {
      debugPrint('[DynamsoftTab] initLicense/Settings error: $e');
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
        _clearPendingLinearCarrier();
      });
      _monitor.startSession(modeLabel: _modeLabel);
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Frame handler
  // ──────────────────────────────────────────────────────────────────────────

  Future<bool?> _handleFrame(CameraImage image, Rect? cropRect) async {
    // Extra guard: skip if a capture is already in-flight
    if (_isCaptureRunning) return false;
    _isCaptureRunning = true;
    final ScanMonitorOperation operation = _monitor.startDecode(
      source: ScanMonitorSource.liveCamera,
      modeLabel: _modeLabel,
    );
    bool hasDecodedCode = false;

    try {
      // 1. Build ImageData (YUV conversion runs in isolate → non-blocking)
      final ImageData? imageData = await _buildImageData(image);
      if (imageData == null) return false;

      // 2. Decode with Dynamsoft
      final CapturedResult result = await CaptureVisionRouter.instance.capture(
        imageData,
        EnumPresetTemplate.readBarcodesReadRateFirst,
      );

      // 3. Extract barcodes
      final List<BarcodeResultItem> barcodes =
          result.decodedBarcodesResult?.items ?? <BarcodeResultItem>[];
      if (barcodes.isEmpty) return false;

      debugPrint(
        '[DynamsoftTab] === DECODED FRAME: ${barcodes.length} barcode item(s) ===',
      );
      for (int i = 0; i < barcodes.length; i++) {
        final BarcodeResultItem b = barcodes[i];
        final Quadrilateral? loc = b.location;
        final String pts =
            loc != null
                ? loc.points.map((p) => '(${p.x},${p.y})').join(', ')
                : 'no-loc';
        debugPrint(
          '[DynamsoftTab] Item #$i: format=${b.formatString} (${b.format}), text="${b.text}", pts=[$pts]',
        );
      }

      hasDecodedCode = true;

      // 4. Try assembling GS1 Composite pair from decoded items
      final List<Code> codes = barcodes.map(_codeFromDynamsoft).toList();
      final Gs1CompositeAssembly? compositeAssembly =
          _gs1CompositeAssembler.assemble(codes);

      debugPrint(
        '[DynamsoftTab] GS1 Composite assembly result: ${compositeAssembly != null ? "SUCCESS (${compositeAssembly.title} => ${compositeAssembly.resultText})" : "NULL (No composite pair assembled)"}',
      );

      if (compositeAssembly != null) {
        final ScanEntry entry = ScanEntry(
          compositeAssembly.title,
          compositeAssembly.resultText,
        );

        if (_scanMode == ScanMode.single) {
          _clearPendingLinearCarrier();
          _monitor.recordResults(uniqueCount: 1);
          if (mounted) {
            setState(() {
              _singleResult = entry;
            });
          }
          return true; // CameraScannerWidget auto-pauses stream
        } else {
          bool hasNew = false;
          int newCodeCount = 0;
          int duplicateCodeCount = 0;
          if (addUniqueScanEntry(_scannedEntries, entry)) {
            hasNew = true;
            newCodeCount++;
          } else {
            duplicateCodeCount++;
          }
          _monitor.recordResults(
            uniqueCount: newCodeCount,
            duplicateCount: duplicateCodeCount,
          );
          if (hasNew && mounted) setState(() {});
          return false;
        }
      }

      if (_scanMode == ScanMode.single) {
        final BarcodeResultItem? selected = _selectSingleBarcode(barcodes);
        if (selected == null) return false;

        final ScanEntry entry = _entryForBarcode(selected);
        if (_shouldWaitForComposite(selected, entry)) {
          hasDecodedCode = false;
          return false;
        }

        _clearPendingLinearCarrier();
        _monitor.recordResults(uniqueCount: 1);
        if (mounted) {
          setState(() {
            _singleResult = entry;
          });
        }
        return true; // CameraScannerWidget auto-pauses stream
      } else {
        // Multi: accumulate unique barcodes
        bool hasNew = false;
        int newCodeCount = 0;
        int duplicateCodeCount = 0;
        for (final BarcodeResultItem b in barcodes) {
          if (_isLikelyPartialCompositeCarrier(b)) continue;
          final ScanEntry e = _entryForBarcode(b);
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
            EnumPresetTemplate
                .readBarcodesReadRateFirst, // best accuracy for still images
          );

      final List<BarcodeResultItem> barcodes =
          result.decodedBarcodesResult?.items ?? <BarcodeResultItem>[];

      if (!mounted) return;

      final List<Code> codes = barcodes.map(_codeFromDynamsoft).toList();
      final Gs1CompositeAssembly? compositeAssembly =
          _gs1CompositeAssembler.assemble(codes);

      if (compositeAssembly != null) {
        hasDecodedCode = true;
        _monitor.recordResults(uniqueCount: 1);
        setState(() {
          _singleResult = ScanEntry(
            compositeAssembly.title,
            compositeAssembly.resultText,
          );
        });
        return;
      }

      final BarcodeResultItem? selected = _selectSingleBarcode(
        barcodes,
        allowPartialCarrier: false,
      );
      if (selected != null) {
        hasDecodedCode = true;
        _monitor.recordResults(uniqueCount: 1);
        setState(() {
          _singleResult = _entryForBarcode(selected);
        });
      } else {
        showScannerMessage(context, 'No valid code found in the image');
        // Resume stream so user can scan again
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
  // CameraImage → Dynamsoft ImageData
  // ──────────────────────────────────────────────────────────────────────────

  Future<ImageData?> _buildImageData(CameraImage image) async {
    try {
      switch (image.format.group) {
        case ImageFormatGroup.yuv420:
          // Offload YUV → NV21 conversion to a background isolate
          final Uint8List nv21 = await compute(
            _yuv420ToNv21Isolate,
            _ConvertParams(
              yBytes: image.planes[0].bytes,
              uBytes: image.planes[1].bytes,
              vBytes: image.planes[2].bytes,
              yRowStride: image.planes[0].bytesPerRow,
              uvPixelStride: image.planes[1].bytesPerPixel ?? 1,
              width: image.width,
              height: image.height,
            ),
          );
          return ImageData(
            bytes: nv21,
            width: image.width,
            height: image.height,
            stride: image.width,
            format: EnumImagePixelFormat.nv21,
            orientation: defaultTargetPlatform == TargetPlatform.android ? 90 : 0,
          );

        case ImageFormatGroup.bgra8888:
          // iOS BGRA — already contiguous, copy directly
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
        scanDelay: const Duration(milliseconds: 300),
        frameIntervalMs: 300,
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
      _clearPendingLinearCarrier();
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

  Code _codeFromDynamsoft(BarcodeResultItem item) {
    final int? zxFormat = item.formatString.toZxingFormat;
    final Quadrilateral? loc = item.location;
    Position? pos;
    if (loc != null && loc.points.length >= 4) {
      pos = Position(
        0,
        0,
        loc.points[0].x,
        loc.points[0].y,
        loc.points[1].x,
        loc.points[1].y,
        loc.points[2].x,
        loc.points[2].y,
        loc.points[3].x,
        loc.points[3].y,
      );
    }
    return Code(
      text: item.text,
      format: zxFormat,
      isValid: true,
      position: pos,
    );
  }

  ScanEntry _entryForBarcode(BarcodeResultItem barcode) {
    final String formatName = barcode.formatString;
    final String rawText = barcode.text;
    final bool looksLikeGs1 = _looksLikeGs1(formatName, rawText);

    // Replace Dynamsoft composite pipe separator '|' with GS separator
    final String cleanText = rawText.replaceAll('|', '\u001d');

    final List<Gs1Element> elements = Gs1ElementStringParser.parse(
      cleanText,
      fallbackFormat: formatName.toZxingFormat,
    );

    String title = formatName.toUpperCase().replaceAll('_', '');
    if (elements.length > 1 || formatName.toUpperCase().contains('COMPOSITE')) {
      if (title.contains('CODE128') ||
          title.contains('GS1128') ||
          title.contains('GS1COMPOSITE')) {
        title = 'CODE128 (COMPOSITE C)';
      } else {
        title = '$title (COMPOSITE A)';
      }
    }

    final String? gs1Text = Gs1ElementStringParser.tryFormatElementString(
      cleanText,
      fallbackFormat: formatName.toZxingFormat,
      requireGs1Marker: !looksLikeGs1,
    );

    final String finalValue = elements.isNotEmpty
        ? Gs1ElementStringParser.formatElements(elements)
        : (gs1Text ?? rawText);

    return ScanEntry(title, finalValue);
  }

  BarcodeResultItem? _selectSingleBarcode(
    List<BarcodeResultItem> barcodes, {
    bool allowPartialCarrier = true,
  }) {
    if (barcodes.isEmpty) return null;

    for (final BarcodeResultItem barcode in barcodes) {
      if (_isCompositeResult(barcode)) return barcode;
    }

    for (final BarcodeResultItem barcode in barcodes) {
      if (allowPartialCarrier || !_isLikelyPartialCompositeCarrier(barcode)) {
        return barcode;
      }
    }

    return null;
  }

  bool _shouldWaitForComposite(BarcodeResultItem barcode, ScanEntry entry) {
    if (!_isLikelyPartialCompositeCarrier(barcode)) return false;

    final DateTime now = DateTime.now();
    if (_pendingLinearCarrier?.value != entry.value) {
      _pendingLinearCarrier = entry;
      _pendingLinearCarrierAt = now;
      return true;
    }

    final DateTime firstSeen = _pendingLinearCarrierAt ?? now;
    return now.difference(firstSeen) < const Duration(milliseconds: 1800);
  }

  bool _isCompositeResult(BarcodeResultItem barcode) {
    final String formatName = barcode.formatString.toUpperCase();
    final String text = barcode.text;
    if (formatName.contains('COMPOSITE') || formatName.contains('GS1_COMPOSITE')) {
      return true;
    }
    if (text.contains('|')) return true;

    final String cleanText = text.replaceAll('|', '\u001d');
    final List<Gs1Element> elements = Gs1ElementStringParser.parse(
      cleanText,
      fallbackFormat: formatName.toZxingFormat,
    );
    return elements.length > 1;
  }

  bool _isLikelyPartialCompositeCarrier(BarcodeResultItem barcode) {
    final String formatName = barcode.formatString.toUpperCase();
    if (formatName.contains('COMPOSITE') || formatName.contains('GS1_COMPOSITE')) {
      return false;
    }
    if (barcode.text.contains('|')) return false;

    if (!formatName.contains('CODE_128') && !formatName.contains('CODE128')) {
      return false;
    }

    final List<Gs1Element> elements = Gs1ElementStringParser.parse(
      barcode.text,
      fallbackFormat: formatName.toZxingFormat,
    );
    return elements.length == 1 && elements.single.ai == '01';
  }

  void _clearPendingLinearCarrier() {
    _pendingLinearCarrier = null;
    _pendingLinearCarrierAt = null;
  }

  bool _looksLikeGs1(String formatName, String text) {
    final String normalizedFormat = formatName.toUpperCase();
    return normalizedFormat.contains('GS1') ||
        normalizedFormat.contains('COMPOSITE') ||
        text.contains('\u001d') ||
        text.contains('\u241d') ||
        RegExp(
          r'\{GS\}|<GS>|\\u001d|\\x1d',
          caseSensitive: false,
        ).hasMatch(text);
  }

  String get _modeLabel {
    return _scanMode == ScanMode.single ? 'Single Code' : 'Multi Code';
  }
}
