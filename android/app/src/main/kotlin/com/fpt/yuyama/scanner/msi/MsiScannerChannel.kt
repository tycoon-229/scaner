package com.fpt.yuyama.scanner.msi

import android.graphics.BitmapFactory
import com.fpt.yuyama.scanner.platform.MethodChannelDecodeExecutor
import com.fpt.yuyama.scanner.platform.ScannerChannel
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MsiScannerChannel private constructor(
    flutterEngine: FlutterEngine
) : MethodChannel.MethodCallHandler, ScannerChannel {

    companion object {
        private const val CHANNEL = "com.fpt.yuyama/msi_scanner"

        fun registerWith(flutterEngine: FlutterEngine): MsiScannerChannel {
            return MsiScannerChannel(flutterEngine)
        }
    }

    private val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
    private val decodeExecutor = MethodChannelDecodeExecutor(
        errorCode = "MSI_DECODE_FAILED",
        fallbackErrorMessage = "MSI decode failed"
    )

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "decodeMsiYuv" -> decodeYuv(call, result)
            "decodeMsiBitmap" -> decodeBitmap(call, result)
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
        val checksumScheme = checksumSchemeFrom(call.argument<String>("checksumScheme"))

        if (bytes == null || width <= 0 || height <= 0 || rowStride <= 0) {
            result.error(
                "INVALID_ARGUMENT",
                "YUV luminance data, width, height, and rowStride are required",
                null
            )
            return
        }

        executeDecode(result) {
            mapOf(
                "text" to MsiNativeDecoder.decodeYuvLuminance(
                    yArray = bytes,
                    width = width,
                    height = height,
                    rowStride = rowStride,
                    scheme = checksumScheme
                ),
                "source" to "yuv"
            )
        }
    }

    private fun decodeBitmap(call: MethodCall, result: MethodChannel.Result) {
        val bytes = call.argument<ByteArray>("imageBytes")
        val checksumScheme = checksumSchemeFrom(call.argument<String>("checksumScheme"))

        if (bytes == null || bytes.isEmpty()) {
            result.error("INVALID_ARGUMENT", "Encoded image bytes are required", null)
            return
        }

        executeDecode(result) {
            val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            mapOf(
                "text" to if (bitmap == null) null else MsiNativeDecoder.decodeBitmap(bitmap, checksumScheme),
                "source" to "bitmap"
            )
        }
    }

    private fun executeDecode(
        result: MethodChannel.Result,
        decode: () -> Map<String, Any?>
    ) {
        decodeExecutor.execute(result) {
            val startedAt = System.nanoTime()
            val decoded = decode()
            decoded + ("durationMs" to ((System.nanoTime() - startedAt) / 1_000_000L).toInt())
        }
    }

    private fun checksumSchemeFrom(value: String?): MsiNativeDecoder.ChecksumScheme {
        return try {
            MsiNativeDecoder.ChecksumScheme.valueOf(value ?: "AUTO")
        } catch (ignored: IllegalArgumentException) {
            MsiNativeDecoder.ChecksumScheme.AUTO
        }
    }
}
