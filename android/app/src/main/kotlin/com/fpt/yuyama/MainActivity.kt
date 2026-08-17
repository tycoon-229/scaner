package com.fpt.yuyama

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {

    private var msiScannerChannel: MsiScannerChannel? = null
    private var gs1CompositeScannerChannel: Gs1CompositeScannerChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        msiScannerChannel = MsiScannerChannel.registerWith(flutterEngine)
        gs1CompositeScannerChannel = Gs1CompositeScannerChannel.registerWith(flutterEngine)
    }

    override fun onDestroy() {
        msiScannerChannel?.dispose()
        msiScannerChannel = null

        gs1CompositeScannerChannel?.dispose()
        gs1CompositeScannerChannel = null

        super.onDestroy()
    }
}

