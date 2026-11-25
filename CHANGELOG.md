## 2.7.0

- **TUA checkout screen in the plugin** (`import 'package:hyperpay_sdk/tua_checkout.dart'`). `TuaCheckoutScreen` moves from the example app into the plugin, so other apps can use it without copying files.
  - **Backend through your own client:** the screen makes its backend calls through a `TuaCheckoutBackend` built on your app's authenticated client. `TuaRestBackend` needs only one request function and the donation body. Login and tokens stay in your app.
  - **Flow logic in `TuaCheckoutSession`, covered by unit tests:**
    - one Idempotency-Key per attempt;
    - a failed payment is retried in place;
    - every result is confirmed with the backend.
  - **Unfinished donations:** on `payments.too_many_open_checkouts` the donor now chooses to continue an unfinished donation or cancel it and start over. Before, the example resumed one automatically. `onOpenCheckouts` overrides this.
  - **Result:** the screen returns a `TuaCheckoutResult`. `isPaid` is confirmed by the backend, and it also carries the payment ID and reference.
  - **Bundled assets:** the Cairo font (OFL) and the wallet marks now ship with the plugin, so `google_fonts` is no longer needed.

## 2.6.1

- **Fix `requestBinInfo`** on iOS and Android. It always failed (iOS: `BIN_INFO_ERROR` "bad request (400)", code 3000; Android: "Malformed server response"), because the SDK needs the checkout info fetched right before. The plugin now fetches it before every lookup, and the error message says which of the two requests failed.
- **Example app**: creates checkouts through a backend (`TuaApi`) instead of holding HyperPay credentials, and confirms each payment's outcome with the backend, because the SDK's success only means the payment was submitted.
- **Example app: TUA checkout screen** (`TuaCheckoutScreen`): a ready-to-use donation checkout in the TUA design. It has an expandable program list that can be turned off with `showItems`, and card fields that accept digits only in the number and CVV (length and Luhn checked) and English letters only in the name. It also has an optional "Save this card" checkbox (`allowSaveCard`), Apple Pay and Google Pay buttons, English and Arabic (right to left), and the bundled Cairo font. See the README's "TUA checkout screen" section.

## 2.6.0

Covers the HyperPay Mobile SDK documentation end to end on the bundled OPPWA 7.11.0. Every change is additive: existing calls compile and behave as before, except for the Android fixes listed below.

