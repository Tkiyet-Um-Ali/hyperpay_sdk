export 'src/models.dart';

import 'src/hyperpay_sdk_method_channel.dart';
import 'src/models.dart';

/// Main entry point for the HyperPay SDK Flutter plugin.
///
/// Wraps the official HyperPay (OPPWA) Mobile SDK v7.11.0
/// for both Android and iOS.
///
/// **Usage:**
/// ```dart
/// // 1. Initialize
/// await HyperpaySdk.setup(mode: PaymentMode.test);
///
/// // 2. Pay with ReadyUI
/// final result = await HyperpaySdk.checkoutReadyUI(
///   checkoutId: 'your-checkout-id',
///   brands: ['VISA', 'MASTER', 'MADA'],
///   shopperResultUrl: 'com.your.app.payments',
/// );
///
/// // 3. Check result
/// if (result.isSuccess) {
///   // Verify on server using result.resourcePath
/// }
/// ```
///
/// Platform-only methods (Apple Pay on iOS; Google Pay / Samsung Pay on
/// Android) return a `PaymentResult` with `errorCode: 'UNSUPPORTED'` on the
/// other platform.
class HyperpaySdk {
  HyperpaySdk._();

  /// Initialize the HyperPay SDK with the given [mode].
  ///
  /// Must be called before any other method. [threeDSConfig] applies to 3-D
  /// Secure 2 challenges in your-own-UI payments (`payCustomUI`,
  /// `payWithToken`, …); for the Ready-UI pass it to [checkoutReadyUI].
  static Future<void> setup({
    required PaymentMode mode,
    ThreeDSConfig? threeDSConfig,
  }) {
    return HyperpaySdkMethodChannel.setup(
      mode: mode,
      threeDSConfig: threeDSConfig,
    );
  }

  /// Launch the ReadyUI checkout (pre-built payment screen).
  ///
  /// - [checkoutId]: The checkout ID obtained from your server.
  /// - [brands]: Payment brands, in display order (e.g.
  ///   `['VISA', 'MASTER', 'MADA']`). The order also decides which brand wins
  ///   when a card number matches several, unless
  ///   [CheckoutOptions.brandDetectionPriority] is set.
  /// - [shopperResultUrl]: URL scheme for async payment callbacks (e.g.
  ///   `'com.your.app.payments'`).
  /// - [googlePayConfig]: Google Pay configuration (Android only).
  /// - [applePayConfig]: Apple Pay configuration (iOS only).
  /// - [lang]: Language code for the checkout UI (e.g. `'en'`, `'ar'`; on
  ///   Android a locale such as `'ar_AR'` also works).
  /// - [themeColor]: ARGB color int (`Color.value`) to tint the checkout UI.
  ///   On iOS this sets the main accent colors; for full control use
  ///   [CheckoutOptions.theme]. On Android this has no effect — use
  ///   [CheckoutOptions.androidThemeResource].
  /// - [paymentBrand]: open the checkout directly on this brand's form,
  ///   skipping the payment method list (e.g. `'STC_PAY'`, `'APPLEPAY'`, or
  ///   `'CARD'` for the card form with brand detection). This is the
  ///   "payment button" integration.
  /// - [options]: every other Ready-UI setting (store card mode, skip CVV,
  ///   billing address, installments, brand detection, security, theme, …).
  /// - [threeDSConfig]: 3-D Secure 2 settings for this checkout.
  /// - [onBeforeSubmit]: called just before the payment is submitted. Return
  ///   [BeforeSubmitDecision.proceed] (optionally with a new checkout ID,
  ///   e.g. after updating the amount server-side) or
  ///   [BeforeSubmitDecision.abort]. Use it for an order summary page too.
  ///   Apple's sheet allows about 30 seconds, so keep server calls short.
  /// - [onApplePayShippingContactSelected] /
  ///   [onApplePayShippingMethodSelected] (iOS): update the Apple Pay sheet
  ///   (summary items, shipping methods) when the shopper changes shipping
  ///   contact or method. Set `requiredShippingContactFields` and
  ///   `shippingMethods` in [applePayConfig].
  ///
  /// Returns a [PaymentResult] with the transaction outcome.
  static Future<PaymentResult> checkoutReadyUI({
    required String checkoutId,
    required List<String> brands,
    String? shopperResultUrl,
    GooglePayConfig? googlePayConfig,
    ApplePayConfig? applePayConfig,
    String? lang,
    int? themeColor,
    String? paymentBrand,
    CheckoutOptions? options,
    ThreeDSConfig? threeDSConfig,
    Future<BeforeSubmitDecision> Function(BeforeSubmitInfo info)?
    onBeforeSubmit,
    Future<ApplePayShippingUpdate> Function(ApplePayContact contact)?
    onApplePayShippingContactSelected,
    Future<ApplePayShippingUpdate> Function(ApplePayShippingMethod method)?
    onApplePayShippingMethodSelected,
  }) {
    return HyperpaySdkMethodChannel.checkoutReadyUI(
      checkoutId: checkoutId,
      brands: brands,
      shopperResultUrl: shopperResultUrl,
      googlePayConfig: googlePayConfig,
      applePayConfig: applePayConfig,
      lang: lang,
      themeColor: themeColor,
      paymentBrand: paymentBrand,
      options: options,
      threeDSConfig: threeDSConfig,
      onBeforeSubmit: onBeforeSubmit,
      onApplePayShippingContactSelected: onApplePayShippingContactSelected,
      onApplePayShippingMethodSelected: onApplePayShippingMethodSelected,
    );
  }

