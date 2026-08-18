package com.fpt.yuyama.scanner.platform

import com.fpt.yuyama.scanner.gs1.Gs1CompositeScannerChannel
import com.fpt.yuyama.scanner.mlkit.MlKitBarcodeScannerChannel
import com.fpt.yuyama.scanner.msi.MsiScannerChannel
import io.flutter.embedding.engine.FlutterEngine

class NativeScannerRegistry private constructor(
    private val channels: List<ScannerChannel>
) {
    companion object {
        fun registerWith(flutterEngine: FlutterEngine): NativeScannerRegistry {
            return NativeScannerRegistry(
                listOf(
                    MsiScannerChannel.registerWith(flutterEngine),
                    Gs1CompositeScannerChannel.registerWith(flutterEngine),
                    MlKitBarcodeScannerChannel.registerWith(flutterEngine)
                )
            )
        }
    }

    fun dispose() {
        channels.asReversed().forEach(ScannerChannel::dispose)
    }
}
