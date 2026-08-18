package com.fpt.yuyama.scanner.mlkit

import com.fpt.yuyama.scanner.platform.MethodChannelDecodeExecutor
import com.fpt.yuyama.scanner.platform.ScannerChannel
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MlKitBarcodeScannerChannel private constructor(
    flutterEngine: FlutterEngine
) : MethodChannel.MethodCallHandler, ScannerChannel {

    companion object {
        private const val CHANNEL = "com.fpt.yuyama/mlkit_barcode_scanner"

        fun registerWith(flutterEngine: FlutterEngine): MlKitBarcodeScannerChannel {
            return MlKitBarcodeScannerChannel(flutterEngine)
        }
    }

    private val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
    private val decoder = MlKitBarcodeNativeDecoder()
    private val decodeExecutor = MethodChannelDecodeExecutor(
        errorCode = "MLKIT_BARCODE_DECODE_FAILED",
        fallbackErrorMessage = "ML Kit barcode decode failed"
    )

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "decodeYuv420" -> decodeYuv420(call, result)
            else -> result.notImplemented()
        }
    }

    override fun dispose() {
        channel.setMethodCallHandler(null)
        decoder.close()
        decodeExecutor.shutdown()
    }

    private fun decodeYuv420(call: MethodCall, result: MethodChannel.Result) {
        val yBytes = call.argument<ByteArray>("yBytes")
        val uBytes = call.argument<ByteArray>("uBytes")
        val vBytes = call.argument<ByteArray>("vBytes")
        val width = call.argument<Int>("imageWidth") ?: 0
        val height = call.argument<Int>("imageHeight") ?: 0

        if (yBytes == null || uBytes == null || vBytes == null || width <= 0 || height <= 0) {
            result.error(
                "INVALID_ARGUMENT",
                "YUV420 planes, width, and height are required",
                null
            )
            return
        }

        val yRowStride = call.argument<Int>("yRowStride") ?: width
        val yPixelStride = call.argument<Int>("yPixelStride") ?: 1
        val uRowStride = call.argument<Int>("uRowStride") ?: (width / 2)
        val uPixelStride = call.argument<Int>("uPixelStride") ?: 1
        val vRowStride = call.argument<Int>("vRowStride") ?: (width / 2)
        val vPixelStride = call.argument<Int>("vPixelStride") ?: 1
        val rotationDegrees = call.argument<Int>("rotationDegrees") ?: 0

        decodeExecutor.execute(result) {
            decoder.decodeYuv420(
                yBytes = yBytes,
                uBytes = uBytes,
                vBytes = vBytes,
                width = width,
                height = height,
                yRowStride = yRowStride,
                yPixelStride = yPixelStride,
                uRowStride = uRowStride,
                uPixelStride = uPixelStride,
                vRowStride = vRowStride,
                vPixelStride = vPixelStride,
                rotationDegrees = rotationDegrees
            )
        }
    }
}
