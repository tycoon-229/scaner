import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import '../extensions/code_format_extensions.dart';

class ScanResultWidget extends StatelessWidget {
  const ScanResultWidget({super.key, this.result, this.onScanAgain});

  final Code? result;
  final Function()? onScanAgain;

  @override
  Widget build(BuildContext context) {
    final durationMs = result?.duration ?? 0;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Orange-bordered TTFD Badge
            Container(
              margin: const EdgeInsets.only(bottom: 24.0),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.08),
                border: Border.all(color: Colors.orange, width: 1.5),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.timer_outlined, color: Colors.orange, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'TTFD: $durationMs ms',
                    style: const TextStyle(
                      color: Colors.orange,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              result?.formatName ?? '',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 20),
            SelectableText(
              result?.text ?? '',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 20),
            Text(
              'Inverted: ${result?.isInverted}\t\tMirrored: ${result?.isMirrored}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan Again'),
              onPressed: onScanAgain,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
