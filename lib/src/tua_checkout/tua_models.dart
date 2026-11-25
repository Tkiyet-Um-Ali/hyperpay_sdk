import '../models/payment_result.dart';

/// A HyperPay checkout created by the Tua backend (the `hyperpay` block of
/// `POST /v1/donations/checkout`, `GET /v1/donations/payments/{id}` and
/// `POST .../retry`).
class TuaCheckout {
  /// HyperPay checkout ID for the card form.
  final String checkoutId;

  /// Brands the checkout accepts, e.g. `['VISA', 'MASTER']`.
  final List<String> brands;

  /// Separate checkout for American Express (`hyperpay.amex`), when offered.
  final String? amexCheckoutId;

  /// `test` or `live`. Must match `HyperpaySdk.setup(mode:)`.
  final String? mode;

  /// The backend's payment ID. Used to read, retry or cancel the payment.
  final String? paymentId;
  final String? reference;
  final num? amount;
  final String? currency;
  final DateTime? expiresAt;

  const TuaCheckout({
    required this.checkoutId,
    required this.brands,
    this.amexCheckoutId,
    this.mode,
    this.paymentId,
    this.reference,
    this.amount,
    this.currency,
    this.expiresAt,
  });

  /// Reads a payment response that carries a `hyperpay` block. Returns null
  /// when there is none (the payment is no longer open).
  static TuaCheckout? fromPaymentJson(Map<String, dynamic> data) {
    final hyperpay = data['hyperpay'];
    if (hyperpay is! Map) return null;
    final checkoutId = hyperpay['checkoutId'];
    if (checkoutId is! String || checkoutId.isEmpty) return null;
    final brands = hyperpay['brands'];
    final amex = hyperpay['amex'];
    return TuaCheckout(
      checkoutId: checkoutId,
      brands: brands is List
          ? brands.map((b) => b.toString()).toList()
          : brands is String
          ? brands.split(' ').where((b) => b.isNotEmpty).toList()
          : const ['VISA', 'MASTER'],
      amexCheckoutId: amex is Map ? amex['checkoutId'] as String? : null,
      mode: hyperpay['mode'] as String?,
      paymentId: data['paymentId'] as String?,
      reference: data['reference'] as String?,
      amount: data['amount'] as num?,
      currency: data['currency'] as String?,
      expiresAt: DateTime.tryParse(data['expiresAt']?.toString() ?? ''),
    );
  }

  bool get isExpired =>
      expiresAt != null && DateTime.now().toUtc().isAfter(expiresAt!);
}

/// One program line of a payment.
class TuaPaymentLine {
  final String programName;
  final String? optionTitle;
  final int quantity;
  final num unitAmount;
  final num amount;

  const TuaPaymentLine({
    required this.programName,
    this.optionTitle,
    required this.quantity,
    required this.unitAmount,
    required this.amount,
  });

  factory TuaPaymentLine.fromJson(Map map) => TuaPaymentLine(
    programName: map['programName']?.toString() ?? '',
    optionTitle: map['optionTitle']?.toString(),
    quantity: (map['quantity'] as num?)?.toInt() ?? 1,
    unitAmount: map['unitAmount'] as num? ?? 0,
    amount: map['amount'] as num? ?? 0,
  );
}

/// A payment as `GET /v1/donations/payments/{paymentId}` returns it.
class TuaPayment {
  final String paymentId;

  /// `pending` (card form open), `processing`, `succeeded`, `review`,
  /// `failed`, `expired` or `cancelled`.
  final String status;
  final String? reference;
  final num? amount;
  final String? currency;
  final List<TuaPaymentLine> lines;

  /// Why it failed (`failure.message`, written for donors), when `failed`.
  final String? failureMessage;
  final String? failureReason;

  /// Whether `POST .../retry` is allowed.
  final bool retryAllowed;

  /// The checkout to show the card form again, while `pending`.
  final TuaCheckout? checkout;

