package com.fpt.yuyama.scanner.gs1

import com.fpt.yuyama.scanner.platform.MethodChannelDecodeExecutor
import com.fpt.yuyama.scanner.platform.ScannerChannel
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class Gs1CompositeScannerChannel private constructor(
    flutterEngine: FlutterEngine
) : MethodChannel.MethodCallHandler, ScannerChannel {

    companion object {
        private const val CHANNEL = "com.fpt.yuyama/gs1_composite_scanner"

        fun registerWith(flutterEngine: FlutterEngine): Gs1CompositeScannerChannel {
            return Gs1CompositeScannerChannel(flutterEngine)
        }
    }

    private val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
    private val decodeExecutor = MethodChannelDecodeExecutor(
        errorCode = "GS1_COMPOSITE_DECODE_FAILED",
        fallbackErrorMessage = "GS1 Composite decode failed"
    )

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "decodeCompositeYuv" -> decodeYuv(call, result)
            "decodeCompositeBitmap" -> decodeBitmap(call, result)
            else -> result.notImplemented()
        }
    }

    override fun dispose() {
        channel.setMethodCallHandler(null)
        decodeExecutor.shutdown()
    }

    private fun decodeYuv(call: MethodCall, result: MethodChannel.Result) {
        val bytes = call.argument<ByteArray>("imageBytes")
        val width = call.argument<Int>("imageWidth") ?: 0
        val height = call.argument<Int>("imageHeight") ?: 0
        val rowStride = call.argument<Int>("rowStride") ?: width

        if (bytes == null || width <= 0 || height <= 0 || rowStride <= 0) {
            result.error(
                "INVALID_ARGUMENT",
                "YUV luminance data, width, height, and rowStride are required",
                null
            )
            return
        }

        executeDecode(result) {
            Gs1CompositeNativeDecoder.decodeYuvLuminance(
                yArray = bytes,
                width = width,
                height = height,
                rowStride = rowStride
            )
        }
    }

    private fun decodeBitmap(call: MethodCall, result: MethodChannel.Result) {
        val bytes = call.argument<ByteArray>("imageBytes")
        if (bytes == null || bytes.isEmpty()) {
            result.error("INVALID_ARGUMENT", "Encoded image bytes are required", null)
            return
        }

        executeDecode(result) {
            Gs1CompositeNativeDecoder.decodeBitmapBytes(bytes)
        }
    }

    private fun executeDecode(
        result: MethodChannel.Result,
        decode: () -> Map<String, Any?>
    ) {
        decodeExecutor.execute(result, decode)
    }
}