  /// Submit a card payment using CustomUI (your own payment form).
  ///
  /// - [checkoutId]: The checkout ID obtained from your server.
  /// - [brand]: Payment brand (e.g. `'VISA'`, `'MASTER'`, `'MADA'`). Leave it
  ///   `null` to let HyperPay detect the brand from the card number (needs
  ///   brand auto-detection enabled for your entity in the HyperPay portal).
  /// - [cardNumber]: Card number without spaces.
  /// - [holder]: Cardholder name.
  /// - [expiryMonth]: Two-digit expiry month (e.g. `'01'`).
  /// - [expiryYear]: Four-digit expiry year (e.g. `'2025'`).
  /// - [cvv]: Card verification value.
  /// - [shopperResultUrl]: URL scheme for async payment callbacks.
  /// - [tokenize]: Whether to tokenize the card for future payments.
  ///
  /// Returns a [PaymentResult] with the transaction outcome.
  static Future<PaymentResult> payCustomUI({
    required String checkoutId,
    String? brand,
    required String cardNumber,
    required String holder,
    required String expiryMonth,
    required String expiryYear,
    required String cvv,
    String? shopperResultUrl,
    bool tokenize = false,
  }) {
    return HyperpaySdkMethodChannel.payCustomUI(
      checkoutId: checkoutId,
      brand: brand,
      cardNumber: cardNumber,
      holder: holder,
      expiryMonth: expiryMonth,
      expiryYear: expiryYear,
      cvv: cvv,
      shopperResultUrl: shopperResultUrl,
      tokenize: tokenize,
    );
  }

  /// Pay with a stored payment method (token / registration ID) from your own
  /// UI, e.g. a "saved cards" list.
  ///
  /// - [tokenId]: the registration ID your server stored. The checkout
  ///   **must** be created with this token in `registrations[n].id`;
  ///   otherwise HyperPay rejects the payment ("registrationId is not in the
  ///   list of registrations[*].id values"). [getCheckoutInfo] lists those
  ///   tokens.
  /// - [brand]: the token's brand (e.g. `'VISA'`, `'MADA'`).
  /// - [cvv]: the card's CVV, if your acquirer requires it for stored cards.
  static Future<PaymentResult> payWithToken({
    required String checkoutId,
    required String tokenId,
    required String brand,
    String? cvv,
    String? shopperResultUrl,
  }) {
    return HyperpaySdkMethodChannel.payWithToken(
      checkoutId: checkoutId,
      tokenId: tokenId,
      brand: brand,
      cvv: cvv,
      shopperResultUrl: shopperResultUrl,
    );
  }

  /// Save a card without paying (stand-alone registration) from your own UI.
  ///
  /// Create the checkout on your server with `createRegistration=true` and
  /// **without** `paymentType`. Then query the registration status from your
  /// server with the returned resource path; the response `id` is the token.
  static Future<PaymentResult> registerCard({
    required String checkoutId,
    String? brand,
    required String cardNumber,
    required String holder,
    required String expiryMonth,
    required String expiryYear,
    required String cvv,
    String? shopperResultUrl,
  }) {
    return HyperpaySdkMethodChannel.registerCard(
      checkoutId: checkoutId,
      brand: brand,
      cardNumber: cardNumber,
      holder: holder,
      expiryMonth: expiryMonth,
      expiryYear: expiryYear,
      cvv: cvv,
      shopperResultUrl: shopperResultUrl,
    );
  }