- **Ready-UI options** (`checkoutReadyUI(options: CheckoutOptions(...))`): store-card mode, skip CVV, card holder visibility and custom holder validation (`cardHolderPattern`), display total amount, back button, installments, billing address prefill/required fields, brand detection type/priority/appearance, device-auth security policies for tokens and brands, card scanning, custom logos, COPYandPAY `wpwlOptions`, STC Pay QR code, IBAN, expiry validation, birth date and token order. iOS also gets the full checkout theme (`CheckoutTheme`: style, 23 colors, 8 fonts, cancel button), Apple Pay button type and contact types. Android gets `androidThemeResource`, custom logo drawables, Google Pay submit types and window security.
- **Single-brand checkout** (`paymentBrand:`): open the Ready-UI directly on one brand's form, e.g. `STC_PAY`, `APPLEPAY` or `CARD` (HyperPay's "payment button" integration).
- **Callbacks**: `onBeforeSubmit` (abort, swap the checkout ID, or show an order summary before the payment is submitted), and on iOS `onApplePayShippingContactSelected` / `onApplePayShippingMethodSelected` to update the Apple Pay sheet. On iOS these delegate methods are only exposed to the SDK when a callback is registered, so checkouts without callbacks behave exactly as before.
- **Your-own-UI payments**: `payWithToken` (stored cards, optional CVV), `registerCard` (save a card without paying), `payStcPay`, `payWithBrand` (any brand plus HyperPay parameters), `payGooglePay` and `paySamsungPay` (Android, credentials from your own Google/Samsung Pay button), and the native Klarna Payments flow (`klarnaCreateSession` / `klarnaSubmitPayment`). `payCustomUI`'s `brand` is now optional (HyperPay detects it).
- **Apple Pay**: `ApplePayConfig` and `payApplePay` / `payApplePayDynamic` take summary items, supported networks, required billing/shipping contact fields, shipping methods, contact submission to HyperPay and the `APPLEPAYTKN` brand. New `isApplePayAvailable()`.
- **Google Pay** (`GooglePayConfig`): card networks, auth methods, price status, billing address (format, phone), email, shipping address and `gateway` for `GOOGLEPAYTKN`.
- **3-D Secure 2**: `ThreeDSConfig` (challenge UI types, timeout, locale, challenge-screen styling, requestor app URL, browser data, device-parameter blacklist, Android app-integrity settings) for `setup(...)` (your-own-UI payments) and `checkoutReadyUI(...)`. New `getThreeDSWarnings()`.
- **Helpers**: `validateCard` (native SDK validators), `getCheckoutInfo` (amount, currency, resource path, stored tokens, brands).
- **Fix (Android)**: the Ready-UI ignored the order of `brands` (it used a `HashSet`), which also decides brand detection priority. Order is now kept.
- **Fix (Android)**: the Ready-UI never offered to save the card (`storePaymentDetails` was NEVER, while iOS used PROMPT). Both platforms now default to `prompt`.
- **Fix (Android)**: `GooglePayConfig.merchantName` was ignored; it's now sent as Google Pay `merchantInfo`.
- **Fix (Android)**: `payApplePayDynamic` threw `MissingPluginException`; it now returns `errorCode: 'UNSUPPORTED'` like `payApplePay`.
- **Fix (Android)**: payment errors now include the SDK's error details (HyperPay result code and `parameterErrors`) in `errorMessage`, like iOS. Before, server rejections only said "Malformed server response".
- **Fix (iOS)**: CustomUI no longer logs the full card number, CVV and holder name (only the brand and last 4 digits).
- **Docs**: Android apps must use `FlutterFragmentActivity` (with `FlutterActivity`, `checkoutReadyUI` returns `NO_LAUNCHER`). New README sections for every feature, plus a coverage table mapping HyperPay's docs to the plugin.
- **Example**: new "Advanced features" screen; Android example moved to `FlutterFragmentActivity`, Gradle 9.3.1, AGP 9.1.0, Kotlin 2.4.0 and Flutter-managed compile/target SDK (it didn't build with JDK 25 before).
- **Tests**: Dart unit tests for the models and the native-to-Dart callbacks.
- **Android: built-in Kotlin.** The plugin no longer applies the Kotlin Gradle Plugin (`kotlin-android`); AGP 9 compiles its Kotlin, and `kotlinOptions` became `kotlin { compilerOptions }`. This removes Flutter's "migrate your plugin to Built-in Kotlin" build warning. It works with `android.builtInKotlin` set to `true` or `false`. Following Flutter's migration guide, the minimum is now **Flutter 3.44 / Dart 3.12** (was 3.38 / 3.10); projects on older Flutter keep resolving 2.5.x. The example app is migrated too.
- **Not available on OPPWA 7.11.0**: device fingerprinting (fraud management / Cybersource), `disablePayNowButtonOnError` and `onDetectedBin` arrive in newer SDK versions. The Ready-UI Samsung Pay sheet (`SamsungPayConfig`) needs Samsung's SDK jar compiled into the plugin, so only `paySamsungPay` is offered.

## 2.5.0

- **Swift Package Manager support (iOS)**: the plugin now ships `ios/hyperpay_sdk/Package.swift`, so apps with `enable-swift-package-manager` build without CocoaPods. The `OPPWAMobile` and `ipworks3ds_sdk` 7.11.0 XCFrameworks are the exact binaries of the `hyperpay_sdk_ios` pod (tag `7.11.0`), zipped and attached to the `ios-binaries-7.11.0` GitHub release. SPM fetches them as checksum-pinned `binaryTarget`s and embeds them as dynamic frameworks, along with their resource bundles and privacy manifests. CocoaPods keeps working unchanged: the Swift sources moved from `ios/Classes/` to `ios/hyperpay_sdk/Sources/hyperpay_sdk/`, and the podspec points there. When switching an existing app to SPM, remove the `hyperpay_sdk_ios` pod line from your Podfile (see README).
- **Fix (iOS)**: removed the `OPPCheckoutProviderDelegate` `checkoutProvider(_:continueSubmitting:completion:)` implementation. Its completion type (`(String, Bool)`) didn't match the SDK's (`(String?, Bool)`), so the SDK never called it (compiler warning "nearly matches optional requirement"). It was also wrong: it passed the resource path as the checkout ID and `abort: true`, so correcting the signature would have aborted every Ready-UI payment. No behavior change.
- **iOS**: `payApplePay` no longer uses the deprecated `OPPApplePayPaymentParams(checkoutID:paymentBrand:)`. The checkout ID is still validated before the Apple Pay sheet is shown, and the submitted params are still built with `tokenData` after authorization. The plugin's Swift sources now compile with zero warnings. No Dart API changes.
- **UIScene support (iOS)**: the plugin now registers as a scene delegate (`FlutterSceneLifeCycleDelegate`) and handles the shopper-result URL in `scene(_:openURLContexts:)`. Apps on the UIScene lifecycle (the Flutter template default since 3.38, and required to launch when built with Xcode 27 / the iOS 27 SDK) never receive `application(_:open:options:)`, so before this fix async/3DS payments in those apps never returned their result. The application-delegate handler is kept for apps that haven't migrated.
- **Breaking (constraint only)**: requires Flutter `>=3.38.0` / Dart `>=3.10.0`, the first release with the UIScene plugin APIs. Projects on older Flutter keep resolving `2.4.x`.
- **Example**: the example app now builds with Swift Package Manager (its Podfile was removed) and uses the UIScene lifecycle (`FlutterImplicitEngineDelegate` + `UIApplicationSceneManifest`).

## 2.4.2

- **Fix (iOS, Apple Pay)**: closing the Apple Pay sheet while an authorized payment was still being submitted to HyperPay was reported as `PaymentResult(isCanceled: true)`. `paymentAuthorizationViewControllerDidFinish` treated "no result yet" as "user cancelled", but in both `payApplePay` and `payApplePayDynamic` the result only arrives after `submitTransaction` (and, for the dynamic flow, `resolveCheckout`) completes — so a sheet dismissed mid-"Processing" (user tap, app backgrounded, sheet timeout) raced a payment that could still succeed. Apps that cancel their order on `isCanceled` then cancelled orders the gateway charged moments later. The plugin now tracks the in-flight submission and, while it is running, lets the submit completion deliver the real result (success, failure or a genuine cancellation error) instead of reporting a cancel. A dismissal before any authorization is still `isCanceled: true`. No Dart API changes.

## 2.4.1

- **Fix (Android)**: crash on opening checkout — `java.lang.NoClassDefFoundError: Failed resolution of: Landroidx/lifecycle/MediatorLiveData;` at `CheckoutViewModel.getTransactionResultLiveData` ← `BaseServiceActivity.onStart`, i.e. every Ready-UI / CustomUI payment on 2.4.0. `MediatorLiveData` lives in `androidx.lifecycle:lifecycle-livedata`, which nothing in 2.4.0's dependency block put on the runtime classpath: `lifecycle-livedata-core` (pulled in transitively by appcompat/fragment) only carries `LiveData`/`MutableLiveData`/`Observer`, and `lifecycle-viewmodel-ktx:2.8.7`'s only runtime dependencies are `lifecycle-viewmodel`, `kotlin-stdlib` and `kotlinx-coroutines-android` — its `lifecycle-livedata` entry is a BOM *constraint*, which aligns a version but never adds the artifact to the graph. Up to 2.3.2 the deprecated `lifecycle-extensions:2.2.0` supplied it transitively, so replacing it in 2.4.0 silently removed the class. `androidx.lifecycle:lifecycle-livedata:2.8.7` is now declared explicitly. Note the OPPWA SDK has referenced `MediatorLiveData` since at least 7.8.1 — this is purely the dependency swap, not the 7.11.0 upgrade. HyperPay's shipped `dependencies.txt` omits the artifact; their own `Android_Frameworks_7.11.0` Demo app still declares `lifecycle-extensions:2.2.0`. No Dart API changes.

## 2.4.0

- **Upgrade** underlying HyperPay (OPPWA) Mobile SDK from `7.8.1` → `7.11.0` on both iOS and Android. No public Dart API changes — every OPPWA symbol this plugin uses (`OPPPaymentProvider`, `OPPCheckoutSettings`, `OPPCheckoutProvider`, `OPPCardPaymentParams`, `OPPApplePayPaymentParams`, `requestBinInfo`/`OPPBinInfo` on iOS; `OppPaymentProvider`, `CheckoutSettings`, `CheckoutActivityResultContract`, `CardPaymentParams`, `Transaction`, `BinInfo`/`BinInfoListener` on Android) has an unchanged signature. The `ipworks3ds` 3DS2 build moves to `9625` on both platforms (was iOS `9485` / Android `9469`).
- **Fix (iOS & Android)**: also treat the new generic cancel code added in 7.11.0 (`OPPErrorCodeGeneralCancelError` = 9001 / `ErrorCode.ERROR_CODE_GENERAL_CANCEL`) as a shopper cancellation, so dismissing a processor-owned sheet returns `PaymentResult(isCanceled: true)` instead of a failure with a raw error string — same handling 2.3.2 added for page/3DS aborts.
- **Android**: transitive dependencies realigned with the `dependencies.txt` shipped in `Android_Frameworks_7.11.0` — `androidx.webkit` `1.12.1` → `1.13.0`, `gson` `2.10.1` → `2.11.0`, the deprecated `lifecycle-extensions:2.2.0` replaced by `lifecycle-viewmodel-ktx:2.8.7`, and `recyclerview:1.4.0` + `constraintlayout:2.2.1` (previously resolved only transitively) declared explicitly. The Braintree PayPal/Venmo dependencies new in 7.11.0 are intentionally omitted — those brands are not exposed by this plugin.

## 2.3.2

- **Fix (iOS & Android)**: report shopper-initiated aborts as cancellations instead of failures. When the user dismissed the 3-D Secure challenge sheet (`OPPErrorCodeThreeDS2ChallengeCanceled` / `ERROR_CODE_THREEDS2_CANCELED`) or closed the payment page (`OPPErrorCodeTransactionAborted` / `ERROR_CODE_TRANSACTION_ABORTED`), the SDK returned `PaymentResult(isSuccess: false, isCanceled: false)` with a raw, untranslated message like `"The challenge was canceled. [domain=…, code=6001, …]"`. These are now returned as `PaymentResult(isCanceled: true)` so apps can silently abort. No Dart API changes.

## 2.3.1

- **Fix (Android)**: stop skipping CVV for stored cards in the Ready-UI checkout. `checkoutReadyUI` previously set `CheckoutSkipCVVMode.FOR_STORED_CARDS`, so saved/tokenized cards were submitted without a CVV. Some acquirer connectors (e.g. SAIB MPGS) reject such requests with `800.100.156` ("transaction declined (format error)" / `INVALID_REQUEST`), so stored-card payments failed on Android while succeeding on iOS (which always collects CVV). Android now collects CVV for stored cards too, matching iOS behaviour. No Dart API changes.

## 2.3.0

- Add `HyperpaySdk.payApplePayDynamic(...)` — defers HyperPay checkout creation until the Apple Pay sheet has revealed the card network (`PKPaymentMethod.network`). The new `resolveCheckout` callback receives the detected network string (`"Visa"`, `"MasterCard"`, `"Mada"`, …) and returns a server-issued `checkoutId`, letting callers route MADA Apple Pay to DB and non-MADA to PA on the same code path. Existing `payApplePay` is unchanged. iOS only — Android Google Pay does not need this. The native presentation explicitly adds `.mada` to `PKPaymentRequest.supportedNetworks` (iOS 14.5+) so MADA-only cards are eligible for the wallet picker.
- Guard both Apple Pay entry points (`payApplePay`, `payApplePayDynamic`) with `PKPaymentAuthorizationViewController.canMakePayments()` before presenting. Without this PassKit can hard-abort the host app via `abort_with_payload` when the merchant ID isn't entitled (no `com.apple.developer.in-app-payments`, no payment-processing certificate, or no eligible Wallet cards). The guard returns a clean `errorCode: "APPLE_PAY_UNAVAILABLE"` result instead.

## 2.2.0

- **Upgrade** underlying HyperPay (OPPWA) Mobile SDK from `7.4.0` → `7.8.1` on both iOS and Android. No public Dart API changes. The `OPPWAMobile` and `ipworks3ds_sdk` frameworks are updated; ipworks3ds versions on iOS are now `9485`, Android `9469`. Transitive Android dependencies are unchanged.

## 2.1.0

- Add `HyperpaySdk.requestBinInfo(checkoutId, bin)` — wraps the OPPWA SDK's BIN service so callers can use HyperPay's authoritative BIN database to detect MADA (and other brands) instead of maintaining their own hardcoded BIN list. Returns `HyperpayBinInfo { brands, binType, type }` with a convenience `isMada` getter. Use this on add-card to route MADA cards through the DB flow and avoid PA-rail declines on Saudi-issued co-branded cards.

## 2.0.1

- Fix example app failing to build after the 2.0.0 breaking change — the example's Apple Pay screen still called `payApplePay` without the now-required `shopperResultUrl`, causing a compile error. No library changes.

## 2.0.0

**Breaking change**: `HyperpaySdk.payApplePay()` now requires `shopperResultUrl`.

The earlier 1.0.5 fix added `shopperResultURL` assignment on the iOS Apple Pay params, but the value was never plumbed through from Dart — the `payApplePay` Dart method didn't accept a `shopperResultUrl` argument, so the iOS plugin always saw a nil value and submitted Apple Pay payments to HyperPay with no `shopperResultURL`, causing `200.300.404 invalid or missing parameter`. Now mirrors the Ready UI flow: callers must pass `shopperResultUrl`, the Dart→iOS bridge forwards it, the iOS handler captures it, and the submission delegate assigns it on `OPPApplePayPaymentParams` before `submitTransaction`.

## 1.0.5

- Fix Apple Pay on iOS rejected by HyperPay with `200.300.404 invalid or missing parameter` — `shopperResultURL` was set on the card path but not on `OPPApplePayPaymentParams` before submission, so wallet payments reached HyperPay without it. Now mirrors the card flow and assigns `shopperResultURL` on the Apple Pay params before submitting the transaction. (Incomplete: see 2.0.0.)

## 1.0.4

- Fix Apple Pay cancel hanging forever on iOS — `pendingResult` was never called when user dismissed the payment sheet

## 1.0.3

- Added Apple Pay Merchant ID configuration guide with screenshots
- Fixed README links to use absolute URLs for pub.dev compatibility

## 1.0.2

- Fix package description length for pub.dev validation

## 1.0.1

- Redesigned example app with multi-screen layout (splash, home, saved cards)
- Added "Add Card" flow — tokenize cards without making a payment (PA + createRegistration)
- Extracted shared business logic into PaymentService
- Custom card form now opens in a modal bottom sheet
- Added .env.example for easier example app setup
- Added screenshots to README
- Added production integration guide with backend flow diagram
- Added UI color customization documentation

## 1.0.0

- Initial release wrapping HyperPay OPPWA Mobile SDK v7.4.0
- ReadyUI and CustomUI payment flows
- Support for VISA, MasterCard, MADA, Apple Pay, Google Pay, STC Pay
- Tokenization / stored cards
- 3DS2 authentication
- Test and Live payment modes
- Shopper result URL / callback scheme handling
- Payment status checking
