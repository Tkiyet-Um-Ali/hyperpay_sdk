import 'checkout_theme.dart';

/// Whether the Ready-UI checkout saves (tokenizes) the shopper's payment
/// details.
enum StorePaymentDetailsMode {
  /// Never store payment details.
  never,

  /// Show a "save payment details" switch and let the shopper decide.
  prompt,

  /// Always store payment details.
  always,
}

/// When the Ready-UI card form asks for the CVV.
enum SkipCvvMode {
  /// Always ask for the CVV (default).
  never,

  /// Skip the CVV for stored (tokenized) cards only.
  forStoredCards,

  /// Never ask for the CVV (the field is hidden).
  always,
}

/// How the Ready-UI checkout detects the card brand from the card number.
enum BrandDetectionType {
  /// Regular expressions. Fast; the SDK default.
  regex,

  /// HyperPay's BIN list. More precise; falls back to regex. Looked up after
  /// 6 digits.
  binList,

  /// Like [binList], and the card number hint also changes to
  /// "Debit Card Number" / "Credit Card Number".
  binListAndType,
}

/// How detected card brands are presented in the Ready-UI card form.
enum BrandDetectionAppearanceStyle {
  /// Detected brands are shown automatically (SDK default).
  active,

  /// Hidden until the shopper taps the card icon; the top brand is preselected.
  inactive,

  /// No brand selection; the brand is chosen by priority.
  none,
}

/// Device authentication (Face ID / Touch ID / passcode, or Android screen
/// lock / fingerprint) required before paying.
enum SecurityPolicyMode {
  /// No device authentication.
  notRequired,

  /// Require device authentication when the device has it set up.
  requiredIfAvailable,

  /// Always require device authentication; the payment method is unavailable
  /// on devices without a screen lock.
  required,
}

/// Apple Pay button style on the Ready-UI payment method screen (iOS).
/// Mirrors `PKPaymentButtonType`.
enum ApplePayButtonType {
  plain,
  buy,
  setUp,
  inStore,
  donate,
  checkout,
  book,
  subscribe,
  reload,
  addMoney,
  topUp,
  order,
  rent,
  support,
  contribute,
  tip,
  continueButton,
}

/// Shopper data the Ready-UI collects from Apple Pay and submits to HyperPay
/// (iOS, `OPPCheckoutSettings.applePayContactTypes`).
enum ApplePayContactType {
  /// Billing address.
  billingAddress,

  /// Customer name, surname, phone and email.
  customer,
}

/// Shopper data the Ready-UI collects from Google Pay and submits to HyperPay
/// (Android, `CheckoutSettings.setGooglePaySubmit`).
enum GooglePaySubmitType {
  /// Billing address.
  billing,

  /// Customer name, surname, phone and email.
  customer,
}

/// Billing address to prefill in the Ready-UI card form, and which of its
/// fields the shopper must fill in.
class BillingAddress {
  final String? country;
  final String? state;
  final String? city;
  final String? postCode;
  final String? street1;
  final String? street2;

  final bool countryRequired;
  final bool stateRequired;
  final bool cityRequired;
  final bool postCodeRequired;
  final bool street1Required;
  final bool street2Required;

  const BillingAddress({
    this.country,
    this.state,
    this.city,
    this.postCode,
    this.street1,
    this.street2,
    this.countryRequired = false,
    this.stateRequired = false,
    this.cityRequired = false,
    this.postCodeRequired = false,
    this.street1Required = false,
    this.street2Required = false,
  });

  Map<String, dynamic> toMap() => {
    if (country != null) 'country': country,
    if (state != null) 'state': state,
    if (city != null) 'city': city,
    if (postCode != null) 'postCode': postCode,
    if (street1 != null) 'street1': street1,
    if (street2 != null) 'street2': street2,
    'countryRequired': countryRequired,
    'stateRequired': stateRequired,
    'cityRequired': cityRequired,
    'postCodeRequired': postCodeRequired,
    'street1Required': street1Required,
    'street2Required': street2Required,
  };
}

/// COPYandPAY widget options for a brand rendered inside the mobile SDK
/// (HyperPay documents this for the `ONEY` brand only).
class WpwlOptions {
  /// Widget configuration values, e.g. `{'locale': 'fr-BE'}`.
  final Map<String, Object> configuration;

