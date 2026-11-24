/// A stored payment method (token / registration) attached to a checkout.
class StoredToken {
  /// The token (registration ID). Pay with it via [HyperpaySdk.payWithToken].
  final String tokenId;

  /// Payment brand, e.g. `VISA`, `MADA`, `DIRECTDEBIT_SEPA`, `PAYPAL`.
  final String paymentBrand;

  /// Card details, for card tokens.
  final String? cardHolder;
  final String? cardLast4Digits;
  final String? cardExpiryMonth;
  final String? cardExpiryYear;

  /// Bank account details, for bank-account tokens.
  final String? bankAccountHolder;
  final String? iban;

  /// Virtual account ID / holder, for virtual-account tokens (e.g. PayPal).
  final String? virtualAccountId;
  final String? virtualAccountHolder;

  const StoredToken({
    required this.tokenId,
    required this.paymentBrand,
    this.cardHolder,
    this.cardLast4Digits,
    this.cardExpiryMonth,
    this.cardExpiryYear,
    this.bankAccountHolder,
    this.iban,
    this.virtualAccountId,
    this.virtualAccountHolder,
  });

  bool get isCard => cardLast4Digits != null;

  factory StoredToken.fromMap(Map<String, dynamic> map) => StoredToken(
    tokenId: map['tokenId']?.toString() ?? '',
    paymentBrand: map['paymentBrand']?.toString() ?? '',
    cardHolder: map['cardHolder'] as String?,
    cardLast4Digits: map['cardLast4Digits'] as String?,
    cardExpiryMonth: map['cardExpiryMonth'] as String?,
    cardExpiryYear: map['cardExpiryYear'] as String?,
    bankAccountHolder: map['bankAccountHolder'] as String?,
    iban: map['iban'] as String?,
    virtualAccountId: map['virtualAccountId'] as String?,
    virtualAccountHolder: map['virtualAccountHolder'] as String?,
  );

  Map<String, dynamic> toMap() => {
    'tokenId': tokenId,
    'paymentBrand': paymentBrand,
    'cardHolder': cardHolder,
    'cardLast4Digits': cardLast4Digits,
    'cardExpiryMonth': cardExpiryMonth,
    'cardExpiryYear': cardExpiryYear,
    'bankAccountHolder': bankAccountHolder,
    'iban': iban,
    'virtualAccountId': virtualAccountId,
    'virtualAccountHolder': virtualAccountHolder,
  };

  @override
  String toString() =>
      'StoredToken($paymentBrand ${cardLast4Digits ?? iban ?? virtualAccountId})';
}

/// Checkout details from HyperPay (`requestCheckoutInfo`).
class CheckoutInfo {
  /// Payment status string, when the native SDK reports one.
  final String? status;

  /// The payment brand used (e.g. `"VISA"`, `"MASTER"`, `"MADA"`).
  final String? paymentBrand;

  /// Checkout amount.
  final double? amount;

  /// ISO 4217 currency code.
  final String? currencyCode;

  /// Resource path to query the payment status from your server.
  final String? resourcePath;

  /// Stored payment methods sent with the checkout (`registrations[n].id`).
  final List<StoredToken> tokens;

  /// Brands enabled for the checkout (Android only).
  final List<String> brands;

  /// Raw response data from the SDK for additional inspection.
  final Map<String, dynamic>? rawResponse;

  const CheckoutInfo({
    this.status,
    this.paymentBrand,
    this.amount,
    this.currencyCode,
    this.resourcePath,
    this.tokens = const [],
    this.brands = const [],
    this.rawResponse,
  });

  factory CheckoutInfo.fromMap(Map<String, dynamic> map) {
    final rawTokens = map['tokens'];
    final rawBrands = map['brands'];
    return CheckoutInfo(
      status: map['status'] as String?,
      paymentBrand: map['paymentBrand'] as String?,
      amount: (map['amount'] as num?)?.toDouble(),
      currencyCode: map['currencyCode'] as String?,
      resourcePath: map['resourcePath'] as String?,
      tokens: rawTokens is List
          ? rawTokens
                .whereType<Map>()
                .map((t) => StoredToken.fromMap(Map<String, dynamic>.from(t)))
                .toList(growable: false)
          : const [],
      brands: rawBrands is List
          ? rawBrands.map((b) => b.toString()).toList(growable: false)
          : const [],
      rawResponse: map['rawResponse'] != null
          ? Map<String, dynamic>.from(map['rawResponse'] as Map)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'status': status,
      'paymentBrand': paymentBrand,
      'amount': amount,
      'currencyCode': currencyCode,
      'resourcePath': resourcePath,
      'tokens': tokens.map((t) => t.toMap()).toList(),
      'brands': brands,
      'rawResponse': rawResponse,
    };
  }

  @override
  String toString() {
    return 'CheckoutInfo(status: $status, paymentBrand: $paymentBrand, '
        'amount: $amount $currencyCode, tokens: ${tokens.length})';
  }
}
