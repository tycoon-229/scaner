import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart' as zxing;
import 'package:flutter_zxing/flutter_zxing.dart' hide ImageFormat;

import 'package:flutter_zxing_example/extensions/code_format_extensions.dart';
import 'package:flutter_zxing_example/services/msi_scanner_service.dart';
import 'package:flutter_zxing_example/utils/scan_entries.dart';
import 'package:flutter_zxing_example/widgets/scan_result_widget.dart';
import 'package:flutter_zxing_example/widgets/camera_scanner/camera_scanner.dart';
import 'package:flutter_zxing_example/widgets/scanner_camera_preview.dart';
import 'package:flutter_zxing_example/widgets/scanner_live_scaffold.dart';
import 'package:flutter_zxing_example/widgets/scanner_message.dart';

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

  Code? result;
  bool _isProcessingMsiFallback = false;
  DateTime _lastMsiFallbackAttempt = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastMsiCandidate;
  int _msiCandidateMatchCount = 0;

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

    if (_scanMode == ScanMode.multiscan) {
      try {
        final Codes res = await zx
            .processCameraImageMulti(image, params)
            .timeout(
              const Duration(milliseconds: 1000),
              onTimeout: () => Codes(),
            );

        if (res.codes.isNotEmpty) {
          bool hasNewCode = false;
          for (final Code c in res.codes) {
            if (c.isValid && c.text != null && c.text!.isNotEmpty) {
              final String key = c.format?.name ?? 'UNKNOWN';
              final String value = c.text!;

              if (addUniqueScanEntry(_scannedEntries, ScanEntry(key, value))) {
                hasNewCode = true;
              }
            }
          }
          if (hasNewCode && mounted) {
            setState(() {});
          }
        }
      } catch (e) {
        debugPrint('processCameraImageMulti error: $e');
      }
    } else {
      try {
        final Code res = await zx
            .processCameraImage(image, params)
            .timeout(
              const Duration(milliseconds: 1000),
              onTimeout: () => Code(),
            );
        _processMsiScanFallback(res);
        if (res.isValid) {
          if (mounted) {
            setState(() {
              result = res;
            });
          }
          return true; // Single scan success -> pause stream
        }
      } catch (e) {
        debugPrint('processCameraImage error: $e');
      }
    }

    return false;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Gallery handler — file path decode using zxing
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _handleGalleryImage(String path) async {
    final DecodeParams params = DecodeParams(
      imageFormat: zxing.ImageFormat.rgb,
      format: Format.any,
      tryHarder: true,
      tryInverted: true,
    );

    final Code res = await zx.readBarcodeImagePathString(path, params);
    if (res.isValid) {
      if (mounted) {
        setState(() {
          result = res;
        });
      }
    } else {
      if (mounted) {
        showScannerMessage(context, 'No valid code found in the image');
      }
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
          ScanEntry(result?.format?.name ?? '', result?.text ?? ''),
        ],
        onScanAgain: () {
          setState(() {
            result = null;
          });
          _resumeScan();
        },
      );
    }

    // 2. Multi Scan result screen
    if (_scanMode == ScanMode.multiscan && _showMultiResultScreen) {
      return ScanResultPage(
        results: _scannedEntries,
        onScanAgain: () {
          setState(_clearMultiResults);
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
      showResumeButton:
          _scanMode == ScanMode.single &&
          _scannerController.isPaused &&
          result == null,
      onResumeScan: _resumeScan,
    );
  }

  Future<void> _processMsiScanFallback(Code? code) async {
    final now = DateTime.now();

    if (now.difference(_lastMsiFallbackAttempt).inMilliseconds < 150) return;

    if (code?.imageBytes != null && code!.imageBytes!.isNotEmpty) {
      if (_isProcessingMsiFallback) return;

      _lastMsiFallbackAttempt = now;
      _isProcessingMsiFallback = true;

      final String? msiCode = await MsiScannerService.decodeMsiYuv(
        code.imageBytes!,
        imageWidth: code.imageWidth ?? 0,
        imageHeight: code.imageHeight ?? 0,
      );

      if (mounted && msiCode != null && msiCode.isNotEmpty) {
        if (msiCode == _lastMsiCandidate) {
          _msiCandidateMatchCount++;
        } else {
          _lastMsiCandidate = msiCode;
          _msiCandidateMatchCount = 1;
        }

        if (_msiCandidateMatchCount >= 2) {
          _lastMsiCandidate = null;
          _msiCandidateMatchCount = 0;

          setState(() {
            result = Code(
              text: msiCode,
              format: FormatMsi.msiCode,
              isValid: true,
              duration: now.difference(_lastMsiFallbackAttempt).inMilliseconds,
            );
          });
        }
      }
      _isProcessingMsiFallback = false;
    }
  }

  void _resumeScan() {
    _scannerController.resumeStream(
      (CameraImage image) => _handleFrame(image, null),
    );
  }

  void _changeMode(ScanMode mode) {
    setState(() {
      _scanMode = mode;
      result = null;
      _clearMultiResults();
    });
  }

  void _clearMultiResults() {
    _scannedEntries.clear();
    _showMultiResultScreen = false;
  }

  void _showMultiResults() {
    setState(() => _showMultiResultScreen = true);
  }
}
