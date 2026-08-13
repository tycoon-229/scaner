import 'package:flutter/material.dart';

import 'package:poc_multi_scan/widgets/camera_scanner/scan_mode.dart';

class MultiScanSuccessButton extends StatelessWidget {
  const MultiScanSuccessButton({
    super.key,
    required this.count,
    required this.onPressed,
  });

  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Theme.of(context).primaryColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        onPressed: onPressed,
        child: Text(
          'Success: ($count)',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

class ScanModeSelector extends StatelessWidget {
  const ScanModeSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final ScanMode value;
  final ValueChanged<ScanMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(0, 0, 0, 0.7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white24),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<ScanMode>(
          value: value,
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
          onChanged: (ScanMode? newMode) {
            if (newMode != null && newMode != value) {
              onChanged(newMode);
            }
          },
        ),
      ),
    );
  }
}

class ScanModeBottomControls extends StatelessWidget {
  const ScanModeBottomControls({
    super.key,
    required this.scanMode,
    required this.resultCount,
    required this.onShowResults,
    required this.onModeChanged,
    this.onPickImage,
  });

  final ScanMode scanMode;
  final int resultCount;
  final VoidCallback onShowResults;
  final ValueChanged<ScanMode> onModeChanged;
  final VoidCallback? onPickImage;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: SafeArea(
        child: Stack(
          children: <Widget>[
            if (scanMode == ScanMode.multiscan && resultCount > 0)
              Positioned(
                left: 20,
                bottom: 24,
                child: MultiScanSuccessButton(
                  count: resultCount,
                  onPressed: onShowResults,
                ),
              ),
            Positioned(
              right: 20,
              bottom: 24,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (onPickImage != null) ...<Widget>[
                    ImagePickerButton(onPressed: onPickImage!),
                    const SizedBox(width: 10),
                  ],
                  ScanModeSelector(value: scanMode, onChanged: onModeChanged),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ImagePickerButton extends StatelessWidget {
  const ImagePickerButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: const Color.fromRGBO(0, 0, 0, 0.7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white24),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: IconButton(
        tooltip: 'Pick image',
        color: Colors.white,
        icon: const Icon(Icons.photo_library_outlined),
        onPressed: onPressed,
      ),
    );
  }
}
