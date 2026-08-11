import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:scandit_flutter_datacapture_barcode/scandit_flutter_datacapture_barcode.dart';
import 'package:scandit_flutter_datacapture_barcode/scandit_flutter_datacapture_barcode_count.dart';
import 'package:scandit_flutter_datacapture_core/scandit_flutter_datacapture_core.dart';

import '../extensions/scandit_mapper_extensions.dart';
import 'scan_result_widget.dart';

// NOTE: Replace 'YOUR_SCANDIT_LICENSE_KEY' with your valid Scandit License Key.
const String _scanditLicenseKey = 'AoI3UA49JoYaM/oyfMc9kQAOoFFnHmdgaxabYHoa6qzPMdhHEkLIYeBMa917bvLd1HFXOXJ7DbT0eCfZ0w8wLnIXUc2qfnFdmm/qEwsiqdx0BWSQbkOuuqgnChJHQJRyt0WVku9Y512+GRxYlUZSPg1rpMJ6Sr3VclCS5Y5oO5sofzfTzBX+bM5ueNKtVDxozxJZZFNFuLYrQ/i2qGmxGQJEKGEQT8mLX1ruaIoUOYKsS1UAMmvg0I9QVb6oZwEJBnBMZvRN//i7RiknzX0lHkJTyS4ZSH7nwHk/DIlpgSDgWwrhEEFOqFNNIEcoaDHsN3YcIDh3B12Mek1RZ1QBqkF57J6AUKFAZmZZRw5tm3dnQYYLsmf9uFFTF5opeuQ/DAzs4C9xs2NKcpiymGfa25cGWiKAa8PkD0PHfokRYHffe98MlEvBE3txnyxhRuDhR1aLK4wBW8g9Jit1234bDKJXDBNeJJ87YkCCvSlLJ74dCKY/aVQvAlx1FtH7ZxMMo25+dSEqnDfafgKMdjmNyVBQtbgTcfntWibUP8hUvbEGGUIx/GlYD1VPoMy1Jmq/aHWeV8ZgX7PpSczHEw8714lkWqt8Tt4QFlQpD3Yh4s1OE5rpBnIT+zhpr+VeeXgXO0NL1B0S6UbwE/T0Lm+tEnpzd6LafNtK4XQw2oU7/SSHHi8WCnMWradfF2BiU+4q+1Jw6vp0U/B1dpb3rV7bfZBjLdkIYvcdi1AP/QR7wNICCFKrUEWfUg0MDgIhVLdNvHY3JRRXZETmUDVb3zi15vlcsSEOFDl140WsLSw27R3mcEG8PT4iphVsNK90LhuAFA2IyOt4S/9ZZ5zxr2vg77Fpz3w5bFbDmmC5i6BW6o3cT+IlpXYfwu1DTawtR/ibiwhOKUBT+PpiJlfcWmAW9fp8zvHPZWijz0xZNI1xLVdff4jh+0TzYM0BmXdPSPW3MG92ssoAr5zqf2FV8DfTaMR4wzepAsmjlRJ7FbHYbneY1BCENZyerPYg4Cx/l2bpvkns3aorO6CQmPbfKO56/EJHk9C2YMfnI75FQJGNg8X+b9HANxdpMX50tpLZSeL+lLILIX8ZjJedfmILji/kXMpd8DeR2y96EOUnYIo1A2EP/A5oU09dSsntK16qDJqSF+2Z4WdwfzlkEZAAzlMCqZca0ZhNOZdIl3e1Rj5W6odhoyGfIHv3n53VBdNt2GA6oIqCFtw30dwS37hM0AeA9hjanoa/FH8+oa4zkelvJkBPCb1WxaOEUKO9adbIkQuliUoAeM+7J9zFDC51f7OoIzzfRGohXQ6FmgQ6aLecdUgz2iBIxDexaoy0uEOBwpuLIm0L+whZvwD5hPM4FrcTZnjgY7wcKgLc3BvJsmtgloHIp499yRsxebxzZP5rGUX6fXUEfYQxZfU8zrPhadQuGX5AYuAHv7hrXV3UWcWgCXpJsD0XunKPckcOsIay0Ie8h76+tY2K1nhxuV73KvfyJIvg/TBqC0xIUNlZBpsu8SgC9TH8dniTWCMk/0Y+xN32KhH7R2KTt4/tJh2zVlFuBZVj8DPcGDSg/CGOkm+Cx+79Oy6ssUQ8+D8jIR1+Kc5JrXfAvcCoCY248MAuD9GhoWcqVrTBKjxF08m0DOcAeeyg7fRj77Gk9+caBHxuv02MWGqcabGpeN2UtQ==';

class ScanditTabWidget extends StatefulWidget {
  const ScanditTabWidget({super.key});

  @override
  State<ScanditTabWidget> createState() => _ScanditTabWidgetState();
}

