import 'dart:async';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'scan_mode.dart';
import 'scanner_overlay.dart';
import 'scanner_ui_controller.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Frame-captured callback typedef
// ─────────────────────────────────────────────────────────────────────────────

/// Signature of the callback invoked for every captured camera frame.
///
/// Parameters:
/// * [image]    – The raw [CameraImage] straight from the platform camera.
///               Contains pixel plane data, width, height, and format group.
/// * [cropRect] – The crop rectangle (in image-pixel coordinates) that matches
///               the viewfinder cut-out, or `null` in [ScanMode.multiscan].
///               Use this to crop before passing to a decoder.
///
/// Return `true` to signal a **successful decode** in [ScanMode.single]:
/// the widget will then pause the stream automatically. Return `false`
/// (or `null`) to keep streaming.
typedef FrameCapturedCallback =
    Future<bool?> Function(CameraImage image, Rect? cropRect);

/// Signature for the gallery-image callback.
///
/// [path] is the absolute file-system path of the selected image.
typedef GalleryImageCallback = Future<void> Function(String path);

// ─────────────────────────────────────────────────────────────────────────────
// CameraScannerWidget
// ─────────────────────────────────────────────────────────────────────────────

/// A fully **decoupled** camera scanner UI widget.
///
/// Mirrors the look & feel of `ReaderWidget` from flutter_zxing but performs
/// **zero** barcode/QR decoding. Every frame is forwarded to [onFrameCaptured]
/// so you can plug in any decoder (ZXing, ML Kit, etc.).
///
/// ### Minimal usage
/// ```dart
/// CameraScannerWidget(
///   onFrameCaptured: (image, crop) async {
///     final result = await myDecoder.decode(image, crop);
///     return result != null; // true → pauses stream in ScanMode.single
///   },
/// )
/// ```
class CameraScannerWidget extends StatefulWidget {
  const CameraScannerWidget({
    super.key,
    this.tabIndex,
    // ── Core callbacks ─────────────────────────────────────────────────────
    this.onFrameCaptured,
    this.onControllerCreated,
    this.onGalleryImageSelected,
    // ── Scan behaviour ─────────────────────────────────────────────────────
    this.scanMode = ScanMode.single,
    this.scanDelay = const Duration(milliseconds: 50),
    this.frameIntervalMs = 500,
    // ── External controller ────────────────────────────────────────────────
    this.controller,
    // ── Scan-mode toggle ───────────────────────────────────────────────────
    this.onScanModeChanged,
    this.scanModeAlignment = Alignment.bottomRight,
    this.scanModePadding = const EdgeInsets.all(10),
    this.showScanModeToggle = false,
    // ── Overlay customisation ──────────────────────────────────────────────
    this.showScannerOverlay = true,
    this.scannerOverlay,
    this.showScanLine = true,
    this.scanLineColor,
    // overlayColor matches zxing default: Colors.black45
    this.overlayColor = Colors.black45,
    // borderColor defaults to Theme.primaryColor at build time
    this.borderColor,

    /// Size of the viewfinder as a fraction of the shorter screen side.
    /// Set to 0 to disable the cut-out (full-screen scan / multiscan style).
    this.cropPercent = 0.5,
    this.horizontalCropOffset = 0.0,
    this.verticalCropOffset = 0.0,
    // ── Controls visibility ────────────────────────────────────────────────
    this.showFlashlight = false,
    this.showToggleCamera = false,
    this.showGallery = false,
    // ── Control icons (match zxing defaults exactly) ───────────────────────
    this.flashOnIcon = const Icon(Icons.flash_on),
    this.flashOffIcon = const Icon(Icons.flash_off),
    this.flashAlwaysIcon = const Icon(Icons.flash_on),
    this.flashAutoIcon = const Icon(Icons.flash_auto),
    this.galleryIcon = const Icon(Icons.photo_library),
    this.toggleCameraIcon = const Icon(Icons.switch_camera),
    // ── Action button styling (match zxing defaults exactly) ───────────────
    this.actionButtonsAlignment = Alignment.bottomLeft,
    this.actionButtonsPadding = const EdgeInsets.all(10),
    // zxing uses Colors.black (fully opaque), not Colors.black54
    this.actionButtonsBackgroundColor = Colors.black,
    this.actionButtonsBackgroundBorderRadius,
    // ── Second action button (mirrors zxing's onActionSecondButton) ─────────
    this.onActionSecondButton,
    this.actionSecondButtonIcon,
    this.actionSecondButtonIconBackgroundColor,
    // ── Camera settings ────────────────────────────────────────────────────
    this.resolution = ResolutionPreset.high,
    this.lensDirection = CameraLensDirection.back,
    this.allowPinchZoom = true,
    // ── Loading placeholder ────────────────────────────────────────────────
    this.loading = const DecoratedBox(
      decoration: BoxDecoration(color: Colors.black),
    ),
    // ── Extra overlay widget ───────────────────────────────────────────────
    this.overlayWidget,
  });

