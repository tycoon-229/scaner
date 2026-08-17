import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'package:poc_multi_scan/widgets/camera_scanner/camera_scanner.dart';

class ScannerCameraPreview extends StatelessWidget {
  const ScannerCameraPreview({
    super.key,
    required this.tabIndex,
    required this.controller,
    required this.scanMode,
    required this.onFrameCaptured,
    required this.onGalleryImageSelected,
    required this.onControllerCreated,
    required this.scanDelay,
    required this.frameIntervalMs,
    required this.resolution,
    this.singleCropPercent = 0.75,
  });

  final int tabIndex;
  final ScannerUIController controller;
  final ScanMode scanMode;
  final FrameCapturedCallback onFrameCaptured;
  final GalleryImageCallback onGalleryImageSelected;
  final void Function(CameraController? cameraController, Exception? error)
  onControllerCreated;
  final Duration scanDelay;
  final int frameIntervalMs;
  final ResolutionPreset resolution;
  final double singleCropPercent;

  @override
  Widget build(BuildContext context) {
    return CameraScannerWidget(
      tabIndex: tabIndex,
      controller: controller,
      scanMode: scanMode,
      scanDelay: scanDelay,
      frameIntervalMs: frameIntervalMs,
      onFrameCaptured: onFrameCaptured,
      onGalleryImageSelected: onGalleryImageSelected,
      onControllerCreated: onControllerCreated,
      scanModeAlignment: Alignment.bottomRight,
      cropPercent: scanMode == ScanMode.single ? singleCropPercent : 0,
      overlayColor: Colors.black45,
      resolution: resolution,
    );
  }
}
