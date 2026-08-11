import 'package:flutter/material.dart';
import 'package:scandit_flutter_datacapture_barcode/scandit_flutter_datacapture_barcode.dart';
import 'package:scandit_flutter_datacapture_barcode/scandit_flutter_datacapture_barcode_capture.dart';
import 'package:scandit_flutter_datacapture_barcode/scandit_flutter_datacapture_barcode_count.dart';
import 'package:scandit_flutter_datacapture_core/scandit_flutter_datacapture_core.dart'
    hide Rect;

import 'package:flutter_zxing_example/config/license_keys.dart';
import 'package:flutter_zxing_example/utils/scan_entries.dart';
import 'package:flutter_zxing_example/utils/scan_monitor.dart';
import 'package:flutter_zxing_example/widgets/scan_result_widget.dart';
import 'package:flutter_zxing_example/widgets/camera_scanner/scan_mode.dart';
import 'package:flutter_zxing_example/widgets/camera_scanner/scanner_overlay.dart';
import 'package:flutter_zxing_example/widgets/scanner_live_scaffold.dart';

const List<Symbology> activeSymbologies = <Symbology>[
  Symbology.ean13Upca,
  Symbology.ean8,
  Symbology.code128,
  Symbology.code39,
  Symbology.code93,
  Symbology.qr,
  Symbology.dataMatrix,
  Symbology.pdf417,
  Symbology.interleavedTwoOfFive,
  Symbology.codabar,
  Symbology.msiPlessey,
];

// Helper listener classes for Scandit SDK callbacks
class _ScanditCaptureListener implements BarcodeCaptureListener {
  _ScanditCaptureListener(this.onScan);
  final void Function(BarcodeCapture capture, BarcodeCaptureSession session)
  onScan;

  @override
  Future<void> didScan(
    BarcodeCapture barcodeCapture,
    BarcodeCaptureSession session,
    Future<FrameData> Function() getFrameData,
  ) async {
    onScan(barcodeCapture, session);
  }

  @override
  Future<void> didUpdateSession(
    BarcodeCapture barcodeCapture,
    BarcodeCaptureSession session,
    Future<FrameData> Function() getFrameData,
  ) async {}
}

class _ScanditCountListener implements BarcodeCountListener {
  _ScanditCountListener(this.onScan);
  final void Function(BarcodeCount count, BarcodeCountSession session) onScan;

  @override
  Future<void> didScan(
    BarcodeCount barcodeCount,
    BarcodeCountSession session,
    Future<FrameData> Function() getFrameData,
  ) async {
    onScan(barcodeCount, session);
  }
}

/// Scandit Tab integrating Scandit Native Camera & View with Custom Scanner Overlay UI.
class ScanditTab extends StatefulWidget {
  const ScanditTab({super.key});

  @override
  State<ScanditTab> createState() => _ScanditTabState();
}

