import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:flutter_zxing_example/extensions/code_format_extensions.dart';

class MultiScanResultWidget extends StatelessWidget {
  const MultiScanResultWidget({
    super.key,
    this.result,
    this.multiResult,
    this.onScanAgain,
  });

  final Code? result;
  final Codes? multiResult;
  final Function()? onScanAgain;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Multi-Scan Results',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: multiResult?.codes.length ?? 0,
                  itemBuilder: (context, index) {
                    final code = multiResult!.codes[index];
                    if (code.isValid != true) return const SizedBox.shrink();

                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: ListTile(
                        leading: const Icon(Icons.qr_code),
                        title: Text(code.text ?? 'No text'),
                        subtitle: Text(code.formatName ?? 'Unknown format'),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan Again'),
                  onPressed: onScanAgain,
                ),
              ),
            ],
          )),
    );
  }
}
