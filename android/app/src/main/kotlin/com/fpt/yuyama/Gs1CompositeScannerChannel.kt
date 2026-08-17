package com.fpt.yuyama

import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class Gs1CompositeScannerChannel private constructor(
    flutterEngine: FlutterEngine
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val CHANNEL = "com.fpt.yuyama/gs1_composite_scanner"

        fun registerWith(flutterEngine: FlutterEngine): Gs1CompositeScannerChannel {
            return Gs1CompositeScannerChannel(flutterEngine)
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
            "decodeGs1CompositeYuv" -> decodeYuv(call, result)
            "decodeGs1CompositeBitmap" -> decodeBitmap(call, result)
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

        if (bytes == null || width <= 0 || height <= 0 || rowStride <= 0) {
            result.error(
                "INVALID_ARGUMENT",
                "YUV luminance data, width, height, and rowStride are required",
                null
            )
            return
        }

        executeDecode(result, source = "yuv") {
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

        executeDecode(result, source = "bitmap") {
            val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            if (bitmap == null) null else Gs1CompositeNativeDecoder.decodeBitmap(bitmap)
        }
    }

    private fun executeDecode(
        result: MethodChannel.Result,
        source: String,
        decode: () -> Gs1CompositeNativeDecoder.Gs1CompositeResult?
    ) {
        backgroundExecutor.execute {
            val startedAt = System.nanoTime()
            try {
                val compositeResult = decode()
                val durationMs = ((System.nanoTime() - startedAt) / 1_000_000L).toInt()
                mainHandler.post {
                    if (compositeResult != null) {
                        result.success(
                            mapOf(
                                "text" to compositeResult.fullText,
                                "primary1dText" to compositeResult.primary1dText,
                                "composite2dText" to compositeResult.composite2dText,
                                "symbology" to compositeResult.symbology,
                                "durationMs" to durationMs,
                                "source" to source
                            )
                        )
                    } else {
                        result.success(null)
                    }
                }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error(
                        "GS1_COMPOSITE_DECODE_FAILED",
                        e.message ?: "GS1 Composite decode failed",
                        null
                    )
                }
            }
        }
    }
}
