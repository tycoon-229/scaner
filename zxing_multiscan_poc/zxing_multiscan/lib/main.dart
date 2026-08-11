import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:flutter_zxing_example/theme/app_theme.dart';
import 'package:flutter_zxing_example/tabs/dynamsoft_tab.dart';
import 'package:flutter_zxing_example/tabs/scandit_tab.dart';
import 'package:flutter_zxing_example/tabs/zxing_tab.dart';
import 'package:scandit_flutter_datacapture_barcode/scandit_flutter_datacapture_barcode.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  zx.setLogEnabled(kDebugMode);
  debugPrint('ZXing version: ${zx.version()}');
  await ScanditFlutterDataCaptureBarcode.initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Barcode Scanner',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const DemoPage(),
    );
  }
}

class DemoPage extends StatelessWidget {
  const DemoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 0,
          bottom: const TabBar(
            tabs: [
              Tab(text: 'ZXing'),
              Tab(text: 'Dynamsoft'),
              Tab(text: 'Scandit'),
            ],
          ),
        ),
        body: TabBarView(children: [ZxingTab(), DynamsoftTab(), ScanditTab()]),
      ),
    );
  }
}
