import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart' as zxing;
import 'package:flutter_zxing/flutter_zxing.dart' hide ImageFormat;

import 'package:poc_multi_scan/extensions/code_format_extensions.dart';
import 'package:poc_multi_scan/services/native_scanners/gs1/gs1_composite_assembler.dart';
import 'package:poc_multi_scan/services/native_scanners/gs1/gs1_composite_native_service.dart';
import 'package:poc_multi_scan/services/native_scanners/msi/msi_scan_coordinator.dart';
import 'package:poc_multi_scan/utils/scan_entries.dart';
import 'package:poc_multi_scan/utils/scan_monitor.dart';
import 'package:poc_multi_scan/widgets/scan_result_widget.dart';
import 'package:poc_multi_scan/widgets/camera_scanner/camera_scanner.dart';
import 'package:poc_multi_scan/widgets/scanner_camera_preview.dart';
import 'package:poc_multi_scan/widgets/scanner_live_scaffold.dart';
import 'package:poc_multi_scan/widgets/scanner_message.dart';

/// Demo page showing how to wire [CameraScannerWidget] to [flutter_zxing] decoder.
///
/// Features:
/// * Single scan: Automatically pauses stream and shows [ScanWidget] on success.
/// * Multi scan: Continuously decodes code-by-code with high sensitivity,
///   accumulating unique Key-Value pairs (`MapEntry(formatName, decodedText)`),
///   and displaying a floating results button.
/// * Displays [ScanResultWidget] (accepts `List<MapEntry<String, String>>`) as a dedicated Widget screen.
/// * Gallery scan: Decodes images picked from gallery.
class ZxingTab extends StatefulWidget {
  const ZxingTab({super.key});

  @override
  State<ZxingTab> createState() => _ZxingTabState();
}

