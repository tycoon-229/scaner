import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart' as zxing;
import 'package:flutter_zxing/flutter_zxing.dart' hide ImageFormat;

import 'package:poc_multi_scan/extensions/code_format_extensions.dart';
import 'package:poc_multi_scan/services/native_scanners/gs1/gs1_composite_assembler.dart';
import 'package:poc_multi_scan/services/native_scanners/gs1/gs1_detected_code.dart';
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

  ScanEntry? _pendingCompositeCarrier;
  DateTime? _pendingCompositeCarrierAt;
  DateTime? _lastEmptyCompositeLogAt;

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
      _clearPendingCompositeCarrier();
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

        bool hasNewCode = false;
        int newCodeCount = 0;
        int duplicateCodeCount = 0;

        if (res.codes.isNotEmpty) {
          for (final Code c in res.codes) {
            final ScanEntry? entry = _scanEntryForCode(c);
            if (entry != null) {
              hasDecodedCode = true;

              if (addUniqueScanEntry(_scannedEntries, entry)) {
                logScanResult(
                  'ZXing',
                  entry,
                  mode: _modeLabel,
                  origin: 'live-camera',
                );
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
        }

        final Gs1CompositeNativeResult nativeCompositeResult =
            await _scanNativeCompositeFromFrame(image);
        if (nativeCompositeResult.hasResult) {
          hasDecodedCode = true;
          if (_addNativeCompositeResult(nativeCompositeResult)) {
            hasNewCode = true;
            newCodeCount++;
          } else {
            duplicateCodeCount++;
          }
        }

        if (newCodeCount > 0 || duplicateCodeCount > 0) {
          _monitor.recordResults(
            uniqueCount: newCodeCount,
            duplicateCount: duplicateCodeCount,
          );
        }
        if (hasNewCode && mounted) {
          setState(() {});
        }
      } else {
        final Code res = await _scanSingleFromFrame(image, params);
        final ScanEntry? entry = _scanEntryForCode(res);
        if (entry != null) {
          final bool likelyCompositeCarrier = _isLikelyCompositeLinearCarrier(
            res,
            entry,
          );
          if (likelyCompositeCarrier) {
            final bool shouldRetryComposite = _shouldWaitForCompositeRetry(
              entry,
            );
            final bool hasCompositeResult = await _trySetSingleCompositeResult(
              image,
              params,
              origin: 'live-camera',
            );
            if (hasCompositeResult) {
              hasDecodedCode = true;
              return true;
            }

            if (shouldRetryComposite && !_isCompositeRetryExpired(entry)) {
              return false;
            }
            if (shouldRetryComposite) {
              debugPrint(
                '[ZXing] PDF417 component not found during retry window; returning current Code128 carrier: format="${entry.key}", text="${entry.value}"',
              );
              _clearPendingCompositeCarrier();
            }
          } else {
            _clearPendingCompositeCarrier();
          }

          hasDecodedCode = true;
          _monitor.recordResults(uniqueCount: 1);
          if (mounted) {
            setState(() {
              logScanResult(
                'ZXing',
                entry,
                mode: _modeLabel,
                origin: 'live-camera',
              );
              result = _createCodeFromEntry(res, entry);
            });
          }
          return true; // Single scan success -> pause stream
        }

        final bool hasCompositeResult = await _trySetSingleCompositeResult(
          image,
          params,
          origin: 'live-camera/no-linear',
        );
        if (hasCompositeResult) {
          hasDecodedCode = true;
          return true;
        }

        final bool hasPendingCarrierResult = _trySetPendingCarrierResult();
        if (hasPendingCarrierResult) {
          hasDecodedCode = true;
          return true;
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
            final Code code = _createNativeCompositeCode(nativeCompositeResult);
            logScanResult(
              'ZXing',
              ScanEntry(code.formatName ?? '', code.text ?? ''),
              mode: _modeLabel,
              origin: 'gallery/native-composite',
            );
            result = code;
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
          .assemble(multiRes.codes.map(_detectedCodeFromZxing).toList());
      if (compositeAssembly != null) {
        hasDecodedCode = true;
        _monitor.recordResults(uniqueCount: 1);
        if (mounted) {
          setState(() {
            final Code code = _createCompositeCode(compositeAssembly);
            logScanResult(
              'ZXing',
              ScanEntry(code.formatName ?? '', code.text ?? ''),
              mode: _modeLabel,
              origin: 'gallery/composite',
            );
            result = code;
          });
        }
        return;
      }

      final Code res = await zx.readBarcodeImagePathString(path, params);
      final ScanEntry? entry = _scanEntryForCode(res);
      if (entry != null) {
        hasDecodedCode = true;
        _monitor.recordResults(uniqueCount: 1);
        if (mounted) {
          setState(() {
            logScanResult('ZXing', entry, mode: _modeLabel, origin: 'gallery');
            result = _createCodeFromEntry(res, entry);
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
          _clearPendingCompositeCarrier();
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
          _clearPendingCompositeCarrier();
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
      final Code code = _createMsiCode(candidate);
      logScanResult(
        'ZXing',
        ScanEntry(code.formatName ?? '', code.text ?? ''),
        mode: _modeLabel,
        origin: 'live-camera/msi-fallback',
      );
      result = code;
    });
    return true;
  }

  Future<bool> _processMsiImageFileFallback(String path) async {
    final MsiScanCandidate? candidate = await _msiScanCoordinator.scanImageFile(
      path,
    );
    if (candidate == null || !mounted) return false;

    setState(() {
      final Code code = _createMsiCode(candidate);
      logScanResult(
        'ZXing',
        ScanEntry(code.formatName ?? '', code.text ?? ''),
        mode: _modeLabel,
        origin: 'gallery/msi-fallback',
      );
      result = code;
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

  Future<Code> _scanSingleFromFrame(
    CameraImage image,
    DecodeParams baseParams,
  ) async {
    for (final MapEntry<String, DecodeParams> pass in _singleDecodePasses(
      image,
      baseParams,
    )) {
      final Code code = await zx
          .processCameraImage(image, pass.value)
          .timeout(const Duration(milliseconds: 650), onTimeout: () => Code());
      final ScanEntry? entry = _scanEntryForCode(code);
      if (entry != null) {
        if (pass.key != 'crop') {
          debugPrint(
            '[ZXing] Single decode fallback pass="${pass.key}" found: format="${entry.key}", text="${entry.value}"',
          );
        }
        return code;
      }
    }

    return Code();
  }

  List<MapEntry<String, DecodeParams>> _singleDecodePasses(
    CameraImage image,
    DecodeParams baseParams,
  ) {
    DecodeParams pass({
      required int cropLeft,
      required int cropTop,
      required int cropWidth,
      required int cropHeight,
      int maxSize = 1600,
    }) {
      return DecodeParams(
        imageFormat: baseParams.imageFormat,
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
        isMultiScan: false,
        maxSize: maxSize,
      );
    }

    final List<MapEntry<String, DecodeParams>> passes =
        <MapEntry<String, DecodeParams>>[
          MapEntry<String, DecodeParams>('crop', baseParams),
        ];

    final bool baseIsFullFrame =
        baseParams.cropLeft == 0 &&
        baseParams.cropTop == 0 &&
        baseParams.cropWidth == image.width &&
        baseParams.cropHeight == image.height;
    if (baseIsFullFrame) return passes;

    final int upperHeight = (image.height * 0.70).round().clamp(
      1,
      image.height,
    );
    final int middleTop = (image.height * 0.10).round().clamp(
      0,
      image.height - 1,
    );
    final int middleHeight = (image.height * 0.82).round().clamp(
      1,
      image.height - middleTop,
    );

    passes.addAll(<MapEntry<String, DecodeParams>>[
      MapEntry<String, DecodeParams>(
        'full',
        pass(
          cropLeft: 0,
          cropTop: 0,
          cropWidth: image.width,
          cropHeight: image.height,
        ),
      ),
      MapEntry<String, DecodeParams>(
        'upper',
        pass(
          cropLeft: 0,
          cropTop: 0,
          cropWidth: image.width,
          cropHeight: upperHeight,
        ),
      ),
      MapEntry<String, DecodeParams>(
        'middle',
        pass(
          cropLeft: 0,
          cropTop: middleTop,
          cropWidth: image.width,
          cropHeight: middleHeight,
        ),
      ),
    ]);

    return passes;
  }

  Future<bool> _trySetSingleCompositeResult(
    CameraImage image,
    DecodeParams params, {
    required String origin,
  }) async {
    final Gs1CompositeNativeResult nativeCompositeResult =
        await _scanNativeCompositeFromFrame(image);
    if (nativeCompositeResult.hasResult) {
      _monitor.recordResults(uniqueCount: 1);
      if (mounted) {
        setState(() {
          final Code code = _createNativeCompositeCode(nativeCompositeResult);
          logScanResult(
            'ZXing',
            ScanEntry(code.formatName ?? '', code.text ?? ''),
            mode: _modeLabel,
            origin: '$origin/native-composite',
          );
          _clearPendingCompositeCarrier();
          result = code;
        });
      }
      return true;
    }

    final Gs1CompositeAssembly? compositeAssembly =
        await _scanCompositeFromFrame(image, params);
    if (compositeAssembly != null) {
      _monitor.recordResults(uniqueCount: 1);
      if (mounted) {
        setState(() {
          final Code code = _createCompositeCode(compositeAssembly);
          logScanResult(
            'ZXing',
            ScanEntry(code.formatName ?? '', code.text ?? ''),
            mode: _modeLabel,
            origin: '$origin/composite',
          );
          _clearPendingCompositeCarrier();
          result = code;
        });
      }
      return true;
    }

    return false;
  }

  Future<Gs1CompositeAssembly?> _scanCompositeFromFrame(
    CameraImage image,
    DecodeParams baseParams,
  ) async {
    final List<Code> candidates = <Code>[];

    for (final DecodeParams params in _compositeDecodePasses(
      image,
      baseParams,
    )) {
      final Codes res = await zx
          .processCameraImageMulti(image, params)
          .timeout(const Duration(milliseconds: 800), onTimeout: () => Codes());

      candidates.addAll(res.codes);
      final Gs1CompositeAssembly? assembly = _gs1CompositeAssembler.assemble(
        candidates.map(_detectedCodeFromZxing).toList(),
      );
      if (assembly != null) {
        return assembly;
      }
    }

    _logCompositeCandidates(candidates);
    return null;
  }

  List<DecodeParams> _compositeDecodePasses(
    CameraImage image,
    DecodeParams baseParams,
  ) {
    DecodeParams pass({
      required int cropLeft,
      required int cropTop,
      required int cropWidth,
      required int cropHeight,
      int maxSize = 1600,
    }) {
      return DecodeParams(
        imageFormat: baseParams.imageFormat,
        format: _compositeCandidateFormats,
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
        isMultiScan: true,
        maxNumberOfSymbols: 8,
        maxSize: maxSize,
      );
    }

    final int upperHeight = (image.height * 0.65).round().clamp(
      1,
      image.height,
    );
    final int middleTop = (image.height * 0.12).round().clamp(
      0,
      image.height - 1,
    );
    final int middleHeight = (image.height * 0.76).round().clamp(
      1,
      image.height - middleTop,
    );

    final List<DecodeParams> passes = <DecodeParams>[
      pass(
        cropLeft: 0,
        cropTop: 0,
        cropWidth: image.width,
        cropHeight: image.height,
      ),
      pass(
        cropLeft: 0,
        cropTop: 0,
        cropWidth: image.width,
        cropHeight: upperHeight,
      ),
      pass(
        cropLeft: 0,
        cropTop: middleTop,
        cropWidth: image.width,
        cropHeight: middleHeight,
      ),
    ];

    if (baseParams.cropWidth > 0 && baseParams.cropHeight > 0) {
      final int cropLeft = baseParams.cropLeft;
      final int cropTop = baseParams.cropTop;
      final int cropWidth = baseParams.cropWidth;
      final int cropHeight = baseParams.cropHeight;
      final int expandedTop = (cropTop - cropHeight * 0.65).round().clamp(
        0,
        image.height - 1,
      );
      final int expandedBottom = (cropTop + cropHeight).clamp(1, image.height);

      passes.addAll(<DecodeParams>[
        pass(
          cropLeft: cropLeft,
          cropTop: cropTop,
          cropWidth: cropWidth,
          cropHeight: cropHeight,
          maxSize: 1200,
        ),
        pass(
          cropLeft: cropLeft,
          cropTop: expandedTop,
          cropWidth: cropWidth,
          cropHeight: expandedBottom - expandedTop,
          maxSize: 1400,
        ),
      ]);
    }

    return passes;
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
    ).timeout(
      const Duration(milliseconds: 1200),
      onTimeout: () => const Gs1CompositeNativeResult.empty(
        warning: 'GS1 Composite native scan timed out',
      ),
    );
  }

  bool _addCompositeResult(List<Code> codes) {
    final Gs1CompositeAssembly? assembly = _gs1CompositeAssembler.assemble(
      codes.map(_detectedCodeFromZxing).toList(),
    );
    if (assembly == null) return false;

    final ScanEntry entry = ScanEntry(assembly.title, assembly.resultText);
    final bool added = addUniqueScanEntry(_scannedEntries, entry);
    if (added) {
      logScanResult(
        'ZXing',
        entry,
        mode: _modeLabel,
        origin: 'live-camera/composite',
      );
    }
    return added;
  }

  bool _addNativeCompositeResult(Gs1CompositeNativeResult result) {
    final String text = _nativeCompositeResultText(result);
    if (!result.hasResult || text.isEmpty) return false;

    final String typeEstimate = result.typeEstimate?.trim() ?? '';
    final String title = typeEstimate.isEmpty
        ? 'GS1 Composite Native POC'
        : 'GS1 Composite Native POC ($typeEstimate)';

    final ScanEntry entry = ScanEntry(title, text);
    final bool added = addUniqueScanEntry(_scannedEntries, entry);
    if (added) {
      logScanResult(
        'ZXing',
        entry,
        mode: _modeLabel,
        origin: 'live-camera/native-composite',
      );
    }
    return added;
  }

  Gs1DetectedCode _detectedCodeFromZxing(Code code) {
    final Position? position = code.position;
    return Gs1DetectedCode(
      text: code.text,
      format: code.format,
      isValid: code.isValid,
      rawBytes: code.rawBytes,
      position: position == null
          ? null
          : Gs1DetectedPosition(
              imageWidth: position.imageWidth,
              imageHeight: position.imageHeight,
              topLeftX: position.topLeftX,
              topLeftY: position.topLeftY,
              topRightX: position.topRightX,
              topRightY: position.topRightY,
              bottomLeftX: position.bottomLeftX,
              bottomLeftY: position.bottomLeftY,
              bottomRightX: position.bottomRightX,
              bottomRightY: position.bottomRightY,
            ),
    );
  }

  Code _createCompositeCode(Gs1CompositeAssembly assembly) {
    return Code(
      text: assembly.resultText,
      format: CustomFormat.gs1CompositePoc,
      isValid: true,
      duration: 0,
    );
  }

  Code _createNativeCompositeCode(Gs1CompositeNativeResult result) {
    return Code(
      text: _nativeCompositeResultText(result),
      format: CustomFormat.gs1CompositePoc,
      isValid: true,
      duration: result.durationMs,
    );
  }

  ScanEntry? _scanEntryForCode(Code code) {
    if (!code.isValid || code.text == null || code.text!.isEmpty) return null;
    if (_isUnpairedCompositeComponent(code)) return null;

    final String key = code.formatName ?? 'UNKNOWN';
    final String value =
        Gs1ElementStringParser.tryFormatElementString(
          code.text!,
          fallbackFormat: code.format,
          requireGs1Marker: !_looksLikeGs1Format(key),
        ) ??
        code.text!;

    return ScanEntry(key, value);
  }

  Code _createCodeFromEntry(Code source, ScanEntry entry) {
    return Code(
      text: entry.value,
      format: source.format,
      isValid: true,
      duration: source.duration,
      rawBytes: source.rawBytes,
      position: source.position,
      isInverted: source.isInverted,
      isMirrored: source.isMirrored,
      imageBytes: source.imageBytes,
      imageWidth: source.imageWidth,
      imageHeight: source.imageHeight,
    );
  }

  bool _isUnpairedCompositeComponent(Code code) {
    if (code.format != Format.pdf417 || code.text == null) return false;
    final String text = code.text!;
    final bool hasGs1Payload =
        Gs1ElementStringParser.tryFormatElementString(
          text,
          fallbackFormat: code.format,
        ) !=
        null;
    if (hasGs1Payload) return false;

    return Gs1ElementStringParser.looksLikeEscapedBinaryControlPayload(text);
  }

  bool _isLikelyCompositeLinearCarrier(Code code, ScanEntry entry) {
    final String formatName = (code.formatName ?? entry.key).toUpperCase();
    if (code.format != Format.code128 && !formatName.contains('CODE128')) {
      return false;
    }

    final List<Gs1Element> elements = Gs1ElementStringParser.parse(
      entry.value,
      fallbackFormat: Gs1DetectedFormat.code128,
    );
    return elements.length == 1 && elements.single.ai == '01';
  }

  bool _shouldWaitForCompositeRetry(ScanEntry entry) {
    final DateTime now = DateTime.now();
    if (_pendingCompositeCarrier?.value != entry.value) {
      _pendingCompositeCarrier = entry;
      _pendingCompositeCarrierAt = now;
      debugPrint(
        '[ZXing] Code128 looks like GS1 Composite carrier; retrying briefly for PDF417 component: format="${entry.key}", text="${entry.value}"',
      );
      return true;
    }

    final DateTime firstSeen = _pendingCompositeCarrierAt ?? now;
    if (now.difference(firstSeen) < _compositeRetryDuration) {
      return true;
    }

    debugPrint(
      '[ZXing] PDF417 component not found during retry window; returning Code128 carrier: format="${entry.key}", text="${entry.value}"',
    );
    _clearPendingCompositeCarrier();
    return false;
  }

  bool _isCompositeRetryExpired(ScanEntry entry) {
    final DateTime? firstSeen = _pendingCompositeCarrierAt;
    if (_pendingCompositeCarrier?.value != entry.value || firstSeen == null) {
      return false;
    }
    return DateTime.now().difference(firstSeen) >= _compositeRetryDuration;
  }

  bool _trySetPendingCarrierResult() {
    final ScanEntry? entry = _pendingCompositeCarrier;
    final DateTime? firstSeen = _pendingCompositeCarrierAt;
    if (entry == null || firstSeen == null) return false;
    if (DateTime.now().difference(firstSeen) < _compositeRetryDuration) {
      return false;
    }

    debugPrint(
      '[ZXing] PDF417 component not found during retry window; returning pending Code128 carrier: format="${entry.key}", text="${entry.value}"',
    );
    _clearPendingCompositeCarrier();
    _monitor.recordResults(uniqueCount: 1);
    if (mounted) {
      setState(() {
        logScanResult(
          'ZXing',
          entry,
          mode: _modeLabel,
          origin: 'live-camera/pending-carrier',
        );
        result = Code(
          text: entry.value,
          format: Format.code128,
          isValid: true,
          duration: DateTime.now().difference(firstSeen).inMilliseconds,
        );
      });
    }
    return true;
  }

  void _clearPendingCompositeCarrier() {
    _pendingCompositeCarrier = null;
    _pendingCompositeCarrierAt = null;
  }

  void _logCompositeCandidates(List<Code> candidates) {
    if (candidates.isEmpty) {
      final DateTime now = DateTime.now();
      final DateTime? lastLogAt = _lastEmptyCompositeLogAt;
      if (lastLogAt == null ||
          now.difference(lastLogAt) >= _emptyCompositeLogInterval) {
        _lastEmptyCompositeLogAt = now;
        debugPrint('[ZXing] Composite scan found no candidates.');
      }
      return;
    }

    final String summary = candidates
        .where(
          (Code code) =>
              code.isValid &&
              ((code.text?.isNotEmpty ?? false) ||
                  (code.rawBytes?.isNotEmpty ?? false)),
        )
        .map(_describeCompositeCandidate)
        .join(' | ');
    if (summary.isEmpty) {
      debugPrint('[ZXing] Composite scan found only invalid candidates.');
      return;
    }

    debugPrint('[ZXing] Composite candidates without pair: $summary');
  }

  String _describeCompositeCandidate(Code code) {
    final String text = code.text ?? '';
    final List<int>? rawBytes = code.rawBytes;
    final String rawSummary = rawBytes == null || rawBytes.isEmpty
        ? 'rawBytes=null'
        : 'rawLen=${rawBytes.length}, rawHex=[${_hexBytes(rawBytes)}], rawB64=${base64Encode(rawBytes)}';

    return '${code.formatName ?? code.format}: "${_visibleControlChars(text)}", textHex=[${_hexText(text)}], $rawSummary';
  }

  String _hexText(String value) {
    return value.runes
        .map((int rune) => rune.toRadixString(16).padLeft(2, '0'))
        .join(' ');
  }

  String _hexBytes(List<int> bytes) {
    return bytes
        .map((int byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join(' ');
  }

  String _visibleControlChars(String value) {
    final StringBuffer buffer = StringBuffer();
    for (final int rune in value.runes) {
      switch (rune) {
        case 8:
          buffer.write('<BS>');
        case 10:
          buffer.write('<LF>');
        case 13:
          buffer.write('<CR>');
        case 29:
          buffer.write('<GS>');
        default:
          if (rune < 32 || rune == 127) {
            buffer.write('<U+${rune.toRadixString(16).toUpperCase()}>');
          } else {
            buffer.writeCharCode(rune);
          }
      }
    }
    return buffer.toString();
  }

  bool _looksLikeGs1Format(String formatName) {
    final String normalized = formatName.toUpperCase();
    return normalized.contains('GS1') || normalized.contains('COMPOSITE');
  }

  String _nativeCompositeResultText(Gs1CompositeNativeResult result) {
    final Object? rawElements = result.raw['elements'];
    if (rawElements is List) {
      final List<Gs1Element> elements = <Gs1Element>[];
      for (final Object? rawElement in rawElements) {
        if (rawElement is! Map) continue;
        final String? ai = rawElement['ai'] as String?;
        final String? value = rawElement['value'] as String?;
        if (ai == null || value == null) continue;
        elements.add(
          Gs1Element(
            ai: ai,
            value: value,
            title: rawElement['title'] as String? ?? 'AI $ai',
          ),
        );
      }
      final String formatted = Gs1ElementStringParser.formatElements(elements);
      if (formatted.isNotEmpty) return formatted;
    }

    return result.text ?? '';
  }

  void _resumeScan() {
    _scannerController.resumeStream(
      (CameraImage image) => _handleFrame(image, null),
    );
  }

  void _resetScanState() {
    _clearPendingCompositeCarrier();
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

  static const Duration _compositeRetryDuration = Duration(milliseconds: 900);
  static const Duration _emptyCompositeLogInterval = Duration(seconds: 5);
}
