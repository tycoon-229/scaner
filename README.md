# POC MultiScan

POC MultiScan is a Flutter proof-of-concept app for comparing barcode scanning
flows across three engines:

- ZXing (`flutter_zxing`)
- Dynamsoft Barcode Reader
- Scandit Data Capture Barcode

The app supports live camera scanning, single-code and multi-code modes, a shared
result list UI, gallery image decoding for supported engines, and a debug preview
mode for checking result UI without scanning real barcodes.

GS1 Composite is handled as special native/fallback paths. Regular barcode
scanning can still use `flutter_zxing`, Dynamsoft, or Scandit, while the ZXing
tab adds native helpers for GS1 Composite proof-of-concept decoding.

## Project Info

- App name: `POC MultiScan`
- Android application ID: `com.fpt.yuyama`
- iOS bundle identifier: `com.fpt.yuyama`
- Primary color: orange
- Flutter package name: `poc_multi_scan`

## Known-Good Environment

This project was last verified with:

- Flutter `3.44.9` stable
- Dart `3.12.2`
- Xcode `26.6`
- Java `21.0.11`
- Gradle wrapper `8.14`
- iOS deployment target `15.0`
- Android NDK `28.2.13676358`

Required by `pubspec.yaml`:

- Dart SDK `>=3.11.0 <4.0.0`
- Flutter stable with Android and iOS toolchains configured

Required for Android Rust CC-A/CC-B builds:

- Rust stable with target `aarch64-linux-android`
- `cargo-ndk`

## Main Dependencies

- `flutter_zxing: ^2.3.0`
- `dynamsoft_barcode_reader_bundle_flutter: ^11.4.3000`
- `dynamsoft_capture_vision_flutter: ^3.4.3000`
- `scandit_flutter_datacapture_barcode: ^8.5.2`
- `scandit_flutter_datacapture_core: ^8.5.2`
- `camera: >=0.10.5 <0.13.0`
- `image_picker: ^1.0.0`

## Native Dependencies

Android GS1 Composite uses ZXing-C++ as a Git submodule:

```text
android/app/src/main/cpp/third_party/zxing-cpp
```

The submodule is pinned to ZXing-C++ `v3.1.1`, which includes MicroPDF417
decoder support required for GS1 Composite CC-A and CC-B. The normal Flutter
`flutter_zxing` package remains in use for non-composite ZXing scans.

Android also includes an experimental Rust fallback for GS1 Composite CC-A and
CC-B:

```text
android/app/src/main/rust/gs1_cca_ccb_scanner
```

This module is built as `libgs1_cca_ccb_scanner.so` and is called through a
separate Flutter method channel. It uses:

- `zedbar` for GS1 DataBar / DataBar Expanded linear candidates
- `anyd` for MicroPDF417 / PDF417 component candidates

The fallback runs after the existing Android CC-C path and logs with the
`[ZXing][RustCCAB]` prefix. The Rust crate versions are pinned by
`Cargo.lock`; the first Android build downloads the crates from crates.io.

License note: `anyd` is MIT, while `zedbar` is LGPL-3.0-or-later. Review this
before shipping the Rust fallback in a production app.

iOS GS1 Composite uses Apple Vision. On iOS 17 and newer, Vision can coalesce
GS1 Composite symbols and report CC-A, CC-B, or CC-C. On older supported iOS
versions, the native module falls back to pairing the linear carrier and
PDF417/MicroPDF417 component by geometry.

## Repository Structure

```text
.run/                         # Shared Android Studio / IntelliJ run configs
.vscode/
  launch.json                 # Shared VS Code run configs
lib/
  config/
    license_keys.dart          # Scandit and Dynamsoft license constants
    scan_result_preview.dart   # Hardcoded preview results for UI checks
  extensions/
    code_format_extensions.dart
  services/
    native_scanners/
      gs1/                    # Neutral GS1 model, parser, assembler, channel API
      msi/                    # Native MSI channel API and coordinator
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
android/
  app/src/main/cpp/
    gs1_composite_scanner.cpp
    third_party/zxing-cpp      # Git submodule pinned to v3.1.1
  app/src/main/kotlin/com/fpt/yuyama/scanner/
    gs1/
    gs1cca/
    mlkit/
    msi/
  app/src/main/rust/
    gs1_cca_ccb_scanner/       # Experimental Rust Android CC-A/B fallback
ios/
  Runner/NativeScanners/
    GS1/
    MSI/
```

## Setup

1. Install Flutter and verify both mobile toolchains.

   ```bash
   flutter doctor
   ```

