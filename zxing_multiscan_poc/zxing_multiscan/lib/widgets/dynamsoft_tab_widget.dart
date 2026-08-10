import 'package:dynamsoft_barcode_reader_bundle_flutter/dynamsoft_barcode_reader_bundle_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';

import '../extensions/dynamsoft_mapper_extensions.dart';
import 'multiscan_result_widget.dart';
import 'scan_result_widget.dart';
import 'unsupported_platform_widget.dart';

class DynamsoftTabWidget extends StatefulWidget {
  const DynamsoftTabWidget({super.key, required this.isCameraSupported});

  final bool isCameraSupported;

  @override
  State<DynamsoftTabWidget> createState() => _DynamsoftTabWidgetState();
}

class _DynamsoftTabWidgetState extends State<DynamsoftTabWidget> {
  Code? dymResult;
  Codes? dymMultiResult;
  String? dymError;
  bool isDymMultiScan = false;
  bool showDymMultiResult = false;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return const UnsupportedPlatformWidget();
    } else if (!widget.isCameraSupported) {
      return const Center(child: Text('Camera not supported on this platform'));
    } else if (!isDymMultiScan &&
        dymResult != null &&
        dymResult?.isValid == true) {
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
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
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
                          foregroundColor:
                              WidgetStateProperty.all(Colors.white),
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
      license:
          "t0089pwAAAFIxakesHjAxT8hGaKw6pkzm2k2X+jTkZyf/4h1k/akqyMYyEuPPcb4kepghNZNBYM5zoJg7Ey90q3dkwJwYZ442+Fan8gPGs1Pnxl9u9BZrJ2W7InQ=",
      scanningMode: scanningMode,
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
}
