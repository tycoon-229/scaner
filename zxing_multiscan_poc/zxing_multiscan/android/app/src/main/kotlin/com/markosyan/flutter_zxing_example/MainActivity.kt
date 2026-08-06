package com.markosyan.flutter_zxing_example

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

class MainActivity : FlutterFragmentActivity() {

    private val CHANNEL = "com.example/msi_scanner"

    private val backgroundExecutor = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "decodeMsiYuv" -> {
                    val bytes = call.argument<ByteArray>("imageBytes")
                    val width = call.argument<Int>("imageWidth") ?: 0
                    val height = call.argument<Int>("imageHeight") ?: 0

                    if (bytes != null && width > 0 && height > 0) {
                        backgroundExecutor.execute {
                            val decodedText = MsiNativeDecoder.decodeYuvLuminance(bytes, width, height, width)

                            android.os.Handler(android.os.Looper.getMainLooper()).post {
                                result.success(decodedText)
                            }
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "YUV data is null or size error", null)
                    }
                }
                "decodeMsiBitmap" -> {
                    val bytes = call.argument<ByteArray>("imageBytes")
                    if (bytes != null) {
                        backgroundExecutor.execute {
                            val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                            val decodedText = if (bitmap != null) MsiNativeDecoder.decodeBitmap(bitmap) else null

                            android.os.Handler(android.os.Looper.getMainLooper()).post {
                                result.success(decodedText)
                            }
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "imageBytes data null", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        backgroundExecutor.shutdown()
    }
}
