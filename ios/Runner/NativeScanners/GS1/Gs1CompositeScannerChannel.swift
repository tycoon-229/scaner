import Flutter
import Foundation

final class Gs1CompositeScannerChannel: NativeScannerChannel {
  private static let channelName = "com.fpt.yuyama/gs1_composite_scanner"

  private let channel: FlutterMethodChannel
  private let decodeQueue = DispatchQueue(label: "com.fpt.yuyama.gs1_composite_scanner.decode")

  init(binaryMessenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler(handle)
  }

  func dispose() {
    channel.setMethodCallHandler(nil)
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "decodeCompositeYuv":
      decodeCameraFrame(call: call, result: result)
    case "decodeCompositeBitmap":
      decodeBitmap(call: call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func decodeCameraFrame(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any],
      let bytes = arguments["imageBytes"] as? FlutterStandardTypedData,
      let width = arguments["imageWidth"] as? Int,
      let height = arguments["imageHeight"] as? Int
    else {
      result(
        FlutterError(
          code: "INVALID_ARGUMENT",
          message: "Camera bytes, width, and height are required",
          details: nil
        )
      )
      return
    }

    let rowStride = arguments["rowStride"] as? Int ?? width
    let imageFormatGroup = arguments["imageFormatGroup"] as? String

    guard width > 0, height > 0, rowStride > 0 else {
      result(
        FlutterError(
          code: "INVALID_ARGUMENT",
          message: "Camera width, height, and rowStride must be greater than zero",
          details: nil
        )
      )
      return
    }

    executeDecode(result: result) {
      Gs1CompositeNativeDecoder.decodeCameraBytes(
        bytes,
        width: width,
        height: height,
        rowStride: rowStride,
        imageFormatGroup: imageFormatGroup
      )
    }
  }

  private func decodeBitmap(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any],
      let bytes = arguments["imageBytes"] as? FlutterStandardTypedData,
      !bytes.data.isEmpty
    else {
      result(
        FlutterError(
          code: "INVALID_ARGUMENT",
          message: "Encoded image bytes are required",
          details: nil
        )
      )
      return
    }

    executeDecode(result: result) {
      Gs1CompositeNativeDecoder.decodeBitmapBytes(bytes)
    }
  }

  private func executeDecode(
    result: @escaping FlutterResult,
    decode: @escaping () -> [String: Any?]
  ) {
    decodeQueue.async {
      let decoded = decode()
      DispatchQueue.main.async {
        result(decoded)
      }
    }
  }
}
