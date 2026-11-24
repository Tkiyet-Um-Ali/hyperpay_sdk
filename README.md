# HyperPay SDK for Flutter

[![pub package](https://img.shields.io/pub/v/hyperpay_sdk.svg)](https://pub.dev/packages/hyperpay_sdk)
[![license](https://img.shields.io/github/license/hrvojecukman/hyperpay_sdk.svg)](https://github.com/hrvojecukman/hyperpay_sdk/blob/main/LICENSE)

Flutter plugin wrapping the official **HyperPay (OPPWA) Mobile SDK v7.11.0** for Android and iOS.

## Features

- **ReadyUI** — Pre-built checkout screen with all payment brands, every `CheckoutSettings` option (store-card mode, skip CVV, billing address, installments, brand detection, device-auth security policies, card scanning, custom logos, full iOS theme), single-brand checkout ("payment button"), and a before-submit callback
- **CustomUI** — Your own forms: cards (with or without brand), stored-card tokens, card registration without payment, STC Pay, Google Pay, Samsung Pay, native Klarna, and any other brand by name
- **Apple Pay** (iOS) — Ready-UI and your own button, dynamic checkout per card network, shipping contact/method updates, billing/shipping contact submission, `APPLEPAYTKN`
- **Google Pay** (Android) — Ready-UI with full request configuration, or your own Google Pay button
- **VISA, MasterCard, MADA, STC Pay, Klarna, PayPal** and every other HyperPay brand
- **Tokenization** — Save cards during payment or stand-alone, list a checkout's stored tokens, pay with a token
- **3DS2** — Handled automatically; challenge-screen styling, app URL and device security warnings are configurable
- **Async payment flows** — Redirect-based payments (e.g. 3DS, bank redirects), on both the AppDelegate and UIScene lifecycles
- **Card helpers** — BIN lookup and native card field validators
- **Test and Live modes**

## Screenshots

| Home                                                                                           | ReadyUI                                                                                               | Custom UI                                                                                                | Apple Pay                                                                                                | Saved Cards                                                                                                  |
| ---------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| ![Home](https://raw.githubusercontent.com/hrvojecukman/hyperpay_sdk/main/screenshots/home.png) | ![ReadyUI](https://raw.githubusercontent.com/hrvojecukman/hyperpay_sdk/main/screenshots/ready_ui.png) | ![Custom UI](https://raw.githubusercontent.com/hrvojecukman/hyperpay_sdk/main/screenshots/custom_ui.png) | ![Apple Pay](https://raw.githubusercontent.com/hrvojecukman/hyperpay_sdk/main/screenshots/apple_pay.png) | ![Saved Cards](https://raw.githubusercontent.com/hrvojecukman/hyperpay_sdk/main/screenshots/saved_cards.png) |

## Requirements

| Platform | Minimum Version      |
| -------- | -------------------- |
| iOS      | 13.0                 |
| Android  | API 24 (Android 7.0) |
| Flutter  | 3.44+                |
| Dart     | 3.12+                |

---

## Getting Started

There are **2 steps** to integrate HyperPay into your Flutter app:

1. Install the plugin
2. Configure your Android and iOS projects

> **Note:** The native HyperPay OPPWA SDK binaries (AARs and XCFrameworks) are fetched automatically at build time via JitPack (Android) and Swift Package Manager or CocoaPods (iOS). No manual binary placement is required.

### Step 1 — Install the Plugin

```sh
flutter pub add hyperpay_sdk
```

Or add manually to your `pubspec.yaml`:

```yaml
dependencies:
  hyperpay_sdk: ^2.6.0
```

Then run:

```sh
flutter pub get
```

### Step 2 — Platform Setup

#### Android

**1. Add JitPack repository** in your project-level `settings.gradle` (inside `dependencyResolutionManagement.repositories` or `pluginManagement.repositories`):

```gradle
maven { url 'https://jitpack.io' }
```

**2. Set minimum SDK and Java version** in `android/app/build.gradle`:

```gradle
android {
    compileSdk 35

    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = '17'
    }

    defaultConfig {
        minSdk 24
        targetSdk 35
    }
}
```

**3. Configure the shopper result URL scheme** in `android/app/src/main/AndroidManifest.xml`:

```xml
<activity android:name=".MainActivity"
    android:launchMode="singleTop"
    ...>

    <!-- HyperPay shopper result callback -->
    <intent-filter>
        <action android:name="android.intent.action.VIEW" />
        <category android:name="android.intent.category.DEFAULT" />
        <category android:name="android.intent.category.BROWSABLE" />
        <data android:scheme="com.your.app.payments" />
    </intent-filter>

    <!-- Main launcher (keep existing) -->
    <intent-filter>
        <action android:name="android.intent.action.MAIN" />
        <category android:name="android.intent.category.LAUNCHER" />
    </intent-filter>
</activity>
```

> **Important:** The scheme must be **lowercase only** (e.g. `com.your.app.payments`, not `com.your.App.Payments`). This must match the `shopperResultUrl` parameter you pass to the SDK.

**4. Use `FlutterFragmentActivity`** in `android/app/src/main/kotlin/.../MainActivity.kt`. The Ready-UI checkout is launched with the Activity Result API, which needs a `ComponentActivity`; with the default `FlutterActivity`, `checkoutReadyUI` returns `NO_LAUNCHER`:

```kotlin
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity()
```

**5. Google Pay (optional)** — add inside `<application>` in your `AndroidManifest.xml`:

```xml
<meta-data
    android:name="com.google.android.gms.wallet.api.enabled"
    android:value="true" />
```

#### iOS

The plugin supports both **Swift Package Manager** and **CocoaPods**. Flutter picks the integration automatically.

**Swift Package Manager (recommended, on by default in recent Flutter).** If it is off, enable it either globally (`flutter config --enable-swift-package-manager`) or for your app only in `pubspec.yaml`:

```yaml
flutter:
  config:
    enable-swift-package-manager: true
```

No Podfile changes are needed: the HyperPay `OPPWAMobile` and `ipworks3ds_sdk` XCFrameworks are downloaded and checksum-verified by SPM, then embedded automatically. If your app previously used the CocoaPods setup below, remove the `hyperpay_sdk_ios` pod line and the static-framework `pre_install` hook from your Podfile (otherwise Xcode fails with *"Multiple commands produce …/OPPWAMobile.framework"*). If HyperPay was your only pod, run `pod deintegrate` in `ios/`. Then skip to step 3.

**CocoaPods.** If you don't use Swift Package Manager:

**1. Set deployment target** in `ios/Podfile`:

```ruby
platform :ios, '13.0'
```

**2. Configure static framework** in `ios/Podfile` inside the `target 'Runner'` block:

```ruby
target 'Runner' do
  use_frameworks!
  use_modular_headers!

  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))

  # HyperPay SDK requires static framework
  $static_framework = ['hyperpay_sdk']

  pre_install do |installer|
    Pod::Installer::Xcode::TargetValidator.send(
      :define_method,
      :verify_no_static_framework_transitive_dependencies
    ) {}
    installer.pod_targets.each do |pod|
      if $static_framework.include?(pod.name)
        def pod.build_type
          Pod::BuildType.static_library
        end
      end
    end
  end
end
```

Then run:

```sh
cd ios && pod install
```

**3. Configure URL scheme** — add to `ios/Runner/Info.plist`:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>CFBundleURLName</key>
        <string>com.your.app.payments</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>com.your.app.payments</string>
        </array>
    </dict>
</array>
```

Or in Xcode: **Target > Info > URL Types** and add your scheme.

**4. Apple Pay (optional)** — enable the **Apple Pay** capability in Xcode and configure your merchant ID. See the full step-by-step guide: **[Apple Pay Merchant ID Setup](https://github.com/hrvojecukman/hyperpay_sdk/blob/main/APPLE_PAY_SETUP.md)**.

---

## Running the Example App

```sh
cd example
cp .env.example .env
```

Edit `.env` with your HyperPay credentials:

```
HYPERPAY_ENTITY_ID=your_entity_id_here
HYPERPAY_ACCESS_TOKEN=your_access_token_here
```

Then run:

```sh
flutter run
```

---

## Usage

### Initialize the SDK

```dart
import 'package:hyperpay_sdk/hyperpay_sdk.dart';

// Call once at app start
await HyperpaySdk.setup(mode: PaymentMode.test);
```

### ReadyUI (Pre-built Checkout Screen)

The simplest way to accept payments. Launches a pre-built payment screen from the SDK.

```dart
final result = await HyperpaySdk.checkoutReadyUI(
  checkoutId: checkoutId,  // obtained from your server
  brands: ['VISA', 'MASTER', 'MADA'],
  shopperResultUrl: 'com.your.app.payments',
  // Optional: Google Pay (Android only)
  googlePayConfig: GooglePayConfig(
    gatewayMerchantId: 'your-merchant-id',
    merchantName: 'Your Company',
    countryCode: 'SA',
    totalPrice: 100.0,
    currencyCode: 'SAR',
  ),
  // Optional: Apple Pay (iOS only)
  applePayConfig: ApplePayConfig(
    merchantId: 'merchant.com.your.app',
    countryCode: 'SA',
    currencyCode: 'SAR',
    amount: 100.0,
    companyName: 'Your Company',
  ),
);

if (result.isSuccess) {
  // Verify payment on your server using result.resourcePath
  print('Resource path: ${result.resourcePath}');
} else if (result.isCanceled) {
  print('Payment canceled');
} else {
  print('Error: ${result.errorCode} - ${result.errorMessage}');
}
```

### CustomUI (Your Own Payment Form)

Build your own payment form and submit card details directly.

```dart
final result = await HyperpaySdk.payCustomUI(
  checkoutId: checkoutId,  // obtained from your server
  brand: 'VISA',
  cardNumber: '4111111111111111',
  holder: 'John Doe',
  expiryMonth: '12',
  expiryYear: '2025',
  cvv: '123',
  shopperResultUrl: 'com.your.app.payments',
  tokenize: true,  // save card for future payments
);

if (result.isSuccess) {
  if (result.transactionType == 'async') {
    // Redirect-based payment (3DS, bank redirect) — wait for callback
    print('Async payment, redirecting...');
  } else {
    // Synchronous payment — verify on server
    print('Resource path: ${result.resourcePath}');
  }
}
```

### Apple Pay (iOS only)

> Requires Merchant ID setup in Apple Developer portal. See **[Apple Pay Merchant ID Setup](https://github.com/hrvojecukman/hyperpay_sdk/blob/main/APPLE_PAY_SETUP.md)** for the full guide.

```dart
final result = await HyperpaySdk.payApplePay(
  checkoutId: checkoutId,
  merchantId: 'merchant.com.your.app',
  countryCode: 'SA',
  currencyCode: 'SAR',
  amount: 100.0,
  companyName: 'Your Company',
  shopperResultUrl: 'com.your.app.payments',
);
```

### Ready-UI options and callbacks

Every Ready-UI setting is in `CheckoutOptions`. All fields are optional.

```dart
final result = await HyperpaySdk.checkoutReadyUI(
  checkoutId: checkoutId,
  brands: ['MADA', 'VISA', 'MASTER'], // display order; also the brand-detection priority
  shopperResultUrl: 'com.your.app.payments',
  options: const CheckoutOptions(
    storePaymentDetails: StorePaymentDetailsMode.prompt, // default on both platforms
    skipCvv: SkipCvvMode.never,
    displayTotalAmount: true,
    billingAddress: BillingAddress(country: 'SA', cityRequired: true),
    brandDetectionType: BrandDetectionType.binList,
    tokensSecurityPolicy: SecurityPolicyMode.requiredIfAvailable, // Face ID / screen lock for saved cards
    installmentEnabled: true,
    installmentOptions: [1, 3, 6],
    cardHolderPattern: r"^[A-Za-z][A-Za-z .'-]{1,49}$",
    theme: CheckoutTheme(accentColor: 0xFF00897B), // iOS
    androidThemeResource: 'MyCheckoutTheme',          // Android, extends Theme.Checkout
  ),
  threeDSConfig: const ThreeDSConfig(
    uiCustomization: ThreeDSUiCustomization(
      toolbar: ThreeDSToolbarCustomization(backgroundColor: 0xFF00897B),
    ),
  ),
  // Called before the payment is submitted: show an order summary, re-create
  // the checkout for the chosen brand, or abort.
  onBeforeSubmit: (info) async {
    final ok = await confirmOrder(info.paymentBrand);
    return ok ? const BeforeSubmitDecision.proceed() : const BeforeSubmitDecision.abort();
  },
);
```

Open the checkout directly on one brand's form (the "payment button" integration) with `paymentBrand`, e.g. `'STC_PAY'`, `'APPLEPAY'`, `'GOOGLEPAY'`, or `'CARD'` for the card form.

Apple Pay in the Ready-UI can update the sheet when the shopper changes shipping details: set `requiredShippingContactFields` and `shippingMethods` in `ApplePayConfig`, and pass `onApplePayShippingContactSelected` / `onApplePayShippingMethodSelected`.

### Stored cards (tokens)

```dart
// 1. Create the checkout on your server with registrations[0].id=<token>, …
// 2. List the tokens and pay with one from your own UI:
final info = await HyperpaySdk.getCheckoutInfo(checkoutId: checkoutId);
final token = info.tokens.first; // brand, last 4 digits, expiry, holder
final result = await HyperpaySdk.payWithToken(
  checkoutId: checkoutId,
  tokenId: token.tokenId,
  brand: token.paymentBrand,
  cvv: cvvFromShopper, // if your acquirer needs it
  shopperResultUrl: 'com.your.app.payments',
);
```

Save a card **without paying**: create the checkout with `createRegistration=true` and no `paymentType`, then call `HyperpaySdk.registerCard(...)` and read the token (`id`) from the registration status on your server. Delete tokens from your server (HyperPay's registration delete API), not from the app.

### Other payment methods from your own UI

| Method | Brand |
| --- | --- |
| `payStcPay(verificationOption:, mobilePhone:)` | STC Pay (OTP or QR code) |
| `payGooglePay(paymentToken:, cardBrand:)` | Google Pay from your own button, e.g. with the `pay` package (Android) |
| `paySamsungPay(paymentCredential:)` | Samsung Pay; get the credential with the Samsung Pay SDK in your app (Android) |
| `klarnaCreateSession(...)` → `klarnaSubmitPayment(...)` | Klarna Payments native flow; render Klarna with Klarna's Mobile SDK using the returned `clientToken` |
| `payWithBrand(brand:, parameters:)` | Any other brand (PayPal, Klarna redirect, iDEAL, Affirm, …) with optional HyperPay parameters |

### Card helpers

```dart
final v = await HyperpaySdk.validateCard(number: number, expiryMonth: mm, expiryYear: yyyy, cvv: cvv);
if (!v.isValid) showErrors(v);

final bin = await HyperpaySdk.requestBinInfo(checkoutId: checkoutId, bin: number.substring(0, 6));
if (bin.isMada) { /* route through DB */ }
```

### 3-D Secure 2

3DS2 runs automatically. Optionally pass a `ThreeDSConfig` to `setup(...)` (your-own-UI payments) or `checkoutReadyUI(...)` to style the challenge screens, set the app URL for app-to-app authentication (`requestorAppUrl`), or restrict device data. `HyperpaySdk.getThreeDSWarnings()` returns the 3DS SDK's device security warnings (jailbreak/root, emulator, debugger).

### Check Payment Status

```dart
final info = await HyperpaySdk.getPaymentStatus(
  checkoutId: checkoutId,
  resourcePath: result.resourcePath,
);
print('Status: ${info.status}');
```

> **Important:** Always verify the final payment status on your backend server using the HyperPay server-to-server API. Never rely solely on the client-side result.

---

## Production Integration

In production, **never** store your HyperPay access token in the client app. The example app calls the HyperPay API directly for convenience, but a real app should use a backend:

```
┌─────────┐         ┌──────────┐         ┌──────────────┐
│  App    │──(1)──▶│  Your    │──(2)──▶│  HyperPay    │
│ (Flutter)│◀──(3)──│  Server  │◀──(4)──│  API         │
│         │         │          │         │              │
│  SDK ───(5)────────────────────────▶│  Payment     │
│         │◀──(6)──────────────────────│  Gateway     │
│         │──(7)──▶│  Verify  │──(8)──▶│              │
└─────────┘         └──────────┘         └──────────────┘
```

1. App requests a checkout from your server (amount, currency, etc.)
2. Your server calls `POST https://oppwa.com/v1/checkouts` with your credentials
3. Your server returns the `checkoutId` to the app
4. _(HyperPay responds to your server)_
5. App passes `checkoutId` to `HyperpaySdk.checkoutReadyUI(...)` or `payCustomUI(...)`
6. SDK handles the payment flow and returns a `PaymentResult`
7. App sends `resourcePath` to your server for verification
8. Your server calls HyperPay's server-to-server API to confirm the payment

```dart
// In your app — get checkoutId from YOUR backend, not HyperPay directly
final checkoutId = await yourApi.createCheckout(amount: 100.0, currency: 'SAR');

final result = await HyperpaySdk.checkoutReadyUI(
  checkoutId: checkoutId,
  brands: ['VISA', 'MASTER', 'MADA'],
  shopperResultUrl: 'com.your.app.payments',
);

if (result.isSuccess) {
  // Verify on your server
  await yourApi.verifyPayment(resourcePath: result.resourcePath!);
}
```

See the [HyperPay documentation](https://wordpresshyperpay.docs.oppwa.com/) for full API details.

---

## HyperPay Mobile SDK coverage

How each part of [HyperPay's Mobile SDK documentation](https://hyperpay.docs.oppwa.com/integrations/mobile-sdk) maps to this plugin (OPPWA 7.11.0):

| HyperPay feature | Plugin |
| --- | --- |
| Ready-to-Use UI, payment brands | `checkoutReadyUI(brands:)` |
| Payment buttons (single brand) | `checkoutReadyUI(paymentBrand:)` |
| UI customization | `CheckoutOptions.theme` (iOS), `androidThemeResource` (Android), `customLogoAssets` / `androidCustomLogoDrawables` |
| Internationalization | `lang:`; override texts with `OPPCheckout.strings` (iOS) or `res/values-xx/strings.xml` (Android) in your app |
| Advanced options (total amount, back button, skip CVV, holder, installments, billing address, brand detection, security, callbacks, summary page, COPYandPAY `wpwlOptions`) | `CheckoutOptions`, `onBeforeSubmit` |
| Asynchronous payments | `shopperResultUrl:`, handled for AppDelegate and UIScene apps |
| Tokenization (Ready-UI and custom UI) | `storePaymentDetails`, `payCustomUI(tokenize:)`, `registerCard`, `getCheckoutInfo().tokens`, `payWithToken` |
| Card scanning | `CheckoutOptions.cardScanningEnabled` (camera on iOS, NFC on Android) |
| SDK & your own UI | `payCustomUI`, `payStcPay`, `payWithBrand`, `validateCard`, `getCheckoutInfo` |
| BIN detection | `requestBinInfo` |
| Apple Pay | `ApplePayConfig`, `payApplePay`, `payApplePayDynamic`, shipping callbacks, `APPLEPAYTKN` |
| Google Pay | `GooglePayConfig`, `googlePaySubmitTypes`, `payGooglePay`, `GOOGLEPAYTKN` |
| Klarna Payments | Redirect: brand in `checkoutReadyUI` / `payWithBrand`. Native: `klarnaCreateSession` + `klarnaSubmitPayment` with Klarna's Mobile SDK |
| Samsung Pay | `paySamsungPay` (your own Samsung Pay button). The Ready-UI Samsung Pay sheet needs Samsung's SDK jar compiled into the plugin, which can't be redistributed, so it isn't exposed. |
| 3D Secure 2 | `ThreeDSConfig`, `getThreeDSWarnings` |
| Error codes | `PaymentResult.errorCode` / `errorMessage`; shopper cancellations become `isCanceled: true` |
| Fraud management / Cybersource device fingerprint, "disable Pay button on error", `onDetectedBin` | Not available: these arrive in OPPWA SDK versions newer than 7.11.0 |

---

## API Reference

### `HyperpaySdk`

| Method | Description |
| --- | --- |
| `setup(mode:, threeDSConfig:)` | Initialize the SDK. Call once before any payment. |
| `checkoutReadyUI(...)` | Launch the pre-built checkout UI (options, single brand, callbacks). Returns `PaymentResult`. |
| `payCustomUI(...)` | Card payment from your own form; `brand` optional. Returns `PaymentResult`. |
| `payWithToken(...)` | Pay with a stored token. Returns `PaymentResult`. |
| `registerCard(...)` | Save a card without paying. Returns `PaymentResult`. |
| `payStcPay(...)` | STC Pay from your own UI. Returns `PaymentResult`. |
| `payWithBrand(...)` | Any brand by name with optional parameters. Returns `PaymentResult`. |
| `payGooglePay(...)` | Google Pay token from your own button (Android). Returns `PaymentResult`. |
| `paySamsungPay(...)` | Samsung Pay credential (Android). Returns `PaymentResult`. |
| `klarnaCreateSession(...)`, `klarnaSubmitPayment(...)` | Klarna Payments native flow. Return `KlarnaSession`. |
| `payApplePay(...)`, `payApplePayDynamic(...)` | Apple Pay from your own button (iOS). Return `PaymentResult`. |
| `isApplePayAvailable(...)` | Whether Apple Pay can be used on this device (iOS). |
| `requestBinInfo(...)` | Brand / type for a card BIN. Returns `HyperpayBinInfo`. |
| `validateCard(...)` | Native card field validation. Returns `CardValidationResult`. |
| `getCheckoutInfo(...)` | Amount, currency, resource path and stored tokens of a checkout. Returns `CheckoutInfo`. |
| `getPaymentStatus(...)` | Get checkout info for verification. Returns `CheckoutInfo`. |
| `getThreeDSWarnings()` | 3DS SDK device security warnings. Returns `List<ThreeDSWarning>`. |

### `PaymentResult`

| Field             | Type      | Description                                |
| ----------------- | --------- | ------------------------------------------ |
| `isSuccess`       | `bool`    | Whether the payment was successful         |
| `isCanceled`      | `bool`    | Whether the user canceled                  |
| `resourcePath`    | `String?` | Resource path for server-side verification |
| `errorCode`       | `String?` | Error code from the SDK                    |
| `errorMessage`    | `String?` | Human-readable error message               |
| `transactionType` | `String?` | `"sync"` or `"async"`                      |

### `CheckoutInfo`

| Field          | Type      | Description                       |
| -------------- | --------- | --------------------------------- |
| `status`       | `String?` | Payment status (e.g. `"CHARGED"`) |
| `paymentBrand` | `String?` | Brand used (e.g. `"VISA"`)        |
| `amount`, `currencyCode` | `double?`, `String?` | Checkout amount and currency |
| `resourcePath` | `String?` | Resource path for the status query |
| `tokens`       | `List<StoredToken>` | Stored payment methods attached to the checkout |
| `brands`       | `List<String>` | Brands enabled for the checkout (Android) |
| `rawResponse`  | `Map?`    | Raw SDK response data             |

### `PaymentMode`

| Value  | Description            |
| ------ | ---------------------- |
| `test` | Sandbox environment    |
| `live` | Production environment |

---

## Supported Payment Brands

| Brand       | ReadyUI          | CustomUI          | Notes                      |
| ----------- | ---------------- | ----------------- | -------------------------- |
| `VISA`      | Yes              | Yes               |                            |
| `MASTER`    | Yes              | Yes               |                            |
| `MADA`      | Yes              | Yes               | Saudi Arabia debit network |
| `STC_PAY`   | Yes              | No                |                            |
| `APPLEPAY`  | Yes (via config) | Via `payApplePay` | iOS only                   |
| `GOOGLEPAY` | Yes (via config) | N/A               | Android only               |

---

## Customizing UI Colors

The ReadyUI checkout screen can be themed to match your app's branding.

### iOS

Pass the `themeColor` parameter to `checkoutReadyUI`. This tints the navigation bar, buttons, and controls:

```dart
final result = await HyperpaySdk.checkoutReadyUI(
  checkoutId: checkoutId,
  brands: ['VISA', 'MASTER', 'MADA'],
  shopperResultUrl: 'com.your.app.payments',
  themeColor: const Color(0xFF6200EE).toARGB32(), // your brand color
);
```

### Android

The `themeColor` parameter has no effect on Android. Instead, override the SDK's theme in your `android/app/src/main/res/values/styles.xml`:

```xml
<!-- Override the HyperPay checkout theme -->
<style name="OpwaTheme" parent="Theme.MaterialComponents.Light">
    <item name="colorPrimary">@color/your_primary</item>
    <item name="colorPrimaryDark">@color/your_primary_dark</item>
    <item name="colorAccent">@color/your_accent</item>
</style>
```

### CustomUI

With CustomUI you build the payment form yourself, so you have full control over colors using Flutter's `ThemeData`.

---

## Troubleshooting

### Android: `ClassNotFoundException` or missing SDK classes

Ensure JitPack is added to your repositories (`maven { url 'https://jitpack.io' }`). Run `flutter clean && flutter pub get` and rebuild.

### iOS: Framework not found

1. Run `cd ios && pod install --repo-update`
2. Clean build: `flutter clean && flutter pub get`

### iOS Simulator: 3DS crashes

The **deploy** (release) 3DS framework doesn't include simulator slices. Simulator testing may require the debug 3DS framework.

### Async payments not returning

Ensure the URL scheme is correctly configured in both your native project and matches the `shopperResultUrl` parameter exactly (lowercase, no special characters).

### Google Pay not showing

1. Add the wallet meta-data to `AndroidManifest.xml`
2. Ensure `play-services-wallet` dependency is present
3. Google Pay requires a real device (not emulator) in most cases

---

## Support

If this package saved you time, consider buying me a coffee:

<a href="https://buymeacoffee.com/hrvojecukman" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" width="217" height="60"></a>

## Contributing

Contributions are welcome! Please open an issue or submit a pull request on [GitHub](https://github.com/hrvojecukman/hyperpay_sdk).

## License

MIT License. See [LICENSE](LICENSE) for details.
