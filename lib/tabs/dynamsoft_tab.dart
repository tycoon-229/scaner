import 'package:camera/camera.dart';
import 'package:dynamsoft_capture_vision_flutter/dynamsoft_capture_vision_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:poc_multi_scan/config/license_keys.dart';
import 'package:poc_multi_scan/services/native_scanners/gs1/gs1_composite_assembler.dart';
import 'package:poc_multi_scan/services/native_scanners/gs1/gs1_detected_code.dart';
import 'package:poc_multi_scan/utils/scan_entries.dart';
import 'package:poc_multi_scan/utils/scan_monitor.dart';
import 'package:poc_multi_scan/widgets/scan_result_widget.dart';
import 'package:poc_multi_scan/widgets/camera_scanner/camera_scanner.dart';
import 'package:poc_multi_scan/widgets/scanner_camera_preview.dart';
import 'package:poc_multi_scan/widgets/scanner_live_scaffold.dart';
import 'package:poc_multi_scan/widgets/scanner_message.dart';



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

      // Retrieve valid template names from native engine dynamically
      List<String> availableTemplates = <String>[];
      try {
        availableTemplates = await CaptureVisionRouter.instance.getTemplateNames();
        debugPrint('[DynamsoftTab] Available template names in CVR: $availableTemplates');
      } catch (e) {
        debugPrint('[DynamsoftTab] Could not get template names: $e');
      }

      final List<String> templatesToUpdate = availableTemplates.isNotEmpty
          ? availableTemplates
          : <String>[
              EnumPresetTemplate.readBarcodesReadRateFirst,
              EnumPresetTemplate.readBarcodes,
              EnumPresetTemplate.defaultTemplate,
              '',
            ];

      for (final String templateName in templatesToUpdate) {
        try {
          final SimplifiedCaptureVisionSettings? settings =
              await CaptureVisionRouter.instance.getSimplifiedSettings(
                templateName,
              );
          if (settings?.barcodeSettings != null) {
            settings!.barcodeSettings!.barcodeFormatIds =
                EnumBarcodeFormat.all & ~EnumBarcodeFormat.pharmacode;
            settings.barcodeSettings!.expectedBarcodesCount = 0;
            settings.barcodeSettings!.localizationModes =
                <EnumLocalizationMode>[
                  EnumLocalizationMode.lines,
                  EnumLocalizationMode.connectedBlocks,
                  EnumLocalizationMode.scanDirectly,
                  EnumLocalizationMode.statistics,
                  EnumLocalizationMode.oneDFastScan,
                ];
            settings.barcodeSettings!.deblurModes = <EnumDeblurMode>[
              EnumDeblurMode.directBinarization,
              EnumDeblurMode.thresholdBinarization,
              EnumDeblurMode.basedOnLocBin,
            ];
            settings.barcodeSettings!.scaleDownThreshold = 1024;
            await CaptureVisionRouter.instance.updateSettings(
              templateName,
              settings,
            );
            debugPrint(
              '[DynamsoftTab] Updated template "$templateName": formats=${settings.barcodeSettings!.barcodeFormatIds}',
            );
          }
        } catch (e) {
          debugPrint(
            '[DynamsoftTab] Error updating template "$templateName": $e',
          );
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
      
      if (barcodes.isNotEmpty) {
        debugPrint(
          '[DynamsoftTab] 🔍 Raw frame decoded ${barcodes.length} item(s): '
          '${barcodes.map((b) => "${b.formatString}: '${b.text}'").join(", ")}',
        );
      } else {
        return false;
      }

      // Filter out Pharmacode false positives
      barcodes.removeWhere((BarcodeResultItem b) {
        final String formatUpper = b.formatString.toUpperCase();
        return formatUpper.contains('PHARMACODE');
      });
      if (barcodes.isEmpty) return false;

      // 3b. Filter out barcodes that fall outside cropRect (viewfinder area)
      if (cropRect != null) {
        final Rect expandedCropRect = cropRect.inflate(30.0);
        barcodes.removeWhere((BarcodeResultItem b) {
          return !_isBarcodeInCropArea(
            b,
            expandedCropRect,
            image.width,
            image.height,
          );
        });
        if (barcodes.isEmpty) return false;
      }

      debugPrint(
        '[DynamsoftTab] === DECODED FRAME: ${barcodes.length} barcode item(s) ===',
      );
      for (int i = 0; i < barcodes.length; i++) {
        final BarcodeResultItem b = barcodes[i];
        final Quadrilateral loc = b.location;
        final String pts = loc.points.map((p) => '(${p.x},${p.y})').join(', ');
        debugPrint(
          '[DynamsoftTab] Item #$i: format=${b.formatString} (${b.format}), text="${b.text}", pts=[$pts]',
        );
      }

      hasDecodedCode = true;

      // 4. Try assembling GS1 Composite pair from decoded items
      final List<Gs1DetectedCode> codes = barcodes
          .map(_detectedCodeFromDynamsoft)
          .toList();
      final Gs1CompositeAssembly? compositeAssembly = _gs1CompositeAssembler
          .assemble(codes);

      debugPrint(
        '[DynamsoftTab] GS1 Composite assembly result: ${compositeAssembly != null ? "SUCCESS (${compositeAssembly.title} => ${compositeAssembly.resultText})" : "NULL (No composite pair assembled)"}',
      );

      if (compositeAssembly != null) {
        final ScanEntry entry = ScanEntry(
          compositeAssembly.title,
          compositeAssembly.resultText,
        );

        if (_scanMode == ScanMode.single) {
          logScanResult(
            'Dynamsoft',
            entry,
            mode: _modeLabel,
            origin: 'live-camera/composite',
          );
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
            logScanResult(
              'Dynamsoft',
              entry,
              mode: _modeLabel,
              origin: 'live-camera/composite',
            );
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

        logScanResult(
          'Dynamsoft',
          entry,
          mode: _modeLabel,
          origin: 'live-camera',
        );
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
          final ScanEntry e = _entryForBarcode(b);
          if (addUniqueScanEntry(_scannedEntries, e)) {
            logScanResult(
              'Dynamsoft',
              e,
              mode: _modeLabel,
              origin: 'live-camera',
            );
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

      final List<Gs1DetectedCode> codes = barcodes
          .map(_detectedCodeFromDynamsoft)
          .toList();
      final Gs1CompositeAssembly? compositeAssembly = _gs1CompositeAssembler
          .assemble(codes);

      if (compositeAssembly != null) {
        hasDecodedCode = true;
        _monitor.recordResults(uniqueCount: 1);
        final ScanEntry entry = ScanEntry(
          compositeAssembly.title,
          compositeAssembly.resultText,
        );
        logScanResult(
          'Dynamsoft',
          entry,
          mode: _modeLabel,
          origin: 'gallery/composite',
        );
        setState(() {
          _singleResult = entry;
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
        final ScanEntry entry = _entryForBarcode(selected);
        logScanResult('Dynamsoft', entry, mode: _modeLabel, origin: 'gallery');
        setState(() {
          _singleResult = entry;
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

  static Uint8List _yuv420ToNv21Direct(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final int ySize = width * height;
    final Uint8List nv21 = Uint8List(ySize + ySize ~/ 2);

    final Uint8List yBytes = image.planes[0].bytes;
    final Uint8List uBytes = image.planes[1].bytes;
    final Uint8List vBytes = image.planes[2].bytes;
    final int yRowStride = image.planes[0].bytesPerRow;
    final int uvPixelStride = image.planes[1].bytesPerPixel ?? 1;

    for (int row = 0; row < height; row++) {
      nv21.setRange(
        row * width,
        row * width + width,
        yBytes,
        row * yRowStride,
      );
    }

    int offset = ySize;
    for (int i = 0; i < uBytes.length; i += uvPixelStride) {
      if (offset + 1 >= nv21.length) break;
      nv21[offset++] = vBytes[i];
      nv21[offset++] = uBytes[i];
    }

    return nv21;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // CameraImage → Dynamsoft ImageData
  // ──────────────────────────────────────────────────────────────────────────

  Future<ImageData?> _buildImageData(CameraImage image) async {
    try {
      switch (image.format.group) {
        case ImageFormatGroup.yuv420:
          final Uint8List nv21 = _yuv420ToNv21Direct(image);
          return ImageData(
            bytes: nv21,
            width: image.width,
            height: image.height,
            stride: image.width,
            format: EnumImagePixelFormat.nv21,
            orientation: defaultTargetPlatform == TargetPlatform.android
                ? 90
                : 0,
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

  bool _isBarcodeInCropArea(
    BarcodeResultItem barcode,
    Rect cropRect,
    int imageWidth,
    int imageHeight,
  ) {
    final Quadrilateral loc = barcode.location;
    if (loc.points.isEmpty) return true;

    double sumX = 0;
    double sumY = 0;
    for (final p in loc.points) {
      sumX += p.x;
      sumY += p.y;
    }
    final double centerX = sumX / loc.points.length;
    final double centerY = sumY / loc.points.length;

    final Offset center = Offset(centerX, centerY);
    final Offset rotatedCenter = Offset(centerY, imageWidth - centerX);

    return cropRect.contains(center) || cropRect.contains(rotatedCenter);
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
        resolution: ResolutionPreset.medium,
        scanDelay: const Duration(milliseconds: 250),
        frameIntervalMs: 250,
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
    _scannerController.pauseStream();
    setState(() => _showMultiResultScreen = true);
  }

  Gs1DetectedCode _detectedCodeFromDynamsoft(BarcodeResultItem item) {
    final int? format = Gs1DetectedFormat.fromName(item.formatString);
    final String rawText = _extractCodabarText(item);
    final String text = Gs1DataBarTextNormalizer.normalize(
      text: rawText,
      formatName: item.formatString,
      format: format,
    );
    debugPrint(
      'format=${item.formatString}, text="${item.text}", '
          'length=${item.text.length}, '
          'codes=${item.text.codeUnits}',
    );
    final Quadrilateral loc = item.location;
    Gs1DetectedPosition? pos;
    if (loc.points.length >= 4) {
      pos = Gs1DetectedPosition(
        imageWidth: 0,
        imageHeight: 0,
        topLeftX: loc.points[0].x,
        topLeftY: loc.points[0].y,
        topRightX: loc.points[1].x,
        topRightY: loc.points[1].y,
        bottomLeftX: loc.points[2].x,
        bottomLeftY: loc.points[2].y,
        bottomRightX: loc.points[3].x,
        bottomRightY: loc.points[3].y,
      );
    }
    return Gs1DetectedCode(
      text: text,
      format: format,
      isValid: true,
      position: pos,
    );
  }

  ScanEntry _entryForBarcode(BarcodeResultItem barcode) {
    final String formatName = barcode.formatString;
    final String normalizedText = Gs1DataBarTextNormalizer.normalize(
      text: barcode.text,
      formatName: formatName,
      format: Gs1DetectedFormat.fromName(formatName),
    );
    final bool looksLikeGs1 = _looksLikeGs1(formatName, normalizedText);

    String title = formatName.toUpperCase().replaceAll('_', '');

    // Non-GS1 barcodes: return exact raw text directly without GS1 AI mangling
    if (!looksLikeGs1) {
      final String rawText = _extractCodabarText(barcode);
      return ScanEntry(title, rawText);
    }

    // Replace Dynamsoft composite pipe separator '|' with GS separator
    final String cleanText = normalizedText.replaceAll('|', '\u001d');

    final List<Gs1Element> elements = Gs1ElementStringParser.parse(
      cleanText,
      fallbackFormat: Gs1DetectedFormat.fromName(formatName),
    );

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
      fallbackFormat: Gs1DetectedFormat.fromName(formatName),
      requireGs1Marker: false,
    );

    final String finalValue = elements.isNotEmpty
        ? Gs1ElementStringParser.formatElements(elements)
        : (gs1Text ?? normalizedText);

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
    if (formatName.contains('COMPOSITE') ||
        formatName.contains('GS1_COMPOSITE')) {
      return true;
    }
    if (text.contains('|')) return true;

    final String cleanText = text.replaceAll('|', '\u001d');
    final List<Gs1Element> elements = Gs1ElementStringParser.parse(
      cleanText,
      fallbackFormat: Gs1DetectedFormat.fromName(formatName),
    );
    return elements.length > 1;
  }

  bool _isLikelyPartialCompositeCarrier(BarcodeResultItem barcode) {
    final String formatName = barcode.formatString.toUpperCase();
    if (formatName.contains('COMPOSITE') ||
        formatName.contains('GS1_COMPOSITE')) {
      return false;
    }
    if (barcode.text.contains('|')) return false;

    if (!formatName.contains('CODE_128') && !formatName.contains('CODE128')) {
      return false;
    }

    final List<Gs1Element> elements = Gs1ElementStringParser.parse(
      barcode.text,
      fallbackFormat: Gs1DetectedFormat.fromName(formatName),
    );
    return elements.length == 1 && elements.single.ai == '01';
  }

  void _clearPendingLinearCarrier() {
    _pendingLinearCarrier = null;
    _pendingLinearCarrierAt = null;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Codabar / NW7 start/stop guard-character extraction
  // ──────────────────────────────────────────────────────────────────────────

  /// Extracts the full Codabar/NW7 text including start/stop guard characters.
  ///
  /// **Root Cause & Technical Finding**:
  /// In Dynamsoft Capture Vision v11 (native C++ DBR engine), `BarcodeResultItem.text`
  /// intentionally strips Codabar start/stop characters to return payload-only data.
  /// No JSON template parameter exists in DCV v11 to alter this text behavior.
  ///
  /// Instead, Dynamsoft provides start/stop guard bytes natively in
  /// [BarcodeResultItem.oneDCodeDetails.startCharsBytes] and [stopCharsBytes].
  ///
  /// This method reads those native bytes and attaches them to [item.text].
  String _extractCodabarText(BarcodeResultItem item) {
    final String formatUpper = item.formatString.toUpperCase();
    final bool isCodabar = formatUpper.contains('CODABAR') ||
        formatUpper.contains('NW_7') ||
        formatUpper.contains('NW7') ||
        formatUpper.contains('NW-7');

    if (!isCodabar) {
      return item.text;
    }

    final String payloadText = item.text;
    final OneDCodeDetails? details = item.oneDCodeDetails;

    String startChar = '';
    if (details?.startCharsBytes != null && details!.startCharsBytes!.isNotEmpty) {
      startChar = String.fromCharCodes(details.startCharsBytes!);
    }

    String stopChar = '';
    if (details?.stopCharsBytes != null && details!.stopCharsBytes!.isNotEmpty) {
      stopChar = String.fromCharCodes(details.stopCharsBytes!);
    }

    // Check if payload string somehow already contains guards
    const Set<String> guardSet = {'A', 'B', 'C', 'D', 'T', 'N', 'E', '*'};
    final bool hasStart = payloadText.isNotEmpty && guardSet.contains(payloadText[0].toUpperCase());
    final bool hasStop = payloadText.length > 1 && guardSet.contains(payloadText[payloadText.length - 1].toUpperCase());

    final String prefix = (hasStart || startChar.isEmpty) ? '' : startChar;
    final String suffix = (hasStop || stopChar.isEmpty) ? '' : stopChar;

    // Fallback: If native bytes were not supplied, prepend/append standard 'A' guard
    if (!hasStart && prefix.isEmpty && startChar.isEmpty) {
      final String fallbackPrefix = hasStart ? '' : 'A';
      final String fallbackSuffix = hasStop ? '' : 'A';
      final String result = '$fallbackPrefix$payloadText$fallbackSuffix';
      debugPrint(
        '[DynamsoftTab] Codabar text extracted (fallback guard): "$payloadText" → "$result"',
      );
      return result;
    }

    final String result = '$prefix$payloadText$suffix';
    debugPrint(
      '[DynamsoftTab] Codabar text extracted via oneDCodeDetails: start="$startChar", stop="$stopChar", payload="$payloadText" → "$result"',
    );
    return result;
  }

  bool _looksLikeGs1(String formatName, String text) {
    final String normalizedFormat = formatName.toUpperCase();
    if (normalizedFormat.contains('GS1') ||
        normalizedFormat.contains('COMPOSITE') ||
        normalizedFormat.contains('DATABAR') ||
        normalizedFormat.contains('RSS') ||
        normalizedFormat.contains('LIMITED') ||
        normalizedFormat.contains('EXPANDED')) {
      return true;
    }
    final String trimmed = text.trim();
    return trimmed.startsWith(RegExp(r'\][CcdQeE][1230]')) ||
        trimmed.startsWith(RegExp(r'^\(\d{2,4}\)')) ||
        RegExp(r'^01\d{14}').hasMatch(trimmed) ||
        trimmed.contains('\u001d') ||
        trimmed.contains('\u241d') ||
        RegExp(
          r'\{GS\}|<GS>|\\u001d|\\x1d',
          caseSensitive: false,
        ).hasMatch(trimmed);
  }

  String get _modeLabel {
    return _scanMode == ScanMode.single ? 'Single Code' : 'Multi Code';
  }
}