class _ZxingTabState extends State<ZxingTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final ScannerUIController _scannerController = ScannerUIController();
  final ScanMonitor _monitor = ScanMonitor(engineName: 'ZXing');
  final MsiScanCoordinator _msiScanCoordinator = MsiScanCoordinator();
  final Gs1CompositeAssembler _gs1CompositeAssembler =
      const Gs1CompositeAssembler();

  Code? result;

  /// Key-Value pairs list for multi scan results:
  /// * `entry.key`   -> formatName (e.g. 'QR_CODE', 'EAN_13')
  /// * `entry.value` -> decoded text string
  final List<ScanEntry> _scannedEntries = <ScanEntry>[];

  ScanMode _scanMode = ScanMode.single;
  bool _showMultiResultScreen = false;

  @override
  void initState() {
    super.initState();
    _scannerController.addListener(_onControllerChanged);
    _monitor.startSession(modeLabel: _modeLabel);
    zx.startCameraProcessing();
  }

  /// Restarts the camera stream and laser line animation when switching tabs
  /// or returning to the scanner screen.
  Future<void> restartCameraLaser() async {
    await _scannerController.restartCameraLaser();
    if (mounted) {
      setState(() {
        result = null;
        _clearMultiResults();
      });
      _msiScanCoordinator.reset();
      _monitor.startSession(modeLabel: _modeLabel);
    }
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _scannerController
      ..removeListener(_onControllerChanged)
      ..dispose();
    zx.stopCameraProcessing();
    super.dispose();
  }

  /// Converts camera [ImageFormatGroup] to zxing [ImageFormat] integer.
  int _imageFormat(ImageFormatGroup group) {
    switch (group) {
      case ImageFormatGroup.yuv420:
        return zxing.ImageFormat.lum;
      case ImageFormatGroup.bgra8888:
        return zxing.ImageFormat.bgrx;
      case ImageFormatGroup.jpeg:
      case ImageFormatGroup.nv21:
        return zxing.ImageFormat.rgb;
      case ImageFormatGroup.unknown:
        return zxing.ImageFormat.none;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Frame handler — live stream decode using zxing
  // ─────────────────────────────────────────────────────────────────────────

  Future<bool?> _handleFrame(CameraImage image, Rect? cropRect) async {
    // Ensure C++ isolate worker is fully started before sending frame
    await zx.startCameraProcessing();
    final ScanMonitorOperation operation = _monitor.startDecode(
      source: ScanMonitorSource.liveCamera,
      modeLabel: _modeLabel,
    );
    bool hasDecodedCode = false;

    final int cropLeft = cropRect?.left.round() ?? 0;
    final int cropTop = cropRect?.top.round() ?? 0;
    final int cropWidth = cropRect?.width.round() ?? image.width;
    final int cropHeight = cropRect?.height.round() ?? image.height;

    final DecodeParams params = DecodeParams(
      imageFormat: _imageFormat(image.format.group),
      format: Format.any,
      width: image.width,
      height: image.height,
      cropLeft: cropLeft,
      cropTop: cropTop,
      cropWidth: cropWidth,
      cropHeight: cropHeight,
      tryHarder: true,
      tryRotate: true,
      tryInverted: true,
      tryDownscale: true,
      isMultiScan: _scanMode == ScanMode.multiscan,
    );

    try {
      if (_scanMode == ScanMode.multiscan) {
        final Codes res = await zx
            .processCameraImageMulti(image, params)
            .timeout(
              const Duration(milliseconds: 1000),
              onTimeout: () => Codes(),
            );

        if (res.codes.isNotEmpty) {
          bool hasNewCode = false;
          int newCodeCount = 0;
          int duplicateCodeCount = 0;
          for (final Code c in res.codes) {
            if (c.isValid && c.text != null && c.text!.isNotEmpty) {
              hasDecodedCode = true;
              final String key = c.formatName ?? 'UNKNOWN';
              final String value = c.text!;

              if (addUniqueScanEntry(_scannedEntries, ScanEntry(key, value))) {
                hasNewCode = true;
                newCodeCount++;
              } else {
                duplicateCodeCount++;
              }
            }
          }
          final bool hasCompositeResult = _addCompositeResult(res.codes);
          if (hasCompositeResult) {
            hasNewCode = true;
            newCodeCount++;
          }
          _monitor.recordResults(
            uniqueCount: newCodeCount,
            duplicateCount: duplicateCodeCount,
          );
          if (hasNewCode && mounted) {
            setState(() {});
          }
        }
      } else {
        final Gs1CompositeNativeResult nativeCompositeResult =
            await _scanNativeCompositeFromFrame(image);
        if (nativeCompositeResult.hasResult) {
          hasDecodedCode = true;
          _monitor.recordResults(uniqueCount: 1);
          if (mounted) {
            setState(() {
              result = _createNativeCompositeCode(nativeCompositeResult);
            });
          }
          return true;
        }

        final Gs1CompositeAssembly? compositeAssembly =
            await _scanCompositeFromFrame(image, params);
        if (compositeAssembly != null) {
          hasDecodedCode = true;
          _monitor.recordResults(uniqueCount: 1);
          if (mounted) {
            setState(() {
              result = _createCompositeCode(compositeAssembly);
            });
          }
          return true;
        }

        final Code res = await zx
            .processCameraImage(image, params)
            .timeout(
              const Duration(milliseconds: 1000),
              onTimeout: () => Code(),
            );
        if (res.isValid) {
          hasDecodedCode = true;
          _monitor.recordResults(uniqueCount: 1);
          if (mounted) {
            setState(() {
              result = res;
            });
          }
          return true; // Single scan success -> pause stream
        }
        final bool hasMsiFallbackResult = await _processMsiScanFallback(res);
        if (hasMsiFallbackResult) {
          hasDecodedCode = true;
          return true;
        }
      }
    } catch (e) {
      debugPrint(
        _scanMode == ScanMode.multiscan
            ? 'processCameraImageMulti error: $e'
            : 'processCameraImage error: $e',
      );
    } finally {
      operation.finish(success: hasDecodedCode);
    }

    return false;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Gallery handler — file path decode using zxing
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _handleGalleryImage(String path) async {
    _monitor.startSession(modeLabel: '$_modeLabel / Gallery');
    final ScanMonitorOperation operation = _monitor.startDecode(
      source: ScanMonitorSource.galleryImage,
      modeLabel: '$_modeLabel / Gallery',
    );
    bool hasDecodedCode = false;

    final DecodeParams params = DecodeParams(
      imageFormat: zxing.ImageFormat.rgb,
      format: Format.any,
      tryHarder: true,
      tryInverted: true,
    );

    try {
      final Gs1CompositeNativeResult nativeCompositeResult =
          await Gs1CompositeNativeService.decodeBitmapPath(path);
      if (nativeCompositeResult.hasResult) {
        hasDecodedCode = true;
        _monitor.recordResults(uniqueCount: 1);
        if (mounted) {
          setState(() {
            result = _createNativeCompositeCode(nativeCompositeResult);
          });
        }
        return;
      }

      final Codes multiRes = await zx.readBarcodesImagePathString(
        path,
        DecodeParams(
          imageFormat: zxing.ImageFormat.rgb,
          format: _compositeCandidateFormats,
          tryHarder: true,
          tryInverted: true,
          tryRotate: true,
          isMultiScan: true,
          maxNumberOfSymbols: 8,
          maxSize: 1600,
        ),
      );
      final Gs1CompositeAssembly? compositeAssembly = _gs1CompositeAssembler
          .assemble(multiRes.codes);
      if (compositeAssembly != null) {
        hasDecodedCode = true;
        _monitor.recordResults(uniqueCount: 1);
        if (mounted) {
          setState(() {
            result = _createCompositeCode(compositeAssembly);
          });
        }
        return;
      }

      final Code res = await zx.readBarcodeImagePathString(path, params);
      if (res.isValid) {
        hasDecodedCode = true;
        _monitor.recordResults(uniqueCount: 1);
        if (mounted) {
          setState(() {
            result = res;
          });
        }
      } else {
        final bool hasMsiResult = await _processMsiImageFileFallback(path);
        if (hasMsiResult) {
          hasDecodedCode = true;
          _monitor.recordResults(uniqueCount: 1);
        } else if (mounted) {
          showScannerMessage(context, 'No valid code found in the image');
        }
      }
    } catch (e) {
      debugPrint('readBarcodeImagePathString error: $e');
      final bool hasMsiResult = await _processMsiImageFileFallback(path);
      if (hasMsiResult) {
        hasDecodedCode = true;
        _monitor.recordResults(uniqueCount: 1);
      } else if (mounted) {
        showScannerMessage(context, 'Failed to read image: $e');
      }
    } finally {
      operation.finish(success: hasDecodedCode);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // 1. Single Scan result screen
    if (_scanMode == ScanMode.single &&
        result != null &&
        result?.isValid == true) {
      return ScanResultPage(
        results: <ScanEntry>[
          ScanEntry(result?.formatName ?? '', result?.text ?? ''),
        ],
        monitorSnapshot: _monitor.snapshot(resultCount: 1),
        onScanAgain: () {
          setState(() {
            result = null;
          });
          _msiScanCoordinator.reset();
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
          _msiScanCoordinator.reset();
          _monitor.startSession(modeLabel: _modeLabel);
          _resumeScan();
        },
      );
    }

    return ScannerLiveScaffold(
      preview: ScannerCameraPreview(
        tabIndex: 0,
        controller: _scannerController,
        scanMode: _scanMode,
        scanDelay: const Duration(milliseconds: 50),
        frameIntervalMs: _scanMode == ScanMode.single ? 500 : 150,
        onFrameCaptured: _handleFrame,
        onGalleryImageSelected: _handleGalleryImage,
        onControllerCreated: (CameraController? cam, Exception? err) {
          if (err != null && mounted) {
            showScannerMessage(context, 'Camera error: $err');
          }
        },
        resolution: ResolutionPreset.high,
      ),
      scanMode: _scanMode,
      resultCount: _scannedEntries.length,
      onShowResults: _showMultiResults,
      onModeChanged: _changeMode,
      onGalleryImageSelected: _handleGalleryImage,
      showResumeButton:
          _scanMode == ScanMode.single &&
          _scannerController.isPaused &&
          result == null,
      onResumeScan: _resumeScan,
    );
  }

  Future<bool> _processMsiScanFallback(Code? code) async {
    if (code == null) return false;

    final MsiScanCandidate? candidate = await _msiScanCoordinator
        .scanProcessedImage(code);
    if (candidate == null || !mounted) return false;

    _monitor.recordResults(uniqueCount: 1);
    setState(() {
      result = _createMsiCode(candidate);
    });
    return true;
  }

  Future<bool> _processMsiImageFileFallback(String path) async {
    final MsiScanCandidate? candidate = await _msiScanCoordinator.scanImageFile(
      path,
    );
    if (candidate == null || !mounted) return false;

    setState(() {
      result = _createMsiCode(candidate);
    });
    return true;
  }

  Code _createMsiCode(MsiScanCandidate candidate) {
    return Code(
      text: candidate.text,
      format: FormatMsi.msiCode,
      isValid: true,
      duration: candidate.durationMs,
    );
  }

  Future<Gs1CompositeAssembly?> _scanCompositeFromFrame(
    CameraImage image,
    DecodeParams baseParams,
  ) async {
    final Codes res = await zx
        .processCameraImageMulti(
          image,
          DecodeParams(
            imageFormat: baseParams.imageFormat,
            format: _compositeCandidateFormats,
            width: baseParams.width,
            height: baseParams.height,
            cropLeft: baseParams.cropLeft,
            cropTop: baseParams.cropTop,
            cropWidth: baseParams.cropWidth,
            cropHeight: baseParams.cropHeight,
            tryHarder: true,
            tryRotate: true,
            tryInverted: true,
            tryDownscale: true,
            isMultiScan: true,
            maxNumberOfSymbols: 8,
            maxSize: 1200,
          ),
        )
        .timeout(const Duration(milliseconds: 1200), onTimeout: () => Codes());

    return _gs1CompositeAssembler.assemble(res.codes);
  }

  Future<Gs1CompositeNativeResult> _scanNativeCompositeFromFrame(
    CameraImage image,
  ) async {
    if (image.planes.isEmpty) {
      return const Gs1CompositeNativeResult.empty(
        warning: 'Camera frame has no planes',
      );
    }

    return Gs1CompositeNativeService.decodeYuvLuminance(
      image.planes.first.bytes,
      imageWidth: image.width,
      imageHeight: image.height,
      rowStride: image.planes.first.bytesPerRow,
      imageFormatGroup: image.format.group.name,
    );
  }

  bool _addCompositeResult(List<Code> codes) {
    final Gs1CompositeAssembly? assembly = _gs1CompositeAssembler.assemble(
      codes,
    );
    if (assembly == null) return false;

    return addUniqueScanEntry(
      _scannedEntries,
      ScanEntry(assembly.title, assembly.toDisplayText()),
    );
  }

  Code _createCompositeCode(Gs1CompositeAssembly assembly) {
    return Code(
      text: assembly.toDisplayText(),
      format: CustomFormat.gs1CompositePoc,
      isValid: true,
      duration: 0,
    );
  }

  Code _createNativeCompositeCode(Gs1CompositeNativeResult result) {
    return Code(
      text: result.text,
      format: CustomFormat.gs1CompositePoc,
      isValid: true,
      duration: result.durationMs,
    );
  }

  void _resumeScan() {
    _scannerController.resumeStream(
      (CameraImage image) => _handleFrame(image, null),
    );
  }

  void _resetScanState() {
    _msiScanCoordinator.reset();
    _monitor.startSession(modeLabel: _modeLabel);
  }

  void _changeMode(ScanMode mode) {
    setState(() {
      _scanMode = mode;
      result = null;
      _clearMultiResults();
    });
    _resetScanState();
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

  static const int _compositeCandidateFormats =
      Format.code128 |
      Format.ean8 |
      Format.ean13 |
      Format.upca |
      Format.upce |
      Format.dataBar |
      Format.dataBarExpanded |
      CustomFormat.dataBarLimited |
      Format.pdf417;
}
