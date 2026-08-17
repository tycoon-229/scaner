package com.fpt.yuyama

import com.fpt.yuyama.scanner.platform.NativeScannerRegistry
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {

    private var nativeScannerRegistry: NativeScannerRegistry? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        nativeScannerRegistry = NativeScannerRegistry.registerWith(flutterEngine)
    }

    override fun onDestroy() {
        nativeScannerRegistry?.dispose()
        nativeScannerRegistry = null
        super.onDestroy()
    }
}