  /// JavaScript functions by name, e.g. `{'onReady': 'function() {...}'}`.
  final Map<String, String> jsFunctions;

  const WpwlOptions({
    this.configuration = const {},
    this.jsFunctions = const {},
  });

  Map<String, dynamic> toMap() => {
    'configuration': configuration,
    'jsFunctions': jsFunctions,
  };
}

/// Optional settings for [HyperpaySdk.checkoutReadyUI]. Every field is
/// optional; unset fields keep the native SDK defaults.
///
/// Platform notes are given per field. A setting that a platform doesn't
/// support is ignored there.
class CheckoutOptions {
  /// Whether to save the payment details. Defaults to
  /// [StorePaymentDetailsMode.prompt] on both platforms.
  final StorePaymentDetailsMode? storePaymentDetails;

  /// When to ask for the CVV.
  final SkipCvvMode? skipCvv;

  /// Show the card holder field (default `true`).
  final bool? cardHolderVisible;

  /// Custom card holder validation: a regular expression the whole holder
  /// name must match. Replaces the SDK's own holder validation.
  final String? cardHolderPattern;

  /// Show the total amount on the payment method screen and the Pay button.
  final bool? displayTotalAmount;

  /// Show the back button on the payment forms (default `true`).
  final bool? backButtonAvailable;

  /// Offer installments in the card form.
  final bool? installmentEnabled;

  /// Installment counts to offer (SDK default `[1, 3, 5]`).
  final List<int>? installmentOptions;

  /// Billing address to prefill / require.
  final BillingAddress? billingAddress;

  /// How the card brand is detected.
  final BrandDetectionType? brandDetectionType;

  /// Brand order to use when several brands match a card number. Defaults to
  /// the order of the `brands` list.
  final List<String>? brandDetectionPriority;

  /// How detected brands are shown.
  final BrandDetectionAppearanceStyle? brandDetectionAppearanceStyle;

  /// Device authentication before paying with a stored token. HyperPay
  /// recommends protecting tokens.
  final SecurityPolicyMode? tokensSecurityPolicy;

  /// Device authentication per payment brand, e.g.
  /// `{'VISA': SecurityPolicyMode.requiredIfAvailable}`.
  final Map<String, SecurityPolicyMode>? brandSecurityPolicies;

  /// Allow card scanning (camera on iOS, NFC on Android). On iOS camera
  /// scanning also needs `NSCameraUsageDescription` in Info.plist.
  final bool? cardScanningEnabled;

  /// iOS: custom brand logos, brand → Flutter asset path (e.g.
  /// `{'PRIVATE_LABEL': 'assets/logo.png'}`).
  final Map<String, String>? customLogoAssets;

  /// Android: custom brand logos, brand → drawable resource name in the app
  /// (e.g. `{'PRIVATE_LABEL': 'logo'}` for `res/drawable/logo.png`).
  final Map<String, String>? androidCustomLogoDrawables;

  /// iOS: full checkout theme (colors, fonts, style). On Android, style the
  /// checkout with [androidThemeResource] instead.
  final CheckoutTheme? theme;

  /// Android: name of a style resource in the app that extends
  /// `Theme.Checkout` (or `Theme.Checkout.Light` / `.Dark`), e.g.
  /// `'NewCheckoutTheme'`.
  final String? androidThemeResource;

  /// iOS: Apple Pay button type on the payment method screen.
  final ApplePayButtonType? applePayButtonType;

  /// iOS: shopper data to take from Apple Pay and send to HyperPay.
  final Set<ApplePayContactType>? applePayContactTypes;

  /// Android: shopper data to take from Google Pay and send to HyperPay.
  final Set<GooglePaySubmitType>? googlePaySubmitTypes;

  /// Ask STC Pay shoppers for a QR code instead of a phone number.
  final bool? stcPayQrCodeRequired;

  /// Turn off the card expiry date validation.
  final bool? cardExpiryDateValidationDisabled;

  /// Require the IBAN for direct debit.
  final bool? ibanRequired;

  /// Android: block screenshots / screen recording of the checkout
  /// (`FLAG_SECURE`).
  final bool? windowSecurityEnabled;

  /// Show the birth date field where a brand supports it (iOS: RatePay).
  final bool? showBirthDate;

  /// Show stored tokens in the order of the `brands` list.
  final bool? paymentBrandsOrderUsedForTokens;

