/// Defines how the camera scanner handles captured frames.
///
/// - [single] : The scanner pauses the frame stream after the external
///   decoder signals a successful scan (via [ScannerUIController.pauseStream]).
///   Use this for scanning one item at a time.
///
/// - [multiscan] : The camera continuously streams frames. A throttle
///   mechanism ([frameIntervalMs] on [CameraScannerWidget]) prevents the
///   external decoder from being flooded.
enum ScanMode {
  /// Capture frames one-at-a-time; pause stream after a successful scan.
  single,

  /// Continuously stream frames with a configurable interval between callbacks.
  multiscan,
}