  // ── Core callbacks ─────────────────────────────────────────────────────────

  /// Called for every captured frame.
  ///
  /// In [ScanMode.single]: return `true` to signal a successful decode and
  /// automatically pause the image stream. Return `false`/`null` to keep scanning.
  ///
  /// In [ScanMode.multiscan]: return value is ignored; the stream always
  /// continues.
  final FrameCapturedCallback? onFrameCaptured;

  /// Called once the [CameraController] has been initialised (or failed).
  ///
  /// * [cameraController] is non-null on success.
  /// * [error] is non-null on failure.
  final void Function(CameraController? cameraController, Exception? error)?
  onControllerCreated;

  /// Called when the user picks an image from the gallery.
  /// Receives the file path so you can pass it to your decoder.
  final GalleryImageCallback? onGalleryImageSelected;

  // ── Scan behaviour ──────────────────────────────────────────────────────────

  /// Whether to scan a single item or stream continuously.
  final ScanMode scanMode;

  /// Delay between frame processing attempts in single scan mode. Defaults to 50ms for maximum responsiveness.
  final Duration scanDelay;

  /// Minimum milliseconds between [onFrameCaptured] calls in
  /// [ScanMode.multiscan]. Has no effect in [ScanMode.single].
  final int frameIntervalMs;

  // ── External controller ─────────────────────────────────────────────────────

  /// Optional external controller for programmatic control
  /// (pause/resume stream, toggle torch, set zoom).
  ///
  /// The caller owns this controller and is responsible for disposing it.
  final ScannerUIController? controller;

  // ── Scan-mode toggle ────────────────────────────────────────────────────────

  /// When non-null, a scan-mode dropdown (Single / Multi) is shown.
  /// The callback receives the new [ScanMode] whenever it changes.
  final void Function(ScanMode)? onScanModeChanged;

  /// Alignment of the scan-mode dropdown overlay. Defaults to [Alignment.bottomRight].
  final AlignmentGeometry scanModeAlignment;

  /// Padding around the scan-mode dropdown overlay.
  final EdgeInsetsGeometry scanModePadding;

  /// When `true`, always show the scan-mode dropdown regardless of whether
  /// [onScanModeChanged] is set. Mirrors zxing's `onMultiScanModeChanged != null` toggle.
  final bool showScanModeToggle;

  // ── Overlay customisation ───────────────────────────────────────────────────

  /// Whether to show the scanner overlay (dark vignette + corner brackets).
  final bool showScannerOverlay;

  /// Supply a custom [ShapeBorder] to replace the built-in overlay.
  final ShapeBorder? scannerOverlay;

  /// Whether to show the animated scan line inside the cut-out.
  final bool showScanLine;

  /// Colour of the animated scan line. Defaults to [ThemeData.primaryColor].
  final Color? scanLineColor;

  /// Colour of the dark overlay surrounding the cut-out. Defaults to [Colors.black45].
  final Color overlayColor;

  /// Colour of the corner-bracket strokes. Defaults to [ThemeData.primaryColor].
  final Color? borderColor;

  /// Size of the viewfinder cut-out as a fraction of the shorter screen side
  /// (e.g. 0.5 = 50 %). Set to `0` to disable the cut-out (show full scan overlay).
  final double cropPercent;

  /// Shift the cut-out centre horizontally. Range: −1.0 … 1.0.
  final double horizontalCropOffset;

  /// Shift the cut-out centre vertically. Range: −1.0 … 1.0.
  final double verticalCropOffset;

  // ── Controls visibility ─────────────────────────────────────────────────────

  /// Show the torch toggle button.
  final bool showFlashlight;

  /// Show the switch-camera button.
  final bool showToggleCamera;

