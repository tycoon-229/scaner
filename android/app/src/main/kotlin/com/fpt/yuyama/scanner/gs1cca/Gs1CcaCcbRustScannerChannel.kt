package com.fpt.yuyama.scanner.gs1cca

import com.fpt.yuyama.scanner.platform.MethodChannelDecodeExecutor
import com.fpt.yuyama.scanner.platform.ScannerChannel
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class Gs1CcaCcbRustScannerChannel private constructor(
    flutterEngine: FlutterEngine
) : MethodChannel.MethodCallHandler, ScannerChannel {

    companion object {
        private const val CHANNEL = "com.fpt.yuyama/gs1_cca_ccb_rust_scanner"

        fun registerWith(flutterEngine: FlutterEngine): Gs1CcaCcbRustScannerChannel {
            return Gs1CcaCcbRustScannerChannel(flutterEngine)
        }
    }

    private val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
    private val decodeExecutor = MethodChannelDecodeExecutor(
        errorCode = "GS1_CCA_CCB_RUST_DECODE_FAILED",
        fallbackErrorMessage = "GS1 CC-A/B Rust decode failed"
    )

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "decodeCcaCcbYuv" -> decodeYuv(call, result)
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
        val hintLeft = call.argument<Int>("hintLeft") ?: -1
        val hintTop = call.argument<Int>("hintTop") ?: -1
        val hintRight = call.argument<Int>("hintRight") ?: -1
        val hintBottom = call.argument<Int>("hintBottom") ?: -1

        if (bytes == null || width <= 0 || height <= 0 || rowStride <= 0) {
            result.error(
                "INVALID_ARGUMENT",
                "YUV luminance data, width, height, and rowStride are required",
                null
            )
            return
        }

        decodeExecutor.execute(result) {
            Gs1CcaCcbRustDecoder.decodeYuvLuminance(
                yArray = bytes,
                width = width,
                height = height,
                rowStride = rowStride,
                hintLeft = hintLeft,
                hintTop = hintTop,
                hintRight = hintRight,
                hintBottom = hintBottom
            )
        }
    }
}