class _ScanditTabState extends State<ScanditTab>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  @override
  bool get wantKeepAlive => true;

  DataCaptureContext? _context;
  BarcodeCapture? _barcodeCapture;
  BarcodeCount? _barcodeCount;
  BarcodeCountView? _barcodeCountView;
  DataCaptureView? _dataCaptureView;
  Camera? _camera;
  TabController? _tabController;

  _ScanditCaptureListener? _captureListener;
  _ScanditCountListener? _countListener;

  bool _isInitializing = true;
  String? _initError;

  final List<ScanEntry> _scannedEntries = <ScanEntry>[];
  final ScanMonitor _monitor = ScanMonitor(engineName: 'Scandit');
  ScanEntry? _singleResult;

  ScanMode _scanMode = ScanMode.single;
  bool _showMultiResultScreen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _monitor.startSession(modeLabel: _modeLabel);
    _initScandit();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newController = DefaultTabController.of(context);
    if (_tabController != newController) {
      _tabController?.removeListener(_onTabChanged);
      _tabController = newController;
      _tabController?.addListener(_onTabChanged);
    }
  }

  void _onTabChanged() {
    if (_tabController == null) return;
    final isCurrentTab = _tabController!.index == 2;
    if (isCurrentTab && _singleResult == null && !_showMultiResultScreen) {
      _camera?.switchToDesiredState(FrameSourceState.on);
    } else {
      _camera?.switchToDesiredState(FrameSourceState.off);
    }
  }

  Future<void> _initScandit() async {
    try {
      await ScanditFlutterDataCaptureBarcode.initialize();
      final DataCaptureContext context = await DataCaptureContext.initialize(
        LicenseKeys.scandit,
      );

      final Camera? camera = Camera.defaultCamera;
      if (camera != null) {
        final CameraSettings settings =
            BarcodeCapture.createRecommendedCameraSettings();
        settings.zoomFactor = 1.0;
        settings.zoomGestureZoomFactor = 1.0;
        settings.zoomLevels = <double>[1.0];
        settings.focusGestureStrategy = FocusGestureStrategy.manual;
        camera.applySettings(settings);
        await context.setFrameSource(camera);
      }
      _camera = camera;

      // 1. Single scan mode: BarcodeCapture
      final BarcodeCaptureSettings captureSettings = BarcodeCaptureSettings();
      for (final Symbology symbology in activeSymbologies) {
        captureSettings.enableSymbology(symbology, true);
      }
      final BarcodeCapture barcodeCapture = BarcodeCapture(captureSettings);
      _captureListener = _ScanditCaptureListener(_onSingleScan);
      barcodeCapture.addListener(_captureListener!);

      // 2. Multi scan mode: BarcodeCount
      final BarcodeCountSettings countSettings = BarcodeCountSettings();
      for (final Symbology symbology in activeSymbologies) {
        countSettings.enableSymbology(symbology, true);
      }
      final BarcodeCount barcodeCount = BarcodeCount(countSettings);
      _countListener = _ScanditCountListener(_onMultiScan);
      barcodeCount.addListener(_countListener!);

      _context = context;
      _barcodeCapture = barcodeCapture;
      _barcodeCount = barcodeCount;

      _dataCaptureView = DataCaptureView.forContext(context);
      _dataCaptureView?.addOverlay(BarcodeCaptureOverlay(barcodeCapture));

      _barcodeCountView =
          BarcodeCountView.forContextWithMode(context, barcodeCount)
            ..shouldShowUserGuidanceView = false
            ..shouldShowHints = false
            ..shouldShowToolbar = true
            ..shouldShowScanAreaGuides = false
            ..shouldShowListButton = false
            ..shouldShowExitButton = false
            ..shouldShowShutterButton = true
            ..shouldShowSingleScanButton = false
            ..shouldShowClearHighlightsButton = false;

      await _updateModeInContext();

      final isTab3Active = _tabController?.index == 2;
      if (isTab3Active) {
        await _camera?.switchToDesiredState(FrameSourceState.on);
      } else {
        await _camera?.switchToDesiredState(FrameSourceState.off);
      }

      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    } catch (e) {
      debugPrint('[ScanditTab] _initScandit error: $e');
      if (mounted) {
        setState(() {
          _initError = e.toString();
          _isInitializing = false;
        });
      }
    }
  }

  void _onSingleScan(BarcodeCapture capture, BarcodeCaptureSession session) {
    final Barcode? b = session.newlyRecognizedBarcode;
    if (b != null && mounted && _singleResult == null) {
      final String text = b.data ?? b.rawData;
      final String formatName = b.symbology
          .toString()
          .replaceAll('Symbology.', '')
          .toUpperCase();
      if (text.isNotEmpty) {
        _monitor.recordNativeEvent(
          uniqueCount: 1,
          duplicateCount: 0,
          modeLabel: _modeLabel,
        );
        setState(() {
          _singleResult = MapEntry<String, String>(formatName, text);
        });
        _camera?.switchToDesiredState(FrameSourceState.off);
      }
    }
  }

  void _onMultiScan(BarcodeCount count, BarcodeCountSession session) {
    final List<Barcode> recognized = session.recognizedBarcodes;
    if (recognized.isNotEmpty && mounted) {
      bool hasNew = false;
      int newCodeCount = 0;
      int duplicateCodeCount = 0;
      for (final Barcode b in recognized) {
        final String text = b.data ?? b.rawData;
        final String formatName = b.symbology
            .toString()
            .replaceAll('Symbology.', '')
            .toUpperCase();
        if (text.isNotEmpty) {
          final ScanEntry e = ScanEntry(formatName, text);
          if (addUniqueScanEntry(_scannedEntries, e)) {
            hasNew = true;
            newCodeCount++;
          } else {
            duplicateCodeCount++;
          }
        }
      }
      _monitor.recordNativeEvent(
        uniqueCount: newCodeCount,
        duplicateCount: duplicateCodeCount,
        modeLabel: _modeLabel,
      );
      if (hasNew) {
        setState(() {});
      }
    }
  }

  Future<void> _updateModeInContext() async {
    if (_context == null) return;
    await _context!.removeAllModes();
    if (_scanMode == ScanMode.single && _barcodeCapture != null) {
      _barcodeCapture!.isEnabled = true;
      await _context!.addMode(_barcodeCapture!);
    } else if (_scanMode == ScanMode.multiscan && _barcodeCount != null) {
      _barcodeCount!.isEnabled = true;
      await _context!.addMode(_barcodeCount!);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final isTab3Active = _tabController?.index == 2;
    if (state == AppLifecycleState.resumed &&
        isTab3Active &&
        _singleResult == null &&
        !_showMultiResultScreen) {
      _camera?.switchToDesiredState(FrameSourceState.on);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _camera?.switchToDesiredState(FrameSourceState.off);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController?.removeListener(_onTabChanged);
    _camera?.switchToDesiredState(FrameSourceState.off);
    if (_captureListener != null) {
      _barcodeCapture?.removeListener(_captureListener!);
    }
    if (_countListener != null) {
      _barcodeCount?.removeListener(_countListener!);
    }
    _context?.removeAllModes();
    super.dispose();
  }

  void _resumeScan() {
    setState(() {
      _singleResult = null;
      _clearMultiResults();
    });
    _monitor.startSession(modeLabel: _modeLabel);
    if (_camera != null && _context != null) {
      _context!.setFrameSource(_camera);
      _camera!.switchToDesiredState(FrameSourceState.on);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isInitializing) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_initError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Failed to initialize Scandit: $_initError',
            style: const TextStyle(color: Colors.red),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // 1. Single Scan result screen
    if (_scanMode == ScanMode.single && _singleResult != null) {
      return ScanResultPage(
        results: <ScanEntry>[_singleResult!],
        monitorSnapshot: _monitor.snapshot(resultCount: 1),
        onScanAgain: _resumeScan,
      );
    }

    // 2. Multi Scan result screen
    if (_scanMode == ScanMode.multiscan && _showMultiResultScreen) {
      return ScanResultPage(
        results: _scannedEntries,
        monitorSnapshot: _monitor.snapshot(resultCount: _scannedEntries.length),
        onScanAgain: _resumeScan,
      );
    }

    return ScannerLiveScaffold(
      preview: _scanMode == ScanMode.single
          ? (_dataCaptureView ?? const SizedBox())
          : (_barcodeCountView ?? const SizedBox()),
      overlayChildren: <Widget>[
        if (_scanMode == ScanMode.single)
          Positioned.fill(
            child: Container(
              decoration: ShapeDecoration(
                shape: CameraScannerOverlayBorder(
                  cutOutSize: 250,
                  borderColor: Theme.of(context).primaryColor,
                  overlayColor: Colors.black45,
                ),
              ),
            ),
          ),
      ],
      scanMode: _scanMode,
      resultCount: _scannedEntries.length,
      onShowResults: _showMultiResults,
      onModeChanged: _changeMode,
    );
  }

  void _changeMode(ScanMode newMode) {
    setState(() {
      _scanMode = newMode;
      _singleResult = null;
      _clearMultiResults();
    });
    _monitor.startSession(modeLabel: _modeLabel);
    _updateModeInContext();
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