  /// Show the gallery picker button.
  final bool showGallery;

  // ── Control icons ───────────────────────────────────────────────────────────

  /// Icon shown when the torch is ON (FlashMode.torch).
  final Widget flashOnIcon;

  /// Icon shown when the torch is OFF.
  final Widget flashOffIcon;

  /// Icon shown when flash is set to always-on.
  final Widget flashAlwaysIcon;

  /// Icon shown when flash is set to auto.
  final Widget flashAutoIcon;

  /// Gallery icon.
  final Widget galleryIcon;

  /// Switch-camera icon.
  final Widget toggleCameraIcon;

  // ── Action button styling ───────────────────────────────────────────────────

  /// Alignment of the action button row. Defaults to [Alignment.bottomLeft].
  final AlignmentGeometry actionButtonsAlignment;

  /// Padding around the action button row. Defaults to [EdgeInsets.all(10)].
  final EdgeInsetsGeometry actionButtonsPadding;

  /// Background fill of the action button container. Defaults to [Colors.black].
  final Color actionButtonsBackgroundColor;

  /// Corner radius of the action button container. Defaults to [BorderRadius.circular(10)].
  final BorderRadius? actionButtonsBackgroundBorderRadius;

  // ── Second action button ────────────────────────────────────────────────────

  /// Optional callback for a second action button shown to the right of the
  /// main button group (mirrors zxing's `onActionSecondButton`).
  final VoidCallback? onActionSecondButton;

  /// Icon for the second action button.
  final Widget? actionSecondButtonIcon;

  /// Background colour of the second action button.
  final Color? actionSecondButtonIconBackgroundColor;

  // ── Camera settings ─────────────────────────────────────────────────────────

  /// Camera resolution preset.
  final ResolutionPreset resolution;

  /// Initial camera lens direction.
  final CameraLensDirection lensDirection;

  /// Whether pinch-to-zoom is enabled.
  final bool allowPinchZoom;

  // ── Loading placeholder ─────────────────────────────────────────────────────

  /// Optional tab index when placed inside a TabBarView / DefaultTabController.
  /// When provided, the camera will automatically stop/dispose when switching away
  /// and restart when switching to this tab.
  final int? tabIndex;

  /// Widget shown while the camera is initialising. Defaults to a black box.
  final Widget loading;

  // ── Extra overlay widget ────────────────────────────────────────────────────

  /// An arbitrary widget rendered on top of everything (e.g. result badges).
  final Widget? overlayWidget;

  @override
  State<CameraScannerWidget> createState() => _CameraScannerWidgetState();
}

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

