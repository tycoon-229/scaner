# POC MultiScan

POC MultiScan is a Flutter proof-of-concept app for comparing barcode scanning
flows across three engines:

- ZXing (`flutter_zxing`)
- Dynamsoft Barcode Reader
- Scandit Data Capture Barcode

The app supports live camera scanning, single-code and multi-code modes, a shared
result list UI, gallery image decoding for supported engines, and a debug preview
mode for checking result UI without scanning real barcodes.

## Project Info

- App name: `POC MultiScan`
- Android application ID: `com.fpt.yuyama`
- iOS bundle identifier: `com.fpt.yuyama`
- Primary color: orange
- Flutter package name: `flutter_zxing_example`

## Known-Good Environment

This project was last verified with:

- Flutter `3.44.9` stable
- Dart `3.12.2`
- Xcode `26.6`
- Java `21.0.11`
- Gradle wrapper `8.14`
- iOS deployment target `15.0`

Required by `pubspec.yaml`:

- Dart SDK `>=3.11.0 <4.0.0`
- Flutter stable with Android and iOS toolchains configured

## Main Dependencies

- `flutter_zxing: ^2.3.0`
- `dynamsoft_barcode_reader_bundle_flutter: ^11.4.3000`
- `dynamsoft_capture_vision_flutter: ^3.4.3000`
- `scandit_flutter_datacapture_barcode: ^8.5.2`
- `scandit_flutter_datacapture_core: ^8.5.2`
- `camera: >=0.10.5 <0.13.0`
- `image_picker: ^1.0.0`

## Repository Structure

```text
lib/
  config/
    license_keys.dart          # Scandit and Dynamsoft license constants
    scan_result_preview.dart   # Hardcoded preview results for UI checks
  extensions/
    code_format_extensions.dart
  services/
    msi_scanner_service.dart
  tabs/
    zxing_tab.dart
    dynamsoft_tab.dart
    scandit_tab.dart
  theme/
    app_theme.dart
  utils/
    scan_entries.dart
  widgets/
    camera_scanner/
    scan_mode_controls.dart
    scan_result_widget.dart
    scanner_camera_preview.dart
    scanner_live_scaffold.dart
```

## Setup

1. Install Flutter and verify both mobile toolchains.

   ```bash
   flutter doctor
   ```

2. Clone the project and enter the app directory.

   ```bash
   cd zxing_multiscan_poc/zxing_multiscan
   ```

3. Install Flutter packages.

   ```bash
   flutter pub get
   ```

4. Configure license keys.

   Update `lib/config/license_keys.dart` with valid Scandit and Dynamsoft keys
   for your bundle ID/application ID.

5. For iOS, install CocoaPods dependencies.

   ```bash
   cd ios
   pod install
   cd ..
   ```

6. For physical iOS devices, open Xcode and configure signing.

   ```bash
   open ios/Runner.xcworkspace
   ```

   In Xcode, select the `Runner` target, choose a Development Team under
   `Signing & Capabilities`, then let Xcode automatically create the development
   certificate and provisioning profile.

## Permissions

Android permissions are declared in:

```text
android/app/src/main/AndroidManifest.xml
```

The app requests camera, network, and gallery/media read permissions needed for
live scanning and image decoding.

iOS usage descriptions are declared in:

```text
ios/Runner/Info.plist
```

The app declares camera, photo library, and local-network debug usage messages.

## Run

List available devices:

```bash
flutter devices
```

Run on the selected default device:

```bash
flutter run --debug
```

Run on a specific device:

```bash
flutter run -d <device-id> --debug
```

Example for a connected iPhone:

```bash
flutter run -d 00008110-0001758A2E06401E --debug
```

Build Android debug APK:

```bash
flutter build apk --debug
```

Build iOS debug app without code signing:

```bash
flutter build ios --debug --no-codesign
```

## Result UI Preview Mode

Use preview mode when you want to check the result-list UI on a simulator or
emulator without scanning real barcode data.

```bash
flutter run --debug --dart-define=PREVIEW_SCAN_RESULTS=true
```

Run preview mode on a specific device:

```bash
flutter run -d <device-id> --debug --dart-define=PREVIEW_SCAN_RESULTS=true
```

When `PREVIEW_SCAN_RESULTS=true`, the app opens directly on the scan-result page
with hardcoded sample results from `lib/config/scan_result_preview.dart`.

When the flag is omitted or set to `false`, the app runs the normal live scanner
flow.

Shared IDE launch configurations are included:

- VS Code: select `POC MultiScan Preview` from Run and Debug.
- Android Studio / IntelliJ: select `POC MultiScan Preview` from the run
  configuration dropdown.

The normal `POC MultiScan` configuration runs the live scanner flow.

## App Flow

1. The app opens with three horizontally swipeable tabs: `ZXing`, `Dynamsoft`,
   and `Scandit`.
2. Each tab displays a live scanner surface with the shared orange UI theme.
3. Use the bottom-right selector to switch between:
   - `Single Code`: stop after the first decoded barcode and show the result.
   - `Multi Code`: keep collecting unique results and show the success counter.
4. In multi-code mode, tap `Success: (n)` to open the shared result list.
5. On ZXing and Dynamsoft tabs, use the photo-library icon to decode a barcode
   from an image file.
6. On the result page, copy individual values or tap `Scan Again` to return to
   scanning.

## Engine Notes

- ZXing uses the shared camera scanner widget and `flutter_zxing` decoding.
- Dynamsoft uses the shared camera scanner widget and Dynamsoft decoding.
- Scandit uses Scandit's native capture context and camera integration.
- Gallery image decoding is currently wired for ZXing and Dynamsoft.

## Common Commands

Format source:

```bash
dart format lib test
```

Analyze source:

```bash
flutter analyze
```

Clean generated build output:

```bash
flutter clean
flutter pub get
```

## Troubleshooting

### iOS signing fails

Open the workspace in Xcode:

```bash
open ios/Runner.xcworkspace
```

Then select `Runner > Signing & Capabilities`, choose a Development Team, and
make sure the bundle identifier is `com.fpt.yuyama`.

### iPhone does not show Developer Mode

Developer Mode usually appears after installing or attempting to run a
development-signed app from Xcode. Connect the device, run from Xcode once, then
check:

```text
Settings > Privacy & Security > Developer Mode
```

### Flutter cannot control Xcode

Allow automation access on macOS:

```text
System Settings > Privacy & Security > Automation
```

Enable access for the terminal or IDE running Flutter.

### No scan data is available on simulator/emulator

Use preview mode:

```bash
flutter run --debug --dart-define=PREVIEW_SCAN_RESULTS=true
```

### Swift Package Manager warning

Some barcode plugins may still use CocoaPods instead of Swift Package Manager on
iOS. Keep using CocoaPods with `pod install` until those plugins add SPM support.