  const TuaPayment({
    required this.paymentId,
    required this.status,
    this.reference,
    this.amount,
    this.currency,
    this.lines = const [],
    this.failureMessage,
    this.failureReason,
    this.retryAllowed = false,
    this.checkout,
  });

  factory TuaPayment.fromJson(Map<String, dynamic> map) {
    final failure = map['failure'];
    final retry = map['retry'];
    final lines = map['lines'];
    return TuaPayment(
      paymentId: map['paymentId']?.toString() ?? '',
      status: map['status']?.toString() ?? 'unknown',
      reference: map['reference']?.toString(),
      amount: map['amount'] as num?,
      currency: map['currency']?.toString(),
      lines: lines is List
          ? lines.whereType<Map>().map(TuaPaymentLine.fromJson).toList()
          : const [],
      failureMessage: failure is Map ? failure['message']?.toString() : null,
      failureReason: failure is Map ? failure['reason']?.toString() : null,
      retryAllowed: retry is Map && retry['allowed'] == true,
      checkout: TuaCheckout.fromPaymentJson(map),
    );
  }

  bool get isPaid => status == 'succeeded';

  /// Still waiting on HyperPay.
  bool get isOpen => status == 'pending' || status == 'processing';
}

/// An error answer from the Tua backend.
class TuaBackendException implements Exception {
  final int statusCode;

  /// Backend error code, e.g. `payments.idempotency_key_reused`.
  final String? code;

  /// Message from the backend, written for donors when it has one.
  final String message;

  TuaBackendException(this.statusCode, this.message, {this.code});

  @override
  String toString() => 'TuaBackendException($statusCode, $code): $message';
}

/// One of the donor's unpaid checkouts, listed on a
/// `payments.too_many_open_checkouts` 429.
class TuaOpenCheckout {
  final String paymentId;

  /// `pending`, `processing` or `failed`.
  final String status;

  /// Null for a moment while another checkout request is still waiting on
  /// HyperPay.
  final String? checkoutId;
  final DateTime? expiresAt;

  const TuaOpenCheckout({
    required this.paymentId,
    required this.status,
    this.checkoutId,
    this.expiresAt,
  });

  factory TuaOpenCheckout.fromJson(Map map) => TuaOpenCheckout(
    paymentId: map['paymentId'].toString(),
    status: map['status']?.toString() ?? '',
    checkoutId: map['checkoutId'] as String?,
    expiresAt: DateTime.tryParse(map['expiresAt']?.toString() ?? ''),
  );

  /// Can be continued: `pending` is resumed, `failed` is retried.
  bool get isResumable => status == 'pending' || status == 'failed';
}

/// `payments.too_many_open_checkouts`: the donor (3) or their address (5) has
/// too many unpaid checkouts. [openCheckouts] lists the donor's own, oldest
/// first; it is empty when only the address cap was hit.
class TuaOpenCheckoutsException extends TuaBackendException {
  final List<TuaOpenCheckout> openCheckouts;
  final int? retryAfterSeconds;

  TuaOpenCheckoutsException(
    String message, {
    required this.openCheckouts,
    this.retryAfterSeconds,
  }) : super(429, message, code: 'payments.too_many_open_checkouts');
}

/// What the donor chose when they already have unfinished donations.
enum TuaOpenCheckoutChoice {
  /// Continue the oldest unfinished donation.
  resume,

  /// Cancel the unfinished donations and start this one.
  startOver,

  /// Do neither; the screen reports the error.
  dismiss,
}

/// What [TuaCheckoutScreen] returns.
class TuaCheckoutResult {
  /// The SDK's own result. Its `isSuccess` only means the payment was
  /// submitted; use [isPaid].
  final PaymentResult sdkResult;

  /// The payment as the backend reports it after the attempt.
  final TuaPayment? payment;

  const TuaCheckoutResult({required this.sdkResult, this.payment});

  String? get paymentId => payment?.paymentId;
  String? get reference => payment?.reference;

  /// Confirmed by the backend (`status: succeeded`).
  bool get isPaid => payment?.isPaid == true;
}