  /// COPYandPAY widget options per brand (HyperPay documents `ONEY`).
  final Map<String, WpwlOptions>? wpwlOptions;

  const CheckoutOptions({
    this.storePaymentDetails,
    this.skipCvv,
    this.cardHolderVisible,
    this.cardHolderPattern,
    this.displayTotalAmount,
    this.backButtonAvailable,
    this.installmentEnabled,
    this.installmentOptions,
    this.billingAddress,
    this.brandDetectionType,
    this.brandDetectionPriority,
    this.brandDetectionAppearanceStyle,
    this.tokensSecurityPolicy,
    this.brandSecurityPolicies,
    this.cardScanningEnabled,
    this.customLogoAssets,
    this.androidCustomLogoDrawables,
    this.theme,
    this.androidThemeResource,
    this.applePayButtonType,
    this.applePayContactTypes,
    this.googlePaySubmitTypes,
    this.stcPayQrCodeRequired,
    this.cardExpiryDateValidationDisabled,
    this.ibanRequired,
    this.windowSecurityEnabled,
    this.showBirthDate,
    this.paymentBrandsOrderUsedForTokens,
    this.wpwlOptions,
  });

  Map<String, dynamic> toMap() => {
    if (storePaymentDetails != null)
      'storePaymentDetails': storePaymentDetails!.name,
    if (skipCvv != null) 'skipCvv': skipCvv!.name,
    if (cardHolderVisible != null) 'cardHolderVisible': cardHolderVisible,
    if (cardHolderPattern != null) 'cardHolderPattern': cardHolderPattern,
    if (displayTotalAmount != null) 'displayTotalAmount': displayTotalAmount,
    if (backButtonAvailable != null) 'backButtonAvailable': backButtonAvailable,
    if (installmentEnabled != null) 'installmentEnabled': installmentEnabled,
    if (installmentOptions != null) 'installmentOptions': installmentOptions,
    if (billingAddress != null) 'billingAddress': billingAddress!.toMap(),
    if (brandDetectionType != null)
      'brandDetectionType': brandDetectionType!.name,
    if (brandDetectionPriority != null)
      'brandDetectionPriority': brandDetectionPriority,
    if (brandDetectionAppearanceStyle != null)
      'brandDetectionAppearanceStyle': brandDetectionAppearanceStyle!.name,
    if (tokensSecurityPolicy != null)
      'tokensSecurityPolicy': tokensSecurityPolicy!.name,
    if (brandSecurityPolicies != null)
      'brandSecurityPolicies': brandSecurityPolicies!.map(
        (brand, mode) => MapEntry(brand, mode.name),
      ),
    if (cardScanningEnabled != null) 'cardScanningEnabled': cardScanningEnabled,
    if (customLogoAssets != null) 'customLogoAssets': customLogoAssets,
    if (androidCustomLogoDrawables != null)
      'androidCustomLogoDrawables': androidCustomLogoDrawables,
    if (theme != null) 'theme': theme!.toMap(),
    if (androidThemeResource != null)
      'androidThemeResource': androidThemeResource,
    if (applePayButtonType != null)
      'applePayButtonType': applePayButtonType!.name,
    if (applePayContactTypes != null)
      'applePayContactTypes': applePayContactTypes!.map((t) => t.name).toList(),
    if (googlePaySubmitTypes != null)
      'googlePaySubmitTypes': googlePaySubmitTypes!.map((t) => t.name).toList(),
    if (stcPayQrCodeRequired != null)
      'stcPayQrCodeRequired': stcPayQrCodeRequired,
    if (cardExpiryDateValidationDisabled != null)
      'cardExpiryDateValidationDisabled': cardExpiryDateValidationDisabled,
    if (ibanRequired != null) 'ibanRequired': ibanRequired,
    if (windowSecurityEnabled != null)
      'windowSecurityEnabled': windowSecurityEnabled,
    if (showBirthDate != null) 'showBirthDate': showBirthDate,
    if (paymentBrandsOrderUsedForTokens != null)
      'paymentBrandsOrderUsedForTokens': paymentBrandsOrderUsedForTokens,
    if (wpwlOptions != null)
      'wpwlOptions': wpwlOptions!.map((brand, o) => MapEntry(brand, o.toMap())),
  };
}
