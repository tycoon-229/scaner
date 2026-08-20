import 'package:flutter/material.dart' hide Feedback;
import 'package:scandit_flutter_datacapture_barcode/scandit_flutter_datacapture_barcode.dart';
import 'package:scandit_flutter_datacapture_barcode/scandit_flutter_datacapture_barcode_capture.dart';
import 'package:scandit_flutter_datacapture_core/scandit_flutter_datacapture_core.dart'
    hide Rect;

import 'package:poc_multi_scan/config/license_keys.dart';
import 'package:poc_multi_scan/utils/scan_entries.dart';
import 'package:poc_multi_scan/utils/scan_monitor.dart';
import 'package:poc_multi_scan/widgets/scan_result_widget.dart';
import 'package:poc_multi_scan/widgets/camera_scanner/scan_mode.dart';
import 'package:poc_multi_scan/widgets/camera_scanner/scanner_overlay.dart';
import 'package:poc_multi_scan/widgets/scanner_live_scaffold.dart';
import 'package:poc_multi_scan/widgets/scanner_message.dart';

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
  Symbology.gs1DatabarLimited,
  Symbology.gs1Databar,
  Symbology.gs1DatabarExpanded,
  Symbology.upce,
  Symbology.microPdf417,
];

// Helper listener class for Scandit BarcodeCapture callbacks
class _ScanditCaptureListener implements BarcodeCaptureListener {
  _ScanditCaptureListener(this.onScan);
  final void Function(BarcodeCapture capture, BarcodeCaptureSession session) onScan;

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

/// Scandit Tab integrating Scandit Native Camera Engine with 100% custom Flutter Scanner UI Overlay.
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
  DataCaptureView? _dataCaptureView;
  Camera? _camera;
  TabController? _tabController;

  _ScanditCaptureListener? _captureListener;

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

      // BarcodeCapture mode used for both Single scan and Continuous Multi scan
      final BarcodeCaptureSettings captureSettings = BarcodeCaptureSettings();
      final compositeTypes = {
        CompositeType.a,
        CompositeType.c,
        CompositeType.b,
      };
      for (final Symbology symbology in activeSymbologies) {
        captureSettings.enableSymbology(symbology, true);
      }
      captureSettings.enableSymbologiesForCompositeTypes(compositeTypes);
      captureSettings.enabledCompositeTypes = compositeTypes;

      // Set code duplicate filter to 800ms for smooth continuous multi-scanning
      captureSettings.codeDuplicateFilter = const Duration(milliseconds: 800);

      final BarcodeCapture barcodeCapture = BarcodeCapture(captureSettings);
      _captureListener = _ScanditCaptureListener(_onScanCaptured);
      barcodeCapture.addListener(_captureListener!);

      // Tắt chế độ rung và âm thanh khi quét thành công
      barcodeCapture.feedback.success = Feedback(null, null);

      _context = context;
      _barcodeCapture = barcodeCapture;

      await context.addMode(barcodeCapture);

      _dataCaptureView = DataCaptureView.forContext(context);

      // Create overlay with transparent brush so native Scandit highlights do not interfere with Flutter UI
      final overlay = BarcodeCaptureOverlay(barcodeCapture);
      overlay.brush = Brush.transparent;
      _dataCaptureView?.addOverlay(overlay);

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

  ScanEntry _extractBarcodeResult(Barcode b) {
    String text = b.data ?? b.rawData;
    if (b.compositeData != null && b.compositeData!.isNotEmpty) {
      text = '$text | Composite: ${b.compositeData}';
    }

    String formatName = b.symbology
        .toString()
        .replaceAll('Symbology.', '')
        .toUpperCase();

    if (b.compositeFlag != CompositeFlag.none) {
      switch (b.compositeFlag) {
        case CompositeFlag.gs1TypeA:
          formatName = '$formatName (COMPOSITE A)';
          break;
        case CompositeFlag.gs1TypeB:
          formatName = '$formatName (COMPOSITE B)';
          break;
        case CompositeFlag.gs1TypeC:
          formatName = '$formatName (COMPOSITE C)';
          break;
        case CompositeFlag.linked:
          formatName = '$formatName (COMPOSITE LINKED)';
          break;
        default:
          formatName = '$formatName (${b.compositeFlag.name.toUpperCase()})';
          break;
      }
    }

    return MapEntry<String, String>(formatName, text);
  }

  void _onScanCaptured(BarcodeCapture capture, BarcodeCaptureSession session) {
    if (!mounted) return;

    final Barcode? b = session.newlyRecognizedBarcode;
    if (b == null) return;

    final entry = _extractBarcodeResult(b);
    if (entry.value.isEmpty) return;

    if (_scanMode == ScanMode.single) {
      if (_singleResult == null) {
        _monitor.recordNativeEvent(
          uniqueCount: 1,
          duplicateCount: 0,
          modeLabel: _modeLabel,
        );
        setState(() {
          _singleResult = entry;
        });
        _camera?.switchToDesiredState(FrameSourceState.off);
      }
    } else {
      // Continuous Multi scan mode
      final bool hasNew = addUniqueScanEntry(_scannedEntries, entry);
      _monitor.recordNativeEvent(
        uniqueCount: hasNew ? 1 : 0,
        duplicateCount: hasNew ? 0 : 1,
        modeLabel: _modeLabel,
      );
      if (hasNew) {
        setState(() {});
      }
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

  Future<void> _handleGalleryImage(String path) async {
    showScannerMessage(
      context,
      'Gallery decoding operates via live camera engine. Use ZXing or Dynamsoft tab for image file scan.',
    );
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

    final double cutOutSize = MediaQuery.of(context).size.shortestSide * 0.5;

    return ScannerLiveScaffold(
      preview: _dataCaptureView ?? const SizedBox(),
      overlayChildren: <Widget>[
        if (_scanMode == ScanMode.single) ...<Widget>[
          Positioned.fill(
            child: Container(
              decoration: ShapeDecoration(
                shape: CameraScannerOverlayBorder(
                  cutOutSize: cutOutSize,
                  borderColor: Theme.of(context).primaryColor,
                  overlayColor: Colors.black45,
                  borderRadius: 4,
                  borderLength: 20,
                  borderWidth: 8,
                ),
              ),
            ),
          ),
          Center(
            child: SizedBox(
              width: cutOutSize,
              height: cutOutSize,
              child: ClipRect(
                child: ScannerScanLine(
                  lineColor: Theme.of(context).primaryColor,
                ),
              ),
            ),
          ),
        ],
      ],
      scanMode: _scanMode,
      resultCount: _scannedEntries.length,
      onShowResults: _showMultiResults,
      onModeChanged: _changeMode,
      onGalleryImageSelected: _handleGalleryImage,
    );
  }

  void _changeMode(ScanMode newMode) {
    setState(() {
      _scanMode = newMode;
      _singleResult = null;
      _clearMultiResults();
    });
    _monitor.startSession(modeLabel: _modeLabel);
    if (_camera != null && _tabController?.index == 2) {
      _camera!.switchToDesiredState(FrameSourceState.on);
    }
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