class _ScanditTabWidgetState extends State<ScanditTabWidget>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin
    implements BarcodeCountListener, BarcodeCountViewUiListener {
  DataCaptureContext? _context;
  BarcodeCount? _barcodeCount;
  BarcodeCountView? _barcodeCountView;
  Camera? _camera;
  TabController? _tabController;

  bool _isInitializing = true;
  String? _initError;

  List<Barcode> _scannedBarcodes = [];
  Codes? _scanditMultiResult;
  bool _showResultsScreen = false;
  final Stopwatch _stopwatch = Stopwatch();

  @override
  bool get wantKeepAlive => true;

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
    final isCurrentTab = _tabController!.index == 2; // Tab 3 is index 2
    if (isCurrentTab && !_showResultsScreen) {
      _camera?.switchToDesiredState(FrameSourceState.on);
    } else {
      _camera?.switchToDesiredState(FrameSourceState.off);
    }
  }

  Future<void> _initScandit() async {
    try {
      // 0. Ensure Scandit SDK native defaults are initialized
      await ScanditFlutterDataCaptureBarcode.initialize();

      // 1. Initialize DataCaptureContext
      final context = DataCaptureContext.forLicenseKey(_scanditLicenseKey);

      // 2. Set up Camera frame source with recommended settings
      final camera = Camera.defaultCamera;
      if (camera != null) {
        camera.applySettings(BarcodeCount.createRecommendedCameraSettings());
        await context.setFrameSource(camera);
      }
      _camera = camera;

      // 3. Configure BarcodeCountSettings (Optimized symbology set for maximum performance)
      final settings = BarcodeCountSettings();
      const activeSymbologies = [
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
      for (final symbology in activeSymbologies) {
        settings.enableSymbology(symbology, true);
      }

      // 4. Create BarcodeCount mode
      final barcodeCount = BarcodeCount(settings);
      barcodeCount.addListener(this);

      // 5. Create BarcodeCountView out-of-the-box UI
      final barcodeCountView = BarcodeCountView.forContextWithMode(
        context,
        barcodeCount,
      );
      barcodeCountView.uiListener = this;

      // 6. Turn Camera on only if Tab 3 is currently active
      final isTab3Active = _tabController?.index == 2;
      if (isTab3Active) {
        await _camera?.switchToDesiredState(FrameSourceState.on);
      } else {
        await _camera?.switchToDesiredState(FrameSourceState.off);
      }

      if (mounted) {
        setState(() {
          _context = context;
          _barcodeCount = barcodeCount;
          _barcodeCountView = barcodeCountView;
          _isInitializing = false;
        });
        _stopwatch.reset();
        _stopwatch.start();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _initError = e.toString();
          _isInitializing = false;
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final isTab3Active = _tabController?.index == 2;
    if (state == AppLifecycleState.resumed && isTab3Active && !_showResultsScreen) {
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
    _barcodeCount?.removeListener(this);
    _context?.removeAllModes();
    _stopwatch.stop();
    super.dispose();
  }

  // --- BarcodeCountListener Callbacks ---

  @override
  Future<void> didScan(
    BarcodeCount barcodeCount,
    BarcodeCountSession session,
    Future<FrameData> Function() getFrameData,
  ) async {
    final currentBarcodes = session.recognizedBarcodes;
    if (currentBarcodes.isNotEmpty && !_showResultsScreen) {
      final elapsedMs = _stopwatch.elapsedMilliseconds;
      final codes = currentBarcodes.toCodes(duration: elapsedMs);

      if (mounted) {
        setState(() {
          _scannedBarcodes = List.from(currentBarcodes);
          _scanditMultiResult = codes;
          _showResultsScreen = true;
        });
        _camera?.switchToDesiredState(FrameSourceState.off);
      }
    }
  }

  // --- BarcodeCountViewUiListener Callbacks ---

  @override
  void didTapListButton(BarcodeCountView view) {
    _showResults();
  }

  @override
  void didTapExitButton(BarcodeCountView view) {
    _resetScan();
  }

  @override
  void didTapSingleScanButton(BarcodeCountView view) {
    // Single scan button tap handler
  }

  void _showResults() {
    final elapsedMs = _stopwatch.elapsedMilliseconds;
    final codes = _scannedBarcodes.toCodes(duration: elapsedMs);

    setState(() {
      _scanditMultiResult = codes;
      _showResultsScreen = true;
    });
    _camera?.switchToDesiredState(FrameSourceState.off);
  }

  void _resetScan() {
    setState(() {
      _scannedBarcodes.clear();
      _scanditMultiResult = null;
      _showResultsScreen = false;
    });
    _barcodeCount?.reset();
    if (_tabController?.index == 2) {
      _camera?.switchToDesiredState(FrameSourceState.on);
    }
    _stopwatch.reset();
    _stopwatch.start();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Keep state alive in TabBarView

    if (_isInitializing) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_initError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Initialization Error: $_initError',
            style: const TextStyle(color: Colors.red),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_showResultsScreen &&
        _scanditMultiResult != null &&
        _scanditMultiResult!.codes.isNotEmpty) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          child: ScanResultWidget(
            results: _scanditMultiResult!.codes
                .where((c) => c.isValid && c.text != null)
                .map((c) => MapEntry<String, String>(
                      c.format?.name ?? '',
                      c.text!,
                    ))
                .toList(),
            onScanAgain: _resetScan,
          ),
        ),
      );
    }

    return Stack(
      children: [
        // Out-of-the-box MatrixScan Count UI View
        ?_barcodeCountView,

        // License key warning banner if default key is present
        if (_scanditLicenseKey == 'YOUR_SCANDIT_LICENSE_KEY')
          Positioned(
            top: 10,
            left: 16,
            right: 16,
            child: Material(
              color: Colors.amber.shade900.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(8),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.white),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Scandit MatrixScan Count Active.\nReplace YOUR_SCANDIT_LICENSE_KEY with your license key to scan.',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
