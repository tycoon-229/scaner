import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:flutter_zxing_example/widgets/camera_scanner/scan_mode.dart';
import 'package:flutter_zxing_example/widgets/scan_mode_controls.dart';

class ScannerLiveScaffold extends StatelessWidget {
  const ScannerLiveScaffold({
    super.key,
    required this.preview,
    required this.scanMode,
    required this.resultCount,
    required this.onShowResults,
    required this.onModeChanged,
    this.overlayChildren = const <Widget>[],
    this.showResumeButton = false,
    this.onResumeScan,
    this.onGalleryImageSelected,
  });

  final Widget preview;
  final ScanMode scanMode;
  final int resultCount;
  final VoidCallback onShowResults;
  final ValueChanged<ScanMode> onModeChanged;
  final List<Widget> overlayChildren;
  final bool showResumeButton;
  final VoidCallback? onResumeScan;
  final Future<void> Function(String path)? onGalleryImageSelected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: <Widget>[
          Positioned.fill(child: preview),
          ...overlayChildren,
          if (showResumeButton && onResumeScan != null)
            ScannerResumeButton(onPressed: onResumeScan!),
          ScanModeBottomControls(
            scanMode: scanMode,
            resultCount: resultCount,
            onShowResults: onShowResults,
            onModeChanged: onModeChanged,
            onPickImage: onGalleryImageSelected == null
                ? null
                : () => _pickImage(context),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage(BuildContext context) async {
    final XFile? image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
    );
    if (image == null) return;
    await onGalleryImageSelected?.call(image.path);
  }
}

class ScannerResumeButton extends StatelessWidget {
  const ScannerResumeButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 80,
      child: Center(
        child: FloatingActionButton.extended(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          icon: const Icon(Icons.refresh),
          label: const Text(
            'Tap to scan again',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          onPressed: onPressed,
        ),
      ),
    );
  }
}