class _CameraScannerWidgetState extends State<CameraScannerWidget>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // ── Camera ─────────────────────────────────────────────────────────────────
  List<CameraDescription> _cameras = <CameraDescription>[];
  CameraDescription? _selectedCamera;
  CameraController? _controller;
  TabController? _tabController;

  bool _isCameraOn = false;
  bool _isFlashAvailable = true;
  bool _isInitializing = false;

  /// Version tag — changed on every new [CameraController] creation.
  /// Stale frame callbacks are discarded when versions don't match.
  String _controllerVersion = '';

  // ── Stream throttling (multiscan) ──────────────────────────────────────────
  DateTime _lastFrameTime = DateTime.fromMillisecondsSinceEpoch(0);

  // ── Frame processing lock ──────────────────────────────────────────────────
  bool _isProcessing = false;

  // ── Scan mode ──────────────────────────────────────────────────────────────
  late ScanMode _activeScanMode;

  // ── Zoom ───────────────────────────────────────────────────────────────────
  double _zoom = 1.0;
  double _scaleFactor = 1.0;
  double _maxZoomLevel = 1.0;
  double _minZoomLevel = 1.0;

  // ── Completer guard (matches zxing pattern exactly) ────────────────────────
  Completer<void>? _initializationCompleter;

  // ── Laser key for restarting animation ────────────────────────────────────
  Key _laserKey = UniqueKey();

  // ── Helpers ────────────────────────────────────────────────────────────────

  bool isAndroid() => Theme.of(context).platform == TargetPlatform.android;

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _activeScanMode = widget.scanMode;
    WidgetsBinding.instance.addObserver(this);
    widget.controller?.attachRestartHandler(_restartCameraLaserInternal);
    _initStateAsync();
  }

  @override
  void didUpdateWidget(covariant CameraScannerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scanMode != widget.scanMode) {
      _activeScanMode = widget.scanMode;
      _isProcessing = false;
      _lastFrameTime = DateTime.fromMillisecondsSinceEpoch(0);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.controller?.updateStreamingState(
          isStreaming: _controller?.value.isStreamingImages ?? false,
          isPaused: false,
        );
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.tabIndex != null) {
      final TabController? newController = DefaultTabController.maybeOf(
        context,
      );
      if (_tabController != newController) {
        _tabController?.removeListener(_onTabChanged);
        _tabController = newController;
        _tabController?.addListener(_onTabChanged);
      }
    }
  }

  void _onTabChanged() {
    if (_tabController == null || widget.tabIndex == null) return;
    final bool isCurrentTab = _tabController!.index == widget.tabIndex;
    if (isCurrentTab) {
      if (!_isCameraOn && !_isInitializing) {
        _onNewCameraSelected(
          _selectedCamera ?? (_cameras.isNotEmpty ? _cameras.first : null),
        );
      }
    } else {
      if (_isCameraOn || _controller != null) {
        _disposeController().then((_) {
          if (mounted) setState(() {});
        });
      }
    }
  }

  Future<void> _initStateAsync() async {
    try {
      final List<CameraDescription> cameras = await availableCameras();
      if (!mounted) return;

      _cameras = cameras;
      if (cameras.isNotEmpty) {
        _selectedCamera = cameras.firstWhere(
          (CameraDescription c) => c.lensDirection == widget.lensDirection,
          orElse: () => cameras.first,
        );

        final TabController? tabController = DefaultTabController.maybeOf(
          context,
        );
        if (widget.tabIndex != null &&
            tabController != null &&
            tabController.index != widget.tabIndex) {
          return;
        }

        await _onNewCameraSelected(_selectedCamera);
      }
    } catch (e) {
      debugPrint('[CameraScannerWidget] _initStateAsync error: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _controller;
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    switch (state) {
      case AppLifecycleState.resumed:
        if (_cameras.isNotEmpty && !_isCameraOn) {
          _onNewCameraSelected(_selectedCamera ?? _cameras.first);
        }
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        _stopCamera();
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  void dispose() {
    _tabController?.removeListener(_onTabChanged);
    // Cancel any ongoing initialization
    if (_initializationCompleter != null &&
        !_initializationCompleter!.isCompleted) {
      _initializationCompleter!.complete();
    }
    _stopCamera();
    _disposeController();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Camera management  (mirrors zxing _ReaderWidgetState exactly)
  // ─────────────────────────────────────────────────────────────────────────

  /// Called by the [CameraController] listener when the controller state changes.
  /// Must call [setState] so the preview widget is actually rebuilt.
  /// Restarts the camera stream, unlocks frame processing, and restarts laser line animation.
  Future<void> _restartCameraLaserInternal() async {
    if (!mounted) return;

    _isProcessing = false;
    _laserKey = UniqueKey();

    final CameraController? cam = _controller;
    if (cam != null && cam.value.isInitialized) {
      if (!cam.value.isStreamingImages) {
        try {
          await cam.startImageStream(
            (CameraImage image) =>
                _processImageStream(image, _controllerVersion),
          );
        } catch (e) {
          debugPrint('[CameraScannerWidget] restartCameraLaser error: $e');
        }
      }
    }

    if (mounted) {
      setState(() {
        _isCameraOn = true;
      });
    }

    widget.controller?.updateStreamingState(
      isStreaming: cam?.value.isStreamingImages ?? false,
      isPaused: false,
    );
  }

  void _rebuildOnMount() {
    if (mounted) {
      setState(() {
        _isCameraOn = true;
      });
    }
  }

  Future<void> _disposeController() async {
    final CameraController? old = _controller;
    if (old == null) return;

    // Immediately nullify and invalidate version (zxing pattern)
    _controller = null;
    _isCameraOn = false;
    _isProcessing = false;
    _controllerVersion = 'disposed_${DateTime.now().millisecondsSinceEpoch}';

    old.removeListener(_rebuildOnMount);
    widget.controller?.attachCameraController(null);

    // Aggressively stop image stream (retry up to 5 times — matches zxing)
    if (old.value.isStreamingImages) {
      for (int i = 0; i < 5; i++) {
        try {
          await old.stopImageStream();
          break;
        } catch (_) {
          if (i < 2) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
        }
      }
    }

    try {
      await old.dispose();
    } catch (e) {
      debugPrint('[CameraScannerWidget] _disposeController error: $e');
    }
  }

  Future<void> _stopCamera() async {
    if (_controller?.value.isStreamingImages ?? false) {
      try {
        await _controller?.stopImageStream();
      } catch (e) {
        debugPrint('[CameraScannerWidget] stopImageStream error: $e');
      }
    }
    _isCameraOn = false;
    _isProcessing = false;
    widget.controller?.updateStreamingState(
      isStreaming: false,
      isPaused: false,
    );
  }

  Future<void> _onNewCameraSelected(
    CameraDescription? cameraDescription,
  ) async {
    if (cameraDescription == null) return;

    // Cancel any pending init
    if (_initializationCompleter != null &&
        !_initializationCompleter!.isCompleted) {
      _initializationCompleter!.complete();
    }

    if (_isInitializing) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (_isInitializing) return;
    }

    _isInitializing = true;
    _initializationCompleter = Completer<void>();

    await _disposeController();

    _isProcessing = false;
    _controllerVersion = DateTime.now().millisecondsSinceEpoch.toString();
    final String currentVersion = _controllerVersion;

    // Small delay to ensure full disposal (matches zxing)
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final CameraController cameraController = CameraController(
      cameraDescription,
      widget.resolution,
      enableAudio: false,
    );
    _controller = cameraController;

    try {
      await cameraController.initialize();
      if (!mounted) return;

      widget.onControllerCreated?.call(cameraController, null);
      widget.controller?.attachCameraController(cameraController);
      cameraController.addListener(_rebuildOnMount);

      // Start image stream
      if (cameraController.value.isInitialized &&
          !cameraController.value.isStreamingImages) {
        try {
          await cameraController.startImageStream(
            (CameraImage image) => _processImageStream(image, currentVersion),
          );
          // Verify stream is actually running (matches zxing)
          await Future<void>.delayed(const Duration(milliseconds: 200));
          if (!cameraController.value.isStreamingImages) {
            await cameraController.startImageStream(
              (CameraImage image) => _processImageStream(image, currentVersion),
            );
          }
        } catch (e) {
          debugPrint('[CameraScannerWidget] failed to start image stream: $e');
        }
      }

      // Zoom limits
      _maxZoomLevel = await cameraController.getMaxZoomLevel();
      _minZoomLevel = await cameraController.getMinZoomLevel();

      // Flash availability check
      try {
        await cameraController.setFlashMode(FlashMode.off);
        if (!_isFlashAvailable && mounted) {
          setState(() => _isFlashAvailable = true);
        }
      } on CameraException catch (e) {
        if (e.code == 'setFlashModeFailed' && mounted) {
          setState(() => _isFlashAvailable = false);
        }
      }

      if (mounted) setState(() => _isCameraOn = true);

      // Force-restart stream after init (matches zxing)
      if (cameraController.value.isStreamingImages) {
        try {
          await cameraController.stopImageStream();
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await cameraController.startImageStream(
            (CameraImage image) => _processImageStream(image, currentVersion),
          );
        } catch (e) {
          debugPrint('[CameraScannerWidget] stream restart failed: $e');
        }
      }

      widget.controller?.updateStreamingState(
        isStreaming: cameraController.value.isStreamingImages,
        isPaused: false,
      );
    } on CameraException catch (e) {
      if (e.code == 'setFlashModeFailed' && mounted) {
        setState(() => _isFlashAvailable = false);
      }
      widget.onControllerCreated?.call(null, e);
    } catch (e) {
      widget.onControllerCreated?.call(null, Exception(e.toString()));
    } finally {
      _isInitializing = false;
      if (_initializationCompleter != null &&
          !_initializationCompleter!.isCompleted) {
        _initializationCompleter!.complete();
      }
      _initializationCompleter = null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Frame processing
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _processImageStream(CameraImage image, String version) async {
    // Early exit if version doesn't match or widget is disposed (matches zxing pattern exactly)
    if (version != _controllerVersion ||
        !mounted ||
        _isInitializing ||
        _controller == null ||
        version.startsWith('disposed_') ||
        _initializationCompleter != null) {
      return;
    }

    if (!_isProcessing) {
      // Multiscan throttle
      if (_activeScanMode == ScanMode.multiscan) {
        final DateTime now = DateTime.now();
        if (now.difference(_lastFrameTime).inMilliseconds <
            widget.frameIntervalMs) {
          return;
        }
        _lastFrameTime = now;
      }

      _isProcessing = true;
      try {
        final Rect? cropRect = _buildCropRect(image);
        final bool? didSucceed = await widget.onFrameCaptured?.call(
          image,
          cropRect,
        );

        if (!mounted) return;

        // In single mode, auto-pause on success
        if (_activeScanMode == ScanMode.single && didSucceed == true) {
          await _pauseStream();
        }
      } catch (e) {
        debugPrint('[CameraScannerWidget] _processImageStream error: $e');
      } finally {
        // Check if still valid before delay (matches zxing pattern exactly)
        if (version == _controllerVersion && mounted) {
          await Future<void>.delayed(widget.scanDelay);
        }
        _isProcessing = false;
      }
    }
  }

  /// Computes the crop rectangle in camera-image pixel coordinates that
  /// corresponds to the viewfinder cut-out on screen.
  Rect? _buildCropRect(CameraImage image) {
    if (_activeScanMode == ScanMode.multiscan || widget.cropPercent == 0) {
      return null;
    }

    // On Android portrait the camera image is rotated 90°
    final bool swap =
        isAndroid() &&
        MediaQuery.of(context).orientation == Orientation.portrait;

    final double horizontalOffset = swap
        ? widget.verticalCropOffset
        : widget.horizontalCropOffset;
    final double verticalOffset = swap
        ? -widget.horizontalCropOffset
        : widget.verticalCropOffset;

    final int cropSize = (min(image.width, image.height) * widget.cropPercent)
        .round();

    final int cropLeft =
        ((image.width - cropSize) ~/ 2 +
                (horizontalOffset * (image.width - cropSize) / 2))
            .round()
            .clamp(0, image.width - cropSize);
    final int cropTop =
        ((image.height - cropSize) ~/ 2 +
                (verticalOffset * (image.height - cropSize) / 2))
            .round()
            .clamp(0, image.height - cropSize);

    return Rect.fromLTWH(
      cropLeft.toDouble(),
      cropTop.toDouble(),
      cropSize.toDouble(),
      cropSize.toDouble(),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Stream control helpers
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _pauseStream() async {
    if (_controller?.value.isStreamingImages ?? false) {
      try {
        await _controller!.stopImageStream();
        widget.controller?.updateStreamingState(
          isStreaming: false,
          isPaused: true,
        );
      } catch (e) {
        debugPrint('[CameraScannerWidget] _pauseStream error: $e');
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Button handlers
  // ─────────────────────────────────────────────────────────────────────────

  void _onFlashButtonTapped() {
    FlashMode mode = _controller?.value.flashMode ?? FlashMode.off;
    if (mode == FlashMode.torch) {
      mode = FlashMode.off;
    } else {
      mode = FlashMode.torch;
    }
    _controller?.setFlashMode(mode);
    if (mounted) setState(() {});
  }

  Future<void> _onGalleryButtonTapped() async {
    final XFile? file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
    );
    if (file != null) {
      await widget.onGalleryImageSelected?.call(file.path);
    }
  }

  void _onCameraButtonTapped() {
    if (_cameras.isEmpty || _controller == null) return;
    final int cameraIndex = _cameras.indexOf(_controller!.description);
    final int nextCameraIndex = (cameraIndex + 1) % _cameras.length;
    _selectedCamera = _cameras[nextCameraIndex];
    _onNewCameraSelected(_selectedCamera);
  }

  Widget _flashIcon(FlashMode mode) {
    switch (mode) {
      case FlashMode.torch:
        return widget.flashOnIcon;
      case FlashMode.off:
        return widget.flashOffIcon;
      case FlashMode.always:
        return widget.flashAlwaysIcon;
      case FlashMode.auto:
        return widget.flashAutoIcon;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build  — layout mirrors ReaderWidget exactly
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bool isCameraReady =
        _cameras.isNotEmpty &&
        _isCameraOn &&
        _controller != null &&
        _controller!.value.isInitialized;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size size = Size(constraints.maxWidth, constraints.maxHeight);
        final double cameraMaxSize = max(size.width, size.height);
        final double cropSize =
            min(size.width, size.height) * widget.cropPercent;
        final Color effectiveBorderColor =
            widget.borderColor ?? Theme.of(context).primaryColor;
        final Color effectiveScanLineColor =
            widget.scanLineColor ?? Theme.of(context).primaryColor;

        return Stack(
          children: <Widget>[
            // ── 1. Camera preview (switch expression — matches zxing exactly) ──
            switch (true) {
              _ when !isCameraReady => widget.loading,
              _ when _controllerVersion.startsWith('disposed_') =>
                const DecoratedBox(
                  decoration: BoxDecoration(color: Colors.black),
                ),
              _ => SizedBox(
                width: cameraMaxSize,
                height: cameraMaxSize,
                child: ClipRRect(
                  child: OverflowBox(
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: cameraMaxSize,
                        child: CameraPreview(_controller!),
                      ),
                    ),
                  ),
                ),
              ),
            },

            // ── 2. Scanner overlay ─────────────────────────────────────────────
            // Mirrors zxing exactly: shown when cropPercent != 0 && !multiscan.
            // NOTE: rendered UNCONDITIONALLY (not gated on isCameraReady) so the
            // dark vignette + corner brackets appear immediately, even over the
            // loading placeholder — exactly as ReaderWidget does.
            if (widget.showScannerOverlay &&
                widget.cropPercent != 0 &&
                _activeScanMode != ScanMode.multiscan)
              Container(
                decoration: ShapeDecoration(
                  shape:
                      widget.scannerOverlay ??
                      CameraScannerOverlayBorder(
                        cutOutSize: cropSize,
                        horizontalOffset: widget.horizontalCropOffset,
                        verticalOffset: widget.verticalCropOffset,
                        borderColor: effectiveBorderColor,
                        overlayColor: widget.overlayColor,
                        // Match zxing defaults exactly
                        borderRadius: 4,
                        borderLength: 20,
                        borderWidth: 8,
                      ),
                ),
              ),

            // ── 3. Animated scan line (bonus over zxing — positioned inside cut-out)
            if (widget.showScanLine &&
                widget.showScannerOverlay &&
                widget.cropPercent != 0 &&
                _activeScanMode != ScanMode.multiscan &&
                isCameraReady)
              _ScanLinePositioned(
                key: _laserKey,
                screenSize: size,
                cropSize: cropSize,
                horizontalOffset: widget.horizontalCropOffset,
                verticalOffset: widget.verticalCropOffset,
                scanLineColor: effectiveScanLineColor,
              ),

            // ── 4. Pinch-to-zoom gesture detector ─────────────────────────────
            if (widget.allowPinchZoom)
              GestureDetector(
                onScaleStart: (ScaleStartDetails details) {
                  _zoom = _scaleFactor;
                },
                onScaleUpdate: (ScaleUpdateDetails details) {
                  if (!_isCameraOn) return;
                  _scaleFactor = (_zoom * details.scale).clamp(
                    _minZoomLevel,
                    _maxZoomLevel,
                  );
                  _controller?.setZoomLevel(_scaleFactor);
                },
              ),

            // ── 5. Action buttons — mirrors ReaderWidget layout exactly ─────────
            //   • SafeArea > Align > Padding > ClipRRect (outer, for entire row)
            //   • Inner Row: [primary group ClipRRect] [spacer] [optional 2nd btn]
            SafeArea(
              child: Align(
                alignment: widget.actionButtonsAlignment,
                child: Padding(
                  padding: widget.actionButtonsPadding,
                  child: ClipRRect(
                    borderRadius:
                        widget.actionButtonsBackgroundBorderRadius ??
                        BorderRadius.circular(10.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        // ── Primary button group ──────────────────────────────
                        ClipRRect(
                          borderRadius:
                              widget.actionButtonsBackgroundBorderRadius ??
                              BorderRadius.circular(10.0),
                          child: ColoredBox(
                            color: widget.actionButtonsBackgroundColor,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                if (widget.showFlashlight && _isFlashAvailable)
                                  IconButton(
                                    onPressed: _onFlashButtonTapped,
                                    color: Colors.white,
                                    icon: _flashIcon(
                                      _controller?.value.flashMode ??
                                          FlashMode.off,
                                    ),
                                  ),
                                if (widget.showGallery)
                                  IconButton(
                                    onPressed: _onGalleryButtonTapped,
                                    color: Colors.white,
                                    icon: widget.galleryIcon,
                                  ),
                                if (widget.showToggleCamera)
                                  IconButton(
                                    onPressed: _onCameraButtonTapped,
                                    color: Colors.white,
                                    icon: widget.toggleCameraIcon,
                                  ),
                              ],
                            ),
                          ),
                        ),

                        // ── Optional secondary button (mirrors zxing) ─────────
                        if (widget.onActionSecondButton != null &&
                            widget.actionSecondButtonIcon != null) ...<Widget>[
                          Container(
                            // Push above dropdown if it sits at bottom-right
                            margin: EdgeInsets.only(
                              bottom:
                                  (widget.onScanModeChanged != null ||
                                          widget.showScanModeToggle) &&
                                      widget.scanModeAlignment ==
                                          Alignment.bottomRight
                                  ? 55.0
                                  : 0,
                            ),
                            child: IconButton.filled(
                              padding: widget.actionButtonsPadding,
                              onPressed: widget.onActionSecondButton,
                              icon: widget.actionSecondButtonIcon!,
                              style: IconButton.styleFrom(
                                backgroundColor:
                                    widget
                                        .actionSecondButtonIconBackgroundColor ??
                                    widget.actionButtonsBackgroundColor,
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      widget
                                          .actionButtonsBackgroundBorderRadius ??
                                      BorderRadius.zero,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── 6. Scan-mode dropdown ──────────────────────────────────────────
            // Shown when [onScanModeChanged] != null  OR  [showScanModeToggle] is true.
            // Default alignment is Alignment.bottomRight — matches zxing multiScanModeAlignment.
            if (widget.onScanModeChanged != null || widget.showScanModeToggle)
              SafeArea(
                child: _ScanModeDropdown(
                  scanMode: _activeScanMode,
                  alignment: widget.scanModeAlignment,
                  padding: widget.scanModePadding,
                  onChanged: (ScanMode mode) {
                    if (mounted) setState(() => _activeScanMode = mode);
                    widget.onScanModeChanged?.call(mode);
                  },
                ),
              ),

            // ── 7. Custom overlay widget ───────────────────────────────────────
            if (widget.overlayWidget != null) widget.overlayWidget!,
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Positions the [ScannerScanLine] precisely inside the viewfinder cut-out.
class _ScanLinePositioned extends StatelessWidget {
  const _ScanLinePositioned({
    super.key,
    required this.screenSize,
    required this.cropSize,
    required this.horizontalOffset,
    required this.verticalOffset,
    required this.scanLineColor,
  });

  final Size screenSize;
  final double cropSize;
  final double horizontalOffset;
  final double verticalOffset;
  final Color scanLineColor;

  @override
  Widget build(BuildContext context) {
    final double left =
        (screenSize.width - cropSize) / 2 +
        horizontalOffset * (screenSize.width - cropSize) / 2;
    final double top =
        (screenSize.height - cropSize) / 2 +
        verticalOffset * (screenSize.height - cropSize) / 2;

    return Positioned(
      left: left,
      top: top,
      width: cropSize,
      height: cropSize,
      child: ClipRect(child: ScannerScanLine(lineColor: scanLineColor)),
    );
  }
}

/// Scan-mode dropdown — mirrors zxing's [ScanModeDropdown] widget.
class _ScanModeDropdown extends StatelessWidget {
  const _ScanModeDropdown({
    required this.scanMode,
    required this.onChanged,
    this.alignment = Alignment.bottomRight,
    this.padding = const EdgeInsets.all(10),
  });

  final ScanMode scanMode;
  final ValueChanged<ScanMode> onChanged;
  final AlignmentGeometry alignment;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Padding(
        padding: padding,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(10),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<ScanMode>(
              value: scanMode,
              dropdownColor: Colors.black87,
              items: const <DropdownMenuItem<ScanMode>>[
                DropdownMenuItem<ScanMode>(
                  value: ScanMode.single,
                  child: Text(
                    'Single Code',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                DropdownMenuItem<ScanMode>(
                  value: ScanMode.multiscan,
                  child: Text(
                    'Multi Code',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
              onChanged: (ScanMode? v) => onChanged(v ?? ScanMode.single),
            ),
          ),
        ),
      ),
    );
  }
}
