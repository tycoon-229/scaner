import 'package:dynamsoft_barcode_reader_bundle_flutter/dynamsoft_barcode_reader_bundle_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:flutter_zxing_example/services/msi_scanner_service.dart';
import 'widgets/debug_info_widget.dart';
import 'widgets/scan_result_widget.dart';
import 'widgets/multiscan_result_widget.dart';
import 'widgets/unsupported_platform_widget.dart';
import 'extensions/code_format_extensions.dart';
import 'extensions/dynamsoft_mapper_extensions.dart';

void main() {
  zx.setLogEnabled(kDebugMode);
  debugPrint('ZXing version: ${zx.version()}');
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Barcode Scanner Comparison',
      debugShowCheckedModeBanner: false,
      home: DemoPage(),
    );
  }
}

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  // ZXing State
  Uint8List? createdCodeBytes;
  Code? result;
  Codes? multiResult;
  bool isMultiScan = false;
  bool showMultiResult = false;
  bool showDebugInfo = true;
  int successScans = 0;
  int failedScans = 0;

  bool _isProcessingMsiFallback = false;
  DateTime _lastMsiFallbackAttempt = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastMsiCandidate;
  int _msiCandidateMatchCount = 0;

  // Dynamsoft State
  Code? dymResult;
  Codes? dymMultiResult;
  String? dymError;
  bool isDymMultiScan = false;
  bool showDymMultiResult = false;

  @override
  Widget build(BuildContext context) {
    final isCameraSupported =
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const TabBar(
            tabs: [
              Tab(text: 'ZXing'),
              Tab(text: 'Dynamsoft'),
            ],
          ),
        ),
        body: TabBarView(
          physics: const NeverScrollableScrollPhysics(),
          children: [
            // Tab 1: ZXing
            _buildZXingTab(isCameraSupported),
            // Tab 2: Dynamsoft
            _buildDynamsoftTab(isCameraSupported),
          ],
        ),
      ),
    );
  }

  Widget _buildZXingTab(bool isCameraSupported) {
    if (kIsWeb) {
      return const UnsupportedPlatformWidget();
    } else if (!isCameraSupported) {
      return const Center(child: Text('Camera not supported on this platform'));
    } else if (!isMultiScan && result != null && result?.isValid == true) {
      return ScanResultWidget(
        result: result,
        onScanAgain: () => setState(() => result = null),
      );
    } else if (isMultiScan &&
        showMultiResult &&
        multiResult != null &&
        multiResult!.codes.isNotEmpty) {
      return MultiScanResultWidget(
        multiResult: multiResult,
        onScanAgain: () => setState(() => showMultiResult = false),
      );
    } else {
      return Stack(
        children: [
          ReaderWidget(
            onScan: _onScanSuccess,
            onScanFailure: _onScanFailure,
            onMultiScan: _onMultiScanSuccess,
            onMultiScanFailure: _onMultiScanFailure,
            onMultiScanModeChanged: _onMultiScanModeChanged,
            onControllerCreated: _onControllerCreated,
            isMultiScan: isMultiScan,
            cropPercent: 0.5,
            verticalCropOffset: 0,
            horizontalCropOffset: 0,
            tryInverted: true,
            onActionSecondButton: () {
              setState(() {
                showDebugInfo = !showDebugInfo;
              });
            },
            actionSecondButtonIcon: const Icon(Icons.info_outline),
            tryDownscale: true,
            maxNumberOfSymbols: 5,
            scanDelay: Duration(milliseconds: isMultiScan ? 50 : 500),
            resolution: ResolutionPreset.high,
            lensDirection: CameraLensDirection.back,
            flashOnIcon: const Icon(Icons.flash_on),
            flashOffIcon: const Icon(Icons.flash_off),
            flashAlwaysIcon: const Icon(Icons.flash_on),
            flashAutoIcon: const Icon(Icons.flash_auto),
            galleryIcon: const Icon(Icons.photo_library),
            toggleCameraIcon: const Icon(Icons.switch_camera),
            actionButtonsBackgroundBorderRadius: BorderRadius.circular(10),
            actionButtonsBackgroundColor: Colors.black.withValues(alpha: 0.5),
          ),
          if (showDebugInfo)
            DebugInfoWidget(
              successScans: successScans,
              failedScans: failedScans,
              error: isMultiScan ? multiResult?.error : result?.error,
              duration: isMultiScan
                  ? multiResult?.duration ?? 0
                  : result?.duration ?? 0,
              onReset: _onReset,
              onViewResults: isMultiScan
                  ? () => setState(() => showMultiResult = true)
                  : null,
              imageBytes: !isMultiScan && result?.imageBytes != null
                  ? pngFromBytes(
                      result?.imageBytes ?? Uint8List(0),
                      result?.imageWidth ?? 0,
                      result?.imageHeight ?? 0,
                    )
                  : null,
            ),
        ],
      );
    }
  }

  Widget _buildDynamsoftTab(bool isCameraSupported) {
    if (kIsWeb) {
      return const UnsupportedPlatformWidget();
    } else if (!isCameraSupported) {
      return const Center(child: Text('Camera not supported on this platform'));
    } else if (!isDymMultiScan && dymResult != null && dymResult?.isValid == true) {
      return ScanResultWidget(
        result: dymResult,
        onScanAgain: () => setState(() => dymResult = null),
      );
    } else if (isDymMultiScan &&
        showDymMultiResult &&
        dymMultiResult != null &&
        dymMultiResult!.codes.isNotEmpty) {
      return MultiScanResultWidget(
        multiResult: dymMultiResult,
        onScanAgain: () => setState(() {
          dymMultiResult = null;
          showDymMultiResult = false;
        }),
      );
    } else {
      return Container(
        color: Colors.black,
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.qr_code_scanner,
                        size: 90,
                        color: Colors.white70,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Dynamsoft Barcode Reader',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isDymMultiScan
                            ? 'Mode: Multi-Barcode Scanning'
                            : 'Mode: Single Barcode Scanning',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.white70,
                            ),
                      ),
                      const SizedBox(height: 28),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment<bool>(
                            value: false,
                            label: Text('Single Scan'),
                            icon: Icon(Icons.qr_code),
                          ),
                          ButtonSegment<bool>(
                            value: true,
                            label: Text('Multi Scan'),
                            icon: Icon(Icons.qr_code_scanner),
                          ),
                        ],
                        selected: {isDymMultiScan},
                        onSelectionChanged: (Set<bool> newSelection) {
                          setState(() {
                            isDymMultiScan = newSelection.first;
                            dymResult = null;
                            dymMultiResult = null;
                            showDymMultiResult = false;
                          });
                        },
                        style: ButtonStyle(
                          backgroundColor: WidgetStateProperty.resolveWith(
                            (states) => states.contains(WidgetState.selected)
                                ? Colors.orange
                                : Colors.grey.shade900,
                          ),
                          foregroundColor: WidgetStateProperty.all(Colors.white),
                        ),
                      ),
                      const SizedBox(height: 28),
                      ElevatedButton.icon(
                        onPressed: () => _launchBarcodeScanner(
                          isDymMultiScan
                              ? EnumScanningMode.multiple
                              : EnumScanningMode.single,
                        ),
                        icon: const Icon(Icons.camera_alt),
                        label: Text(
                          isDymMultiScan
                              ? 'Start Multi Scan'
                              : 'Start Single Scan',
                          style: const TextStyle(fontSize: 16),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                      ),
                      if (dymMultiResult != null &&
                          dymMultiResult!.codes.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: () => setState(() {
                            isDymMultiScan = true;
                            showDymMultiResult = true;
                          }),
                          icon: const Icon(Icons.list_alt),
                          label: Text(
                            'View Multi Results (${dymMultiResult!.codes.length})',
                            style: const TextStyle(fontSize: 15),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.orange,
                            side: const BorderSide(color: Colors.orange),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
  }

  void _launchBarcodeScanner(EnumScanningMode scanningMode) async {
    final startTime = DateTime.now();
    var config = BarcodeScannerConfig(
      license: "t0089pwAAAFIxakesHjAxT8hGaKw6pkzm2k2X+jTkZyf/4h1k/akqyMYyEuPPcb4kepghNZNBYM5zoJg7Ey90q3dkwJwYZ442+Fan8gPGs1Pnxl9u9BZrJ2W7InQ=",
      scanningMode: scanningMode,
      isBeepEnabled: true,
      isVibrateEnabled: true,
      maxConsecutiveStableFramesToExit: 5,
    );

    BarcodeScanResult barcodeScanResult = await BarcodeScanner.launch(config);
    final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;

    setState(() {
      isDymMultiScan = scanningMode == EnumScanningMode.multiple;
      if (barcodeScanResult.status == EnumResultStatus.canceled) {
        // Canceled scan, do not record failure
      } else if (barcodeScanResult.status == EnumResultStatus.exception) {
        dymError =
            "ErrorCode: ${barcodeScanResult.errorCode}\nErrorString: ${barcodeScanResult.errorMessage}";
        if (scanningMode == EnumScanningMode.single) {
          dymResult = Code(
            isValid: false,
            duration: elapsedMs,
          );
        } else {
          dymMultiResult = Codes(
            codes: [],
            duration: elapsedMs,
          );
        }
      } else {
        // EnumResultStatus.finished
        dymError = null;
        if (scanningMode == EnumScanningMode.single) {
          final code = barcodeScanResult.toSingleCode(duration: elapsedMs);
          if (code != null && code.isValid) {
            dymResult = code;
          }
        } else {
          final codes = barcodeScanResult.toCodes(duration: elapsedMs);
          if (codes.codes.isNotEmpty) {
            dymMultiResult ??= Codes(codes: []);
            for (final c in codes.codes) {
              if (c.isValid &&
                  !dymMultiResult!.codes.any((exist) => exist.text == c.text)) {
                dymMultiResult!.codes.add(c);
              }
            }
            dymMultiResult!.duration = elapsedMs;
            showDymMultiResult = true;
          }
        }
      }
    });
  }

  void _onControllerCreated(CameraController? controller, Exception? error) {
    if (error != null) {
      _showMessage(context, 'Error: $error');
    }
  }

  void _onScanSuccess(Code? code) {
    setState(() {
      successScans++;
      result = code;
    });
  }

  void _onScanFailure(Code? code) async {
    setState(() {
      failedScans++;
    });

    _processMsiScanFallback(code);
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
            successScans++;
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

  void _onMultiScanSuccess(Codes codes) {
    setState(() {
      multiResult ??= Codes(codes: []);
      for (final code in codes.codes) {
        if (code.isValid &&
            !multiResult!.codes.any((c) => c.text == code.text)) {
          multiResult!.codes.add(code);
          successScans++;
        }
      }
      multiResult!.duration = codes.duration;
    });
  }

  void _onMultiScanFailure(Codes result) {
    setState(() {
      failedScans++;
    });
    if (result.codes.isNotEmpty == true) {
      _showMessage(context, 'Error: ${result.codes.first.error}');
    }
  }

  void _onMultiScanModeChanged(bool isMultiScan) {
    setState(() {
      this.isMultiScan = isMultiScan;
      result = null;
      multiResult = null;
      showMultiResult = false;
    });
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _onReset() {
    setState(() {
      successScans = 0;
      failedScans = 0;
      result = null;
      multiResult = null;
      showMultiResult = false;
    });
  }
}

