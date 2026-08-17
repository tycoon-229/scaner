import Flutter
import Foundation

final class NativeScannerRegistry {
  private let channels: [NativeScannerChannel]

  init(binaryMessenger: FlutterBinaryMessenger) {
    channels = [
      MsiScannerChannel(binaryMessenger: binaryMessenger),
      Gs1CompositeScannerChannel(binaryMessenger: binaryMessenger),
    ]
  }

  func dispose() {
    channels.reversed().forEach { $0.dispose() }
  }
}
