import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:flutter_zxing_example/widgets/zxing_tab_widget.dart';
import 'package:scandit_flutter_datacapture_barcode/scandit_flutter_datacapture_barcode.dart';

import 'widgets/dynamsoft_tab_widget.dart';
import 'widgets/scandit_tab_widget.dart';

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
    return const MaterialApp(
      title: 'Barcode Scanner Comparison',
      debugShowCheckedModeBanner: false,
      home: DemoPage(),
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
          title: const TabBar(
            tabs: [
              Tab(text: 'ZXing'),
              Tab(text: 'Dynamsoft'),
              Tab(text: 'Scandit'),
            ],
          ),
        ),
        body: TabBarView(
          physics: const NeverScrollableScrollPhysics(),
          children: [
            ZxingTab(),
            DynamsoftTab(),
            const ScanditTabWidget(),
          ],
        ),
      ),
    );
  }
}
