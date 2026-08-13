package com.fpt.yuyama

import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MsiScannerChannel private constructor(
    flutterEngine: FlutterEngine
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val CHANNEL = "com.fpt.yuyama/msi_scanner"

        fun registerWith(flutterEngine: FlutterEngine): MsiScannerChannel {
            return MsiScannerChannel(flutterEngine)
        }
    }

    private val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
    private val backgroundExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

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

    fun dispose() {
        channel.setMethodCallHandler(null)
        backgroundExecutor.shutdown()
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

        executeDecode(result, source = "yuv") {
            MsiNativeDecoder.decodeYuvLuminance(
                yArray = bytes,
                width = width,
                height = height,
                rowStride = rowStride,
                scheme = checksumScheme
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

        executeDecode(result, source = "bitmap") {
            val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            if (bitmap == null) null else MsiNativeDecoder.decodeBitmap(bitmap, checksumScheme)
        }
    }

    private fun executeDecode(
        result: MethodChannel.Result,
        source: String,
        decode: () -> String?
    ) {
        backgroundExecutor.execute {
            val startedAt = System.nanoTime()
            try {
                val decodedText = decode()
                val durationMs = ((System.nanoTime() - startedAt) / 1_000_000L).toInt()
                mainHandler.post {
                    result.success(
                        mapOf(
                            "text" to decodedText,
                            "durationMs" to durationMs,
                            "source" to source
                        )
                    )
                }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error(
                        "MSI_DECODE_FAILED",
                        e.message ?: "MSI decode failed",
                        null
                    )
                }
            }
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
