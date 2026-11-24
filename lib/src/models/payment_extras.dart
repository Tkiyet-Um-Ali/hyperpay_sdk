/// Details of a Ready-UI payment about to be submitted, passed to the
/// `onBeforeSubmit` callback of [HyperpaySdk.checkoutReadyUI].
class BeforeSubmitInfo {
  /// The checkout ID the payment will be submitted against.
  final String checkoutId;

  /// The brand the shopper chose, e.g. `VISA`, `MADA`, `APPLEPAY`.
  final String paymentBrand;

  /// The Visa Installments plan the shopper picked, if any.
  final String? selectedInstallmentPlan;

  const BeforeSubmitInfo({
    required this.checkoutId,
    required this.paymentBrand,
    this.selectedInstallmentPlan,
  });

  factory BeforeSubmitInfo.fromMap(Map<String, dynamic> map) =>
      BeforeSubmitInfo(
        checkoutId: map['checkoutId']?.toString() ?? '',
        paymentBrand: map['paymentBrand']?.toString() ?? '',
        selectedInstallmentPlan: map['selectedInstallmentPlan'] as String?,
      );
}

/// What to do with a Ready-UI payment, returned from `onBeforeSubmit`.
class BeforeSubmitDecision {
  /// Submit against this checkout ID instead (e.g. a checkout you re-created
  /// server-side for the chosen brand or a changed amount). `null` keeps the
  /// current one.
  final String? checkoutId;

  /// Abort the payment. The checkout closes and the result is
  /// `PaymentResult(isCanceled: true)`.
  final bool abort;

  const BeforeSubmitDecision.proceed({this.checkoutId}) : abort = false;

  const BeforeSubmitDecision.abort() : checkoutId = null, abort = true;

  Map<String, dynamic> toMap() => {
    if (checkoutId != null) 'checkoutId': checkoutId,
    'abort': abort,
  };
}

/// How STC Pay verifies the shopper.
enum StcPayVerificationOption {
  /// The shopper enters their mobile number and confirms with an OTP.
  mobilePhone,

  /// The shopper scans a QR code with the STC Pay app.
  qrCode,
}

/// Result of [HyperpaySdk.validateCard], using the native SDK's validators.
/// A field you didn't pass is `null`.
class CardValidationResult {
  final bool? numberValid;
  final bool? holderValid;
  final bool? expiryMonthValid;
  final bool? expiryYearValid;

  /// `true` when the expiry date is in the past.
  final bool? expired;
  final bool? cvvValid;

  const CardValidationResult({
    this.numberValid,
    this.holderValid,
    this.expiryMonthValid,
    this.expiryYearValid,
    this.expired,
    this.cvvValid,
  });

  /// `true` when every checked field is valid and the card isn't expired.
  bool get isValid =>
      numberValid != false &&
      holderValid != false &&
      expiryMonthValid != false &&
      expiryYearValid != false &&
      expired != true &&
      cvvValid != false;

  factory CardValidationResult.fromMap(Map<String, dynamic> map) =>
      CardValidationResult(
        numberValid: map['numberValid'] as bool?,
        holderValid: map['holderValid'] as bool?,
        expiryMonthValid: map['expiryMonthValid'] as bool?,
        expiryYearValid: map['expiryYearValid'] as bool?,
        expired: map['expired'] as bool?,
        cvvValid: map['cvvValid'] as bool?,
      );

  @override
  String toString() =>
      'CardValidationResult(number: $numberValid, '
      'holder: $holderValid, month: $expiryMonthValid, year: $expiryYearValid, '
      'expired: $expired, cvv: $cvvValid)';
}

/// Klarna session data from HyperPay, for the native Klarna Payments flow.
///
/// Render Klarna with Klarna's own Mobile SDK using [clientToken], then call
/// [callbackUrl] (with `{{authorization_token}}` replaced by Klarna's
/// authorization token) or [failureCallbackUrl] from your app or server.
class KlarnaSession {
  final String? clientToken;
  final String? initialTransactionId;
  final String? callbackUrl;
  final String? failureCallbackUrl;

  /// Klarna payment category for the Klarna SDK, derived from the brand:
  /// `pay_later`, `pay_over_time`, `pay_now` or `klarna`.
  final String? paymentCategory;

  const KlarnaSession({
    this.clientToken,
    this.initialTransactionId,
    this.callbackUrl,
    this.failureCallbackUrl,
    this.paymentCategory,
  });

  factory KlarnaSession.fromMap(Map<String, dynamic> map) => KlarnaSession(
    clientToken: map['clientToken'] as String?,
    initialTransactionId: map['initialTransactionId'] as String?,
    callbackUrl: map['callbackUrl'] as String?,
    failureCallbackUrl: map['failureCallbackUrl'] as String?,
    paymentCategory: map['paymentCategory'] as String?,
  );

  @override
  String toString() =>
      'KlarnaSession(initialTransactionId: $initialTransactionId, '
      'category: $paymentCategory)';
}

/// Klarna Payments brands.
class KlarnaBrand {
  KlarnaBrand._();
  static const payLater = 'KLARNA_PAYMENTS_PAYLATER';
  static const sliceIt = 'KLARNA_PAYMENTS_SLICEIT';
  static const payNow = 'KLARNA_PAYMENTS_PAYNOW';
  static const one = 'KLARNA_PAYMENTS_ONE';
}