  /// Pay with STC Pay from your own UI.
  ///
  /// With [StcPayVerificationOption.mobilePhone] pass [mobilePhone] (e.g.
  /// `'05xxxxxxxx'`); the SDK then opens STC Pay's OTP page. With
  /// [StcPayVerificationOption.qrCode] a QR code page is shown.
  static Future<PaymentResult> payStcPay({
    required String checkoutId,
    required StcPayVerificationOption verificationOption,
    String? mobilePhone,
    String? shopperResultUrl,
  }) {
    return HyperpaySdkMethodChannel.payStcPay(
      checkoutId: checkoutId,
      verificationOption: verificationOption,
      mobilePhone: mobilePhone,
      shopperResultUrl: shopperResultUrl,
    );
  }

  /// Pay with any other brand from your own UI, e.g. redirect brands such as
  /// `PAYPAL`, `KLARNA_PAYMENTS_PAYLATER` (redirect flow), `IDEAL` or
  /// `AFFIRM`. Extra brand parameters go in [parameters] (HyperPay parameter
  /// names, e.g. `{'bankAccount.bic': '...'}`).
  static Future<PaymentResult> payWithBrand({
    required String checkoutId,
    required String brand,
    Map<String, String>? parameters,
    String? shopperResultUrl,
  }) {
    return HyperpaySdkMethodChannel.payWithBrand(
      checkoutId: checkoutId,
      brand: brand,
      parameters: parameters,
      shopperResultUrl: shopperResultUrl,
    );
  }

  /// Submit a Google Pay payment from your own Google Pay button (Android).
  ///
  /// Get [paymentToken] (`paymentMethodData.tokenizationData.token`) and
  /// [cardBrand] (`paymentMethodData.info.cardNetwork`) from Google Pay, e.g.
  /// with the `pay` package. `MASTERCARD` is mapped to HyperPay's `MASTER`.
  /// [brand] is `'GOOGLEPAY'` (default) or `'GOOGLEPAYTKN'`.
  static Future<PaymentResult> payGooglePay({
    required String checkoutId,
    required String paymentToken,
    required String cardBrand,
    String? brand,
    String? shopperResultUrl,
  }) {
    return HyperpaySdkMethodChannel.payGooglePay(
      checkoutId: checkoutId,
      paymentToken: paymentToken,
      cardBrand: cardBrand,
      brand: brand,
      shopperResultUrl: shopperResultUrl,
    );
  }

  /// Submit a Samsung Pay payment (Android). Get [paymentCredential] from the
  /// Samsung Pay SDK in your app (Samsung Pay needs its own SDK jar and a
  /// Samsung Pay service; see the README).
  static Future<PaymentResult> paySamsungPay({
    required String checkoutId,
    required String paymentCredential,
    String? brand,
    String? shopperResultUrl,
  }) {
    return HyperpaySdkMethodChannel.paySamsungPay(
      checkoutId: checkoutId,
      paymentCredential: paymentCredential,
      brand: brand,
      shopperResultUrl: shopperResultUrl,
    );
  }

  /// Klarna Payments, native flow, step 1: create the Klarna session.
  ///
  /// Use the returned [KlarnaSession.clientToken] and
  /// [KlarnaSession.paymentCategory] to show Klarna's view with Klarna's
  /// Mobile SDK. The simpler redirect flow needs none of this: pass a
  /// [KlarnaBrand] to [checkoutReadyUI] or [payWithBrand].
  static Future<KlarnaSession> klarnaCreateSession({
    required String checkoutId,
    required String brand,
    required String shopperResultUrl,
  }) {
    return HyperpaySdkMethodChannel.klarnaCreateSession(
      checkoutId: checkoutId,
      brand: brand,
      shopperResultUrl: shopperResultUrl,
    );
  }

