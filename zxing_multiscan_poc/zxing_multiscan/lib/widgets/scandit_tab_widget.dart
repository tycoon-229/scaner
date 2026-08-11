import 'package:flutter/material.dart';
import 'package:scandit_flutter_datacapture_barcode/scandit_flutter_datacapture_barcode.dart';
import 'package:scandit_flutter_datacapture_barcode/scandit_flutter_datacapture_barcode_capture.dart';
import 'package:scandit_flutter_datacapture_barcode/scandit_flutter_datacapture_barcode_count.dart';
import 'package:scandit_flutter_datacapture_core/scandit_flutter_datacapture_core.dart'
    hide Rect;

import 'scan_result_widget.dart';
import 'camera_scanner/scan_mode.dart';
import 'camera_scanner/scanner_overlay.dart';

const String _scanditLicenseKey =
    'AoI3UA49JoYaM/oyfMc9kQAOoFFnHmdgaxabYHoa6qzPMdhHEkLIYeBMa917bvLd1HFXOXJ7DbT0eCfZ0w8wLnIXUc2qfnFdmm/qEwsiqdx0BWSQbkOuuqgnChJHQJRyt0WVku9Y512+GRxYlUZSPg1rpMJ6Sr3VclCS5Y5oO5sofzfTzBX+bM5ueNKtVDxozxJZZFNFuLYrQ/i2qGmxGQJEKGEQT8mLX1ruaIoUOYKsS1UAMmvg0I9QVb6oZwEJBnBMZvRN//i7RiknzX0lHkJTyS4ZSH7nwHk/DIlpgSDgWwrhEEFOqFNNIEcoaDHsN3YcIDh3B12Mek1RZ1QBqkF57J6AUKFAZmZZRw5tm3dnQYYLsmf9uFFTF5opeuQ/DAzs4C9xs2NKcpiymGfa25cGWiKAa8PkD0PHfokRYHffe98MlEvBE3txnyxhRuDhR1aLK4wBW8g9Jit1234bDKJXDBNeJJ87YkCCvSlLJ74dCKY/aVQvAlx1FtH7ZxMMo25+dSEqnDfafgKMdjmNyVBQtbgTcfntWibUP8hUvbEGGUIx/GlYD1VPoMy1Jmq/aHWeV8ZgX7PpSczHEw8714lkWqt8Tt4QFlQpD3Yh4s1OE5rpBnIT+zhpr+VeeXgXO0NL1B0S6UbwE/T0Lm+tEnpzd6LafNtK4XQw2oU7/SSHHi8WCnMWradfF2BiU+4q+1Jw6vp0U/B1dpb3rV7bfZBjLdkIYvcdi1AP/QR7wNICCFKrUEWfUg0MDgIhVLdNvHY3JRRXZETmUDVb3zi15vlcsSEOFDl140WsLSw27R3mcEG8PT4iphVsNK90LhuAFA2IyOt4S/9ZZ5zxr2vg77Fpz3w5bFbDmmC5i6BW6o3cT+IlpXYfwu1DTawtR/ibiwhOKUBT+PpiJlfcWmAW9fp8zvHPZWijz0xZNI1xLVdff4jh+0TzYM0BmXdPSPW3MG92ssoAr5zqf2FV8DfTaMR4wzepAsmjlRJ7FbHYbneY1BCENZyerPYg4Cx/l2bpvkns3aorO6CQmPbfKO56/EJHk9C2YMfnI75FQJGNg8X+b9HANxdpMX50tpLZSeL+lLILIX8ZjJedfmILji/kXMpd8DeR2y96EOUnYIo1A2EP/A5oU09dSsntK16qDJqSF+2Z4WdwfzlkEZAAzlMCqZca0ZhNOZdIl3e1Rj5W6odhoyGfIHv3n53VBdNt2GA6oIqCFtw30dwS37hM0AeA9hjanoa/FH8+oa4zkelvJkBPCb1WxaOEUKO9adbIkQuliUoAeM+7J9zFDC51f7OoIzzfRGohXQ6FmgQ6aLecdUgz2iBIxDexaoy0uEOBwpuLIm0L+whZvwD5hPM4FrcTZnjgY7wcKgLc3BvJsmtgloHIp499yRsxebxzZP5rGUX6fXUEfYQxZfU8zrPhadQuGX5AYuAHv7hrXV3UWcWgCXpJsD0XunKPckcOsIay0Ie8h76+tY2K1nhxuV73KvfyJIvg/TBqC0xIUNlZBpsu8SgC9TH8dniTWCMk/0Y+xN32KhH7R2KTt4/tJh2zVlFuBZVj8DPcGDSg/CGOkm+Cx+79Oy6ssUQ8+D8jIR1+Kc5JrXfAvcCoCY248MAuD9GhoWcqVrTBKjxF08m0DOcAeeyg7fRj77Gk9+caBHxuv02MWGqcabGpeN2UtQ==';

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

  final List<MapEntry<String, String>> _scannedEntries =
      <MapEntry<String, String>>[];
  MapEntry<String, String>? _singleResult;

  ScanMode _scanMode = ScanMode.single;
  bool _showMultiResultScreen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
        _scanditLicenseKey,
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
      for (final Barcode b in recognized) {
        final String text = b.data ?? b.rawData;
        final String formatName = b.symbology
            .toString()
            .replaceAll('Symbology.', '')
            .toUpperCase();
        if (text.isNotEmpty) {
          final MapEntry<String, String> e = MapEntry<String, String>(
            formatName,
            text,
          );
          if (!_scannedEntries.any(
            (MapEntry<String, String> x) => x.value == text,
          )) {
            _scannedEntries.add(e);
            hasNew = true;
          }
        }
      }
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
      _scannedEntries.clear();
      _showMultiResultScreen = false;
    });
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
            'Lỗi khởi tạo Scandit: $_initError',
            style: const TextStyle(color: Colors.red),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // 1. Single Scan result screen
    if (_scanMode == ScanMode.single && _singleResult != null) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          child: ScanResultWidget(
            results: <MapEntry<String, String>>[_singleResult!],
            onScanAgain: _resumeScan,
          ),
        ),
      );
    }

    // 2. Multi Scan result screen
    if (_scanMode == ScanMode.multiscan && _showMultiResultScreen) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          child: ScanResultWidget(
            results: _scannedEntries,
            onScanAgain: _resumeScan,
          ),
        ),
      );
    }

    // 3. Live Camera View with Custom Overlay UI Stack
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: <Widget>[
          // ── Scandit Native Camera View ─────────────────────────────────────
          Positioned.fill(
            child: _scanMode == ScanMode.single
                ? (_dataCaptureView ?? const SizedBox())
                : (_barcodeCountView ?? const SizedBox()),
          ),

          // ── Custom Viewfinder & Scan Overlay (Single Code mode only) ─────
          if (_scanMode == ScanMode.single)
            Positioned.fill(
              child: Container(
                decoration: const ShapeDecoration(
                  shape: CameraScannerOverlayBorder(
                    cutOutSize: 250,
                    overlayColor: Colors.black45,
                  ),
                ),
              ),
            ),

          // ── Bottom-Left: Multi Scan result button (Symmetrical) ─────────────
          if (_scanMode == ScanMode.multiscan && _scannedEntries.isNotEmpty)
            Positioned(
              left: 20,
              bottom: 24,
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  label: Text(
                    'Success: (${_scannedEntries.length})',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed: () =>
                      setState(() => _showMultiResultScreen = true),
                ),
              ),
            ),

          // ── Bottom-Right: Mode Selector Dropdown (Symmetrical) ─────────────
          Positioned(
            right: 20,
            bottom: 24,
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: const Color.fromRGBO(0, 0, 0, 0.7),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white24, width: 1),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<ScanMode>(
                  value: _scanMode,
                  dropdownColor: const Color(0xFF1E1E1E),
                  icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  items: const <DropdownMenuItem<ScanMode>>[
                    DropdownMenuItem<ScanMode>(
                      value: ScanMode.single,
                      child: Text('Single Code'),
                    ),
                    DropdownMenuItem<ScanMode>(
                      value: ScanMode.multiscan,
                      child: Text('Multi Code'),
                    ),
                  ],
                  onChanged: (ScanMode? newMode) async {
                    if (newMode != null && newMode != _scanMode) {
                      setState(() {
                        _scanMode = newMode;
                        _singleResult = null;
                        _scannedEntries.clear();
                        _showMultiResultScreen = false;
                      });
                      await _updateModeInContext();
                    }
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
