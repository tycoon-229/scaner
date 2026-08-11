import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

/// A controller that allows the parent widget to interact with
/// [CameraScannerWidget] at runtime.
///
/// Pass an instance of this to [CameraScannerWidget.controller].
/// Dispose this controller when no longer needed – it will NOT automatically
/// dispose the camera; call [dispose] explicitly.
///
/// ### Example
/// ```dart
/// final controller = ScannerUIController();
///
/// @override
/// void dispose() {
///   controller.dispose();
///   super.dispose();
/// }
/// ```
class ScannerUIController extends ChangeNotifier {
  // ── Internal state ───────────────────────────────────────────────────────

  CameraController? _cameraController;
  bool _isStreaming = false;
  bool _isPaused = false;

  // ── Public getters ────────────────────────────────────────────────────────

  /// The underlying [CameraController] (null while camera is initializing).
  CameraController? get cameraController => _cameraController;

  /// Whether the image stream is currently active.
  bool get isStreaming => _isStreaming;

  /// Whether the stream has been manually paused (single-scan hold state).
  bool get isPaused => _isPaused;

  // ── Internal API used by CameraScannerWidget ─────────────────────────────

  /// Called by the widget when a new [CameraController] is ready.
  // ignore: use_setters_to_change_properties
  void attachCameraController(CameraController? controller) {
    _cameraController = controller;
    notifyListeners();
  }

  /// Handler attached by CameraScannerWidget for restarting camera and laser.
  Future<void> Function()? _onRestartCameraLaser;

  /// Called by [CameraScannerWidget] to register its internal restart callback.
  // ignore: use_setters_to_change_properties
  void attachRestartHandler(Future<void> Function()? handler) {
    _onRestartCameraLaser = handler;
  }

  /// Called by the widget whenever the streaming state changes.
  void updateStreamingState({required bool isStreaming, required bool isPaused}) {
    _isStreaming = isStreaming;
    _isPaused = isPaused;
    notifyListeners();
  }

  /// Restarts the camera stream, resets processing locks, and restarts the laser animation.
  ///
  /// Call this when switching tabs or returning to the scanner screen to ensure
  /// the camera stream and laser line animation are active and responsive.
  Future<void> restartCameraLaser() async {
    if (_onRestartCameraLaser != null) {
      await _onRestartCameraLaser!();
    } else if (_cameraController != null &&
        _cameraController!.value.isInitialized) {
      _isPaused = false;
      notifyListeners();
    }
  }

  // ── Public control API ────────────────────────────────────────────────────

  /// Pause the image stream (e.g., after a successful single scan).
  ///
  /// This is typically called from your [onFrameCaptured] callback once you
  /// have decoded a result and want to stop processing further frames.
  ///
  /// Call [resumeStream] to start again.
  Future<void> pauseStream() async {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        !_cameraController!.value.isStreamingImages) {
      return;
    }
    try {
      await _cameraController!.stopImageStream();
      _isPaused = true;
      _isStreaming = false;
      notifyListeners();
    } catch (e) {
      debugPrint('[ScannerUIController] pauseStream error: $e');
    }
  }

  /// Resume the image stream after a [pauseStream] call.
  Future<void> resumeStream(void Function(CameraImage) onImage) async {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _cameraController!.value.isStreamingImages) {
      return;
    }
    try {
      await _cameraController!.startImageStream(onImage);
      _isPaused = false;
      _isStreaming = true;
      notifyListeners();
    } catch (e) {
      debugPrint('[ScannerUIController] resumeStream error: $e');
    }
  }

  /// Toggle the torch (flashlight).
  Future<void> toggleTorch() async {
    final cam = _cameraController;
    if (cam == null || !cam.value.isInitialized) return;
    try {
      final mode =
          cam.value.flashMode == FlashMode.torch ? FlashMode.off : FlashMode.torch;
      await cam.setFlashMode(mode);
      notifyListeners();
    } catch (e) {
      debugPrint('[ScannerUIController] toggleTorch error: $e');
    }
  }

  /// Set the zoom level. [level] is clamped to the device's min/max.
  Future<void> setZoom(double level) async {
    final cam = _cameraController;
    if (cam == null || !cam.value.isInitialized) return;
    try {
      await cam.setZoomLevel(level);
    } catch (e) {
      debugPrint('[ScannerUIController] setZoom error: $e');
    }
  }

  @override
  void dispose() {
    _cameraController = null;
    super.dispose();
  }
}