  /// Klarna Payments, native flow, step 2 (Pay button): submit the payment
  /// with the session's [initialTransactionId]. Authorize the returned
  /// session with Klarna's SDK, then call its `callbackUrl` (success,
  /// `{{authorization_token}}` replaced) or `failureCallbackUrl`, and query
  /// the payment status from your server.
  static Future<KlarnaSession> klarnaSubmitPayment({
    required String checkoutId,
    required String brand,
    required String initialTransactionId,
    required String shopperResultUrl,
  }) {
    return HyperpaySdkMethodChannel.klarnaSubmitPayment(
      checkoutId: checkoutId,
      brand: brand,
      initialTransactionId: initialTransactionId,
      shopperResultUrl: shopperResultUrl,
    );
  }

  /// Validate card fields with the native SDK's validators (for your own
  /// card form). Only the fields you pass are checked.
  static Future<CardValidationResult> validateCard({
    String? number,
    String? holder,
    String? expiryMonth,
    String? expiryYear,
    String? cvv,
    String? brand,
    bool luhnCheck = true,
  }) {
    return HyperpaySdkMethodChannel.validateCard(
      number: number,
      holder: holder,
      expiryMonth: expiryMonth,
      expiryYear: expiryYear,
      cvv: cvv,
      brand: brand,
      luhnCheck: luhnCheck,
    );
  }

  /// Submit a payment via Apple Pay (iOS only).
  ///
  /// - [checkoutId]: The checkout ID obtained from your server.
  /// - [merchantId]: Your Apple Pay merchant identifier.
  /// - [countryCode]: ISO 3166-1 alpha-2 country code.
  /// - [currencyCode]: ISO 4217 currency code.
  /// - [amount]: Payment amount.
  /// - [companyName]: Company name displayed on the Apple Pay sheet.
  /// - [summaryItems], [supportedNetworks], [requiredBillingContactFields],
  ///   [requiredShippingContactFields], [submitContacts], [paymentBrand]: see
  ///   [ApplePayConfig].
  ///
  /// Returns a [PaymentResult] with the transaction outcome.
  static Future<PaymentResult> payApplePay({
    required String checkoutId,
    required String merchantId,
    required String countryCode,
    required String currencyCode,
    required double amount,
    required String companyName,
    required String shopperResultUrl,
    List<ApplePaySummaryItem>? summaryItems,
    List<String>? supportedNetworks,
    Set<ApplePayContactField>? requiredBillingContactFields,
    Set<ApplePayContactField>? requiredShippingContactFields,
    bool submitContacts = false,
    String? paymentBrand,
  }) {
    return HyperpaySdkMethodChannel.payApplePay(
      checkoutId: checkoutId,
      merchantId: merchantId,
      countryCode: countryCode,
      currencyCode: currencyCode,
      amount: amount,
      companyName: companyName,
      shopperResultUrl: shopperResultUrl,
      config: ApplePayConfig(
        merchantId: merchantId,
        countryCode: countryCode,
        currencyCode: currencyCode,
        amount: amount,
        companyName: companyName,
        summaryItems: summaryItems,
        supportedNetworks: supportedNetworks,
        requiredBillingContactFields: requiredBillingContactFields,
        requiredShippingContactFields: requiredShippingContactFields,
        submitContacts: submitContacts,
        paymentBrand: paymentBrand,
      ),
    );
  }