2. Clone the project and enter the app directory.

   ```bash
   git clone --recurse-submodules <repo-url> poc_multi_scan
   cd poc_multi_scan
   ```

   If you already cloned without submodules, initialize them before building:

   ```bash
   git submodule update --init --recursive --depth 1
   ```

3. Install Flutter packages.

   ```bash
   flutter pub get
   ```

4. Configure license keys.

   Update `lib/config/license_keys.dart` with valid Scandit and Dynamsoft keys
   for your bundle ID/application ID.

5. For Android, install Rust dependencies for the experimental CC-A/B fallback.

   macOS:

   ```bash
   brew install rustup cargo-ndk
   /opt/homebrew/opt/rustup/bin/rustup toolchain install stable --profile minimal --target aarch64-linux-android
   ```

   Windows PowerShell:

   ```powershell
   winget install Rustlang.Rustup
   rustup target add aarch64-linux-android
   cargo install cargo-ndk
   ```

   Linux:

   ```bash
   rustup target add aarch64-linux-android
   cargo install cargo-ndk
   ```

   The Android Gradle build calls `cargo ndk` automatically and writes generated
   `.so` files under Gradle build output.

6. For iOS, install CocoaPods dependencies.

   ```bash
   cd ios
   pod install
   cd ..
   ```

7. For physical iOS devices, open Xcode and configure signing.

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

## IDE Run Configurations

The repository includes shared run configurations so teammates can pull the
source and run the same modes from the IDE toolbar.

### VS Code

Shared file:

```text
.vscode/launch.json
```

Available configurations:

- `POC MultiScan`: runs the normal live scanner flow.
- `POC MultiScan Preview`: runs with
  `--dart-define=PREVIEW_SCAN_RESULTS=true`.

Open the Run and Debug panel, select the desired configuration, then press Run.

### Android Studio / IntelliJ

Shared files:

```text
.run/POC MultiScan.run.xml
.run/POC MultiScan Preview.run.xml
```

Available configurations:

- `POC MultiScan`: runs the normal live scanner flow.
- `POC MultiScan Preview`: runs with
  `--dart-define=PREVIEW_SCAN_RESULTS=true`.

Select the desired configuration from the Run Configuration dropdown in the
toolbar. If the configurations do not appear immediately after pulling the
source, reopen the project or run `File > Sync Project with Gradle Files`.

Device selection is intentionally not committed. Each developer should select
their own simulator, emulator, or physical device in the IDE.

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

- VS Code: `.vscode/launch.json`
- Android Studio / IntelliJ: `.run/*.run.xml`

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
- On Android, the ZXing tab uses ML Kit as the fast primary path for Code128 +
  PDF417 CC-C-style candidates, then uses the experimental Rust fallback for
  DataBar + MicroPDF417 CC-A/CC-B candidates.
- On iOS, GS1 Composite uses the dedicated native GS1 Composite module, then
  falls back to Dart-side pairing for decoded candidates.
- Dynamsoft uses the shared camera scanner widget and Dynamsoft decoding.
- Scandit uses Scandit's native capture context and camera integration.
- Gallery image decoding is currently wired for ZXing and Dynamsoft.
- Android still links ZXing-C++ `v3.1.1` through the submodule for native GS1
  experiments and parity with the iOS/native path.
- iOS GS1 Composite uses Vision with coalesced composite symbologies on iOS 17+
  and geometry pairing fallback for separate observations.

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

### Android CMake cannot find ZXing-C++

Make sure the ZXing-C++ submodule has been initialized:

```bash
git submodule update --init --recursive --depth 1
```

The expected path is:

```text
android/app/src/main/cpp/third_party/zxing-cpp/core
```

### Android Rust CC-A/B build fails

Check that Rust, the Android target, and `cargo-ndk` are installed:

```bash
cargo --version
cargo ndk --version
rustup target list --installed
```

The installed target list must include:

```text
aarch64-linux-android
```

On Windows, run the same checks in PowerShell. If `cargo ndk` is not found,
make sure `%USERPROFILE%\.cargo\bin` is on `PATH`, then restart the terminal or
IDE.

### Android APK does not contain the Rust CC-A/B library

Build the debug APK and inspect native libraries:

```bash
flutter build apk --debug
unzip -l build/app/outputs/flutter-apk/app-debug.apk | grep libgs1_cca_ccb_scanner
```

Expected entry:

```text
lib/arm64-v8a/libgs1_cca_ccb_scanner.so
```

### Swift Package Manager warning

Some barcode plugins may still use CocoaPods instead of Swift Package Manager on
iOS. Keep using CocoaPods with `pod install` until those plugins add SPM support.
