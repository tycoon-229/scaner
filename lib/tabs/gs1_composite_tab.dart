import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'package:poc_multi_scan/services/gs1_composite_coordinator.dart';
import 'package:poc_multi_scan/utils/scan_entries.dart';
import 'package:poc_multi_scan/widgets/scan_result_widget.dart';
import 'package:poc_multi_scan/widgets/camera_scanner/camera_scanner.dart';
import 'package:poc_multi_scan/widgets/scanner_camera_preview.dart';
import 'package:poc_multi_scan/widgets/scanner_live_scaffold.dart';
import 'package:poc_multi_scan/widgets/scanner_message.dart';

/// Standalone tab component for decoding GS1 Composite barcodes (1D Linear + 2D MicroPDF417/PDF417).
///
/// Features:
/// * Detects 1D primary code and 2D composite component via native MethodChannel.
/// * Verifies linkage flags and stitches payloads together.
/// * Single scan: Pauses stream and displays [ScanResultPage].
/// * Multi scan: Continuously decodes barcodes in real-time.
/// * Gallery scan: Decodes barcode images selected from device gallery.
class Gs1CompositeTab extends StatefulWidget {
  const Gs1CompositeTab({super.key});

  @override
  State<Gs1CompositeTab> createState() => _Gs1CompositeTabState();
}

class _Gs1CompositeTabState extends State<Gs1CompositeTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final ScannerUIController _scannerController = ScannerUIController();
  final Gs1CompositeCoordinator _coordinator = Gs1CompositeCoordinator();

  Gs1CompositeScanCandidate? result;
  final List<ScanEntry> _scannedEntries = <ScanEntry>[];

  ScanMode _scanMode = ScanMode.single;
  bool _showMultiResultScreen = false;

  @override
  void initState() {
    super.initState();
    _scannerController.addListener(_onControllerChanged);
  }

  Future<void> restartCameraLaser() async {
    await _scannerController.restartCameraLaser();
    if (mounted) {
      setState(() {
        result = null;
        _clearMultiResults();
      });
      _coordinator.reset();
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
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Frame Handler — Live stream decoding via Gs1CompositeCoordinator
  // ─────────────────────────────────────────────────────────────────────────

  Future<bool?> _handleFrame(CameraImage image, Rect? cropRect) async {
    try {
      final Gs1CompositeScanCandidate? candidate =
          await _coordinator.scanCameraImage(image);
      if (candidate == null) return false;

      if (_scanMode == ScanMode.multiscan) {
        final String key = candidate.symbology;
        final String value = candidate.text;

        if (addUniqueScanEntry(_scannedEntries, ScanEntry(key, value))) {
          if (mounted) setState(() {});
        }
        return false;
      } else {
        if (mounted) {
          setState(() {
            result = candidate;
          });
        }
        return true; // Return true to pause camera stream on single scan success
      }
    } catch (e) {
      debugPrint('GS1 Composite frame decode error: $e');
    }
    return false;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Gallery Handler — Static image decoding via Gs1CompositeCoordinator
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _handleGalleryImage(String path) async {
    try {
      final Gs1CompositeScanCandidate? candidate =
          await _coordinator.scanImageFile(path);
      if (candidate != null && mounted) {
        setState(() {
          result = candidate;
        });
      } else if (mounted) {
        showScannerMessage(context, 'No valid GS1 Composite barcode found in image');
      }
    } catch (e) {
      debugPrint('GS1 Composite gallery decode error: $e');
      if (mounted) {
        showScannerMessage(context, 'Failed to read image: $e');
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UI Builder
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // 1. Single Scan result screen
    if (_scanMode == ScanMode.single && result != null) {
      return ScanResultPage(
        results: <ScanEntry>[
          ScanEntry(result!.symbology, result!.text),
        ],
        onScanAgain: () {
          setState(() {
            result = null;
          });
          _coordinator.reset();
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
          _coordinator.reset();
          _resumeScan();
        },
      );
    }

    // 3. Live Scanner Screen
    return ScannerLiveScaffold(
      preview: ScannerCameraPreview(
        tabIndex: 3,
        controller: _scannerController,
        scanMode: _scanMode,
        scanDelay: const Duration(milliseconds: 50),
        frameIntervalMs: _scanMode == ScanMode.single ? 300 : 150,
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
    _coordinator.reset();
  }

  void _clearMultiResults() {
    _scannedEntries.clear();
    _showMultiResultScreen = false;
  }

  void _showMultiResults() {
    setState(() => _showMultiResultScreen = true);
  }
}