  /// Submit a payment via Apple Pay with a deferred checkout.
  ///
  /// Unlike [payApplePay], the HyperPay checkout is NOT created up front. The
  /// Apple Pay sheet is presented immediately and, once the user authorises,
  /// the detected card network (`"Visa"`, `"MasterCard"`, `"Mada"`, …) is passed
  /// to [resolveCheckout]. Your callback creates a checkout on your server
  /// tailored to that network (e.g. PA for Visa/MC, DB for MADA) and returns
  /// the resulting `checkoutId`. The SDK then submits the Apple Pay token
  /// against that checkout.
  ///
  /// Apple gives ~30 seconds between authorisation and result, so the server
  /// call inside [resolveCheckout] must comfortably fit that window.
  ///
  /// - [resolveCheckout]: Async callback that maps the detected network to a
  ///   server-issued checkoutId. Throw to abort the payment.
  /// - [merchantId]: Your Apple Pay merchant identifier.
  /// - [countryCode]: ISO 3166-1 alpha-2 country code.
  /// - [currencyCode]: ISO 4217 currency code.
  /// - [amount]: Payment amount.
  /// - [companyName]: Company name displayed on the Apple Pay sheet.
  /// - [shopperResultUrl]: URL scheme for async payment callbacks.
  /// - The remaining optional parameters are as in [payApplePay].
  ///
  /// Returns a [PaymentResult] with the transaction outcome.
  static Future<PaymentResult> payApplePayDynamic({
    required Future<String> Function(String network) resolveCheckout,
    required String merchantId,
    required String countryCode,
    required String currencyCode,
    required double amount,
    required String companyName,
    required String shopperResultUrl,
    List<ApplePaySummaryItem>? summaryItems,
    List<String>? supportedNetworks,
    Set<ApplePayContactField>? requiredBillingContactFields,
    Set<ApplePayContactField>? requiredShippingContactFields,
    bool submitContacts = false,
    String? paymentBrand,
  }) {
    return HyperpaySdkMethodChannel.payApplePayDynamic(
      resolveCheckout: resolveCheckout,
      merchantId: merchantId,
      countryCode: countryCode,
      currencyCode: currencyCode,
      amount: amount,
      companyName: companyName,
      shopperResultUrl: shopperResultUrl,
      config: ApplePayConfig(
        merchantId: merchantId,
        countryCode: countryCode,
        currencyCode: currencyCode,
        amount: amount,
        companyName: companyName,
        summaryItems: summaryItems,
        supportedNetworks: supportedNetworks,
        requiredBillingContactFields: requiredBillingContactFields,
        requiredShippingContactFields: requiredShippingContactFields,
        submitContacts: submitContacts,
        paymentBrand: paymentBrand,
      ),
    );
  }

  /// Whether this device can pay with Apple Pay (iOS). With [networks]
  /// (`PKPaymentNetwork` raw values), also checks that the shopper has a card
  /// of one of those networks in Wallet. Always `false` on Android.
  static Future<bool> isApplePayAvailable({List<String>? networks}) {
    return HyperpaySdkMethodChannel.isApplePayAvailable(networks: networks);
  }

  /// Look up brand/type info for a card BIN via HyperPay's BIN service.
  ///
  /// Use this on the add-card screen as soon as the user has typed the first
  /// 6 digits — the result is authoritative (same database HyperPay uses on
  /// its backend) and lets you route MADA cards through the DB flow instead
  /// of being declined on PA. Don't call it on every keystroke.
  ///
  /// - [checkoutId]: A valid checkout ID. The BIN endpoint is keyed on a
  ///   checkout, so this must already have been created on your server. A
  ///   `0.00` setup checkout is fine.
  /// - [bin]: First 6+ digits of the card number.
  ///
  /// Returns a [HyperpayBinInfo] with `brands` (e.g. `["MADA"]`), `binType`,
  /// and `type`. Returns an empty result if the BIN is unknown.
  static Future<HyperpayBinInfo> requestBinInfo({
    required String checkoutId,
    required String bin,
  }) {
    return HyperpaySdkMethodChannel.requestBinInfo(
      checkoutId: checkoutId,
      bin: bin,
    );
  }

  /// Get checkout details: amount, currency, resource path and the stored
  /// payment methods (tokens) attached to the checkout.
  static Future<CheckoutInfo> getCheckoutInfo({required String checkoutId}) {
    return HyperpaySdkMethodChannel.getCheckoutInfo(checkoutId: checkoutId);
  }

  /// Get the payment status for a completed checkout.
  ///
  /// - [checkoutId]: The checkout ID to check.
  /// - [resourcePath]: Optional resource path from a previous [PaymentResult].
  ///
  /// Returns a [CheckoutInfo] with the payment status.
  ///
  /// **Note:** For production, you should verify payment status on your
  /// backend server using the HyperPay server-to-server API.
  static Future<CheckoutInfo> getPaymentStatus({
    required String checkoutId,
    String? resourcePath,
  }) {
    return HyperpaySdkMethodChannel.getPaymentStatus(
      checkoutId: checkoutId,
      resourcePath: resourcePath,
    );
  }

  /// 3DS SDK security warnings for this device (EMVCo `SW01`–`SW05`: e.g.
  /// jailbroken / rooted device, emulator, debugger attached, unsupported OS).
  ///
  /// The 3DS SDK starts with the first 3-D Secure transaction, not with
  /// [setup]. Before that this throws a `PlatformException` with code
  /// `THREE_DS_WARNINGS_ERROR` (iOS: "Service is not initialized").
  static Future<List<ThreeDSWarning>> getThreeDSWarnings() {
    return HyperpaySdkMethodChannel.getThreeDSWarnings();
  }
}
