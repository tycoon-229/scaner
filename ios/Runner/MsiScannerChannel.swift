import Flutter
import Foundation

final class MsiScannerChannel {
  private static let channelName = "com.fpt.yuyama/msi_scanner"

  private let channel: FlutterMethodChannel
  private let decodeQueue = DispatchQueue(label: "com.fpt.yuyama.msi_scanner.decode")

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
    case "decodeMsiYuv":
      decodeYuv(call: call, result: result)
    case "decodeMsiBitmap":
      decodeBitmap(call: call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func decodeYuv(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any],
      let bytes = arguments["imageBytes"] as? FlutterStandardTypedData,
      let width = arguments["imageWidth"] as? Int,
      let height = arguments["imageHeight"] as? Int
    else {
      result(
        FlutterError(
          code: "INVALID_ARGUMENT",
          message: "YUV luminance data, width, and height are required",
          details: nil
        )
      )
      return
    }

    let rowStride = arguments["rowStride"] as? Int ?? width
    let checksumScheme = checksumScheme(from: arguments["checksumScheme"] as? String)

    guard width > 0, height > 0, rowStride > 0 else {
      result(
        FlutterError(
          code: "INVALID_ARGUMENT",
          message: "YUV width, height, and rowStride must be greater than zero",
          details: nil
        )
      )
      return
    }

    executeDecode(result: result, source: "yuv") {
      MsiNativeDecoder.decodeYuvLuminance(
        bytes,
        width: width,
        height: height,
        rowStride: rowStride,
        scheme: checksumScheme
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

    let checksumScheme = checksumScheme(from: arguments["checksumScheme"] as? String)

    executeDecode(result: result, source: "bitmap") {
      MsiNativeDecoder.decodeImageData(bytes, scheme: checksumScheme)
    }
  }

  private func executeDecode(
    result: @escaping FlutterResult,
    source: String,
    decode: @escaping () -> String?
  ) {
    decodeQueue.async {
      let startedAt = DispatchTime.now().uptimeNanoseconds
      let decodedText = decode()
      let durationMs = Int((DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000)

      DispatchQueue.main.async {
        result([
          "text": decodedText as Any,
          "durationMs": durationMs,
          "source": source,
        ])
      }
    }
  }

  private func checksumScheme(from value: String?) -> MsiChecksumScheme {
    guard let value = value else { return .auto }
    return MsiChecksumScheme(rawValue: value) ?? .auto
  }
}
