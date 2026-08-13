package com.fpt.yuyama

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {

    private var msiScannerChannel: MsiScannerChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        msiScannerChannel = MsiScannerChannel.registerWith(flutterEngine)
    }

    override fun onDestroy() {
        msiScannerChannel?.dispose()
        msiScannerChannel = null
        super.onDestroy()
    }
}
