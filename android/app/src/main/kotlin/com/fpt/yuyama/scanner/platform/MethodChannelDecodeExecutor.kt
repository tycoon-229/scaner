package com.fpt.yuyama.scanner.platform

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MethodChannelDecodeExecutor(
    private val errorCode: String,
    private val fallbackErrorMessage: String
) {
    private val backgroundExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    fun <T> execute(result: MethodChannel.Result, decode: () -> T) {
        backgroundExecutor.execute {
            try {
                val decoded = decode()
                mainHandler.post {
                    result.success(decoded)
                }
            } catch (e: UnsatisfiedLinkError) {
                mainHandler.post {
                    result.error(
                        "NATIVE_LIBRARY_UNAVAILABLE",
                        e.message ?: "Native scanner library is unavailable",
                        null
                    )
                }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error(
                        errorCode,
                        e.message ?: fallbackErrorMessage,
                        null
                    )
                }
            }
        }
    }

    fun shutdown() {
        backgroundExecutor.shutdown()
    }
}
