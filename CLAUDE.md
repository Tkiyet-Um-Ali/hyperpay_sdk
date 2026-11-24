# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Flutter plugin wrapping the HyperPay OPPWA Mobile SDK v7.11.0. Provides ReadyUI (pre-built checkout), CustomUI (card form), Apple Pay (iOS), and Google Pay (Android) payment flows. Supports VISA, MasterCard, MADA, STC Pay, 3DS2, and tokenization.

## Build & Development Commands

```bash
flutter pub get              # Install dependencies
flutter analyze              # Lint (uses flutter_lints with prefer_single_quotes)
flutter test                 # Run tests
dart format lib/             # Format code

# Example app
cd example && flutter pub get && flutter run

# iOS: the example uses Swift Package Manager (no pod install needed)
cd example && flutter build ios --simulator
```

## Architecture

```
Dart API (lib/hyperpay_sdk.dart - HyperpaySdk class)
    │  MethodChannel: "com.hyperpay.sdk/channel"
    ├── iOS: ios/hyperpay_sdk/Sources/hyperpay_sdk/HyperpaySdkPlugin.swift (shared by SPM Package.swift + CocoaPods podspec)
    │   └── OPPWAMobile.xcframework + ipworks3ds XCFramework
    └── Android: android/src/main/kotlin/.../HyperpaySdkPlugin.kt
        └── oppwa.mobile AAR + ipworks3ds AAR
```

**Method channel calls (Dart → native):** `setup`, `checkoutReadyUI`, `payCustomUI`, `payWithToken`, `registerCard`, `payStcPay`, `payWithBrand`, `payGooglePay` / `paySamsungPay` (Android), `klarnaCreateSession`, `klarnaSubmitPayment`, `validateCard`, `payApplePay` / `payApplePayDynamic` / `isApplePayAvailable` (iOS), `requestBinInfo`, `getCheckoutInfo`, `getPaymentStatus`, `getThreeDSWarnings`. Platform-only methods return error code `UNSUPPORTED` on the other platform (never `notImplemented`).

**Native → Dart calls:** `resolveApplePayCheckout`, `onBeforeSubmit`, `applePayShippingContactSelected`, `applePayShippingMethodSelected` (handled in `lib/src/hyperpay_sdk_method_channel.dart`). On iOS the optional `OPPCheckoutProviderDelegate` methods live on `HyperpayCheckoutDelegate`, which overrides `responds(to:)` so the SDK only sees a method when Dart registered its callback; implementing them unconditionally makes the SDK wait on them for every payment. On Android the Ready-UI callbacks are Parcelable and reach the plugin through a static holder (`CheckoutCallbacks.kt`).

**Transaction types:**
- **Sync** — immediate result with resourcePath for server verification
- **Async** — browser redirect (Safari VC on iOS, Intent on Android) for 3DS/gateway, then URL scheme callback returns resourcePath

**Data models** live in `lib/src/models/` (`toMap()` / `fromMap()` define the channel map shapes): `PaymentMode`, `PaymentResult`, `CheckoutInfo` / `StoredToken`, `GooglePayConfig`, `ApplePayConfig` (+ summary items, shipping), `CheckoutOptions`, `CheckoutTheme`, `ThreeDSConfig`, `payment_extras.dart` (before-submit, STC Pay, card validation, Klarna).

**Real native APIs:** trust the OPPWA 7.11.0 headers/swiftinterface (CocoaPods cache `hyperpay_sdk_ios/7.11.0-*`) and the Android AAR classes (`javap`) over HyperPay's web docs, which have typos and describe newer SDK versions.

## Platform Requirements

- **iOS:** min 13.0, Swift 5.0, CocoaPods consumers need the static-framework Podfile hook (see README); SPM needs nothing
- **Android:** minSdk 24, Java 17, Kotlin 2.0.21, Gradle 8.7.3
- **iOS integration:** Swift Package Manager (`ios/hyperpay_sdk/Package.swift`) and CocoaPods (`ios/hyperpay_sdk.podspec`) are both supported. The example app uses SPM (`enable-swift-package-manager: true` in `example/pubspec.yaml`, no Podfile).
- **Native SDK binaries** are not bundled in this repo — they are pulled from:
  - iOS (CocoaPods): pod `hyperpay_sdk_ios` (version-matched to the OPPWA version, tag `7.11.0`) — https://github.com/hrvojecukman/hyperpay_sdk_ios
  - iOS (SPM): the same xcframeworks, zipped (`ditto -c -k --keepParent X.xcframework X.xcframework.zip`) as assets on the `ios-binaries-<oppwa version>` release of https://github.com/Tkiyet-Um-Ali/hyperpay_sdk, referenced by URL + checksum (`swift package compute-checksum`) in `Package.swift`. Never replace an existing asset; publish a new release instead.
  - Android: JitPack `com.github.hrvojecukman.hyperpay_sdk_android:{oppwa,ipworks3ds,ipworks3ds_deploy}` (tag `v7.11.0.0`) — https://github.com/hrvojecukman/hyperpay_sdk_android
  - Upgrading the native SDK means: swap the binaries in those two repos, bump + tag them, publish a new `ios-binaries-<version>` release with the zips, then bump `ios/hyperpay_sdk.podspec`, `ios/hyperpay_sdk/Package.swift` (version + both checksums) and `android/build.gradle`

## Linting

`analysis_options.yaml` extends `package:flutter_lints/flutter.yaml` with `avoid_print: false` and `prefer_single_quotes: true`.
