import 'dart:math';

import '../models/payment_result.dart';
import 'tua_backend.dart';
import 'tua_models.dart';

/// Asked when the backend refuses a new checkout because the donor already
/// has unfinished ones.
typedef TuaOpenCheckoutsHandler =
    Future<TuaOpenCheckoutChoice> Function(List<TuaOpenCheckout> openCheckouts);

/// The payment flow behind [TuaCheckoutScreen], without any UI:
///
/// - one `Idempotency-Key` per payment attempt, reused when the donor closes
///   the card form and tries again, and replaced after a payment succeeds or
///   fails, or when the backend says the key was used or expired;
/// - a failed payment is retried in place (`.../retry`) instead of opening
///   another checkout;
/// - `payments.too_many_open_checkouts` lets the donor resume an unfinished
///   donation or cancel them and start over;
/// - every SDK result is confirmed with the backend, because the SDK's
///   success only means the payment was submitted.
class TuaCheckoutSession {
  TuaCheckoutSession(
    this.backend, {
    String Function()? newIdempotencyKey,
    this.pollAttempts = 6,
    this.pollInterval = const Duration(seconds: 2),
  }) : _newKey = newIdempotencyKey ?? _randomKey {
    _key = _newKey();
  }

  final TuaCheckoutBackend backend;
  final String Function() _newKey;

  /// How often to re-read a payment that is still `pending`/`processing`
  /// after the SDK returns.
  final int pollAttempts;
  final Duration pollInterval;

  late String _key;
  String? _failedPaymentId;

  /// The checkout the card form pays into.
  TuaCheckout? checkout;

  /// The current `Idempotency-Key`.
  String get idempotencyKey => _key;

  static String _randomKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return 'mobile-${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  }

  void _rotateKey() => _key = _newKey();

  /// Gets the checkout to pay into: retries the last failed payment, or
  /// creates a checkout. [onOpenCheckouts] decides what happens when the
  /// donor has too many unfinished donations; without it the
  /// [TuaOpenCheckoutsException] is thrown.
  Future<TuaCheckout> start({TuaOpenCheckoutsHandler? onOpenCheckouts}) async {
    final failed = _failedPaymentId;
    if (failed != null) {
      _failedPaymentId = null;
      try {
        return checkout = await backend.retryPayment(failed);
      } on TuaBackendException {
        // Retry no longer allowed (expired, under review…): start a new one.
      }
    }
    try {
      return checkout = await _create();
    } on TuaOpenCheckoutsException catch (e) {
      if (onOpenCheckouts == null) rethrow;
      final resumable = e.openCheckouts.where((c) => c.isResumable).toList();
      if (resumable.isEmpty) rethrow;
      switch (await onOpenCheckouts(e.openCheckouts)) {
        case TuaOpenCheckoutChoice.resume:
          for (final open in resumable) {
            final resumed = await _resume(open);
            if (resumed != null) return checkout = resumed;
          }
          rethrow;
        case TuaOpenCheckoutChoice.startOver:
          for (final open in resumable) {
            try {
              await backend.cancelPayment(open.paymentId);
            } on TuaBackendException {
              // Already submitted or finished; it frees its slot by itself.
            }
          }
          return checkout = await _create();
        case TuaOpenCheckoutChoice.dismiss:
          rethrow;
      }
    }
  }

  Future<TuaCheckout> _create() async {
    TuaCheckout created;
    try {
      created = await backend.createCheckout(idempotencyKey: _key);
    } on TuaBackendException catch (e) {
      if (e.code != 'payments.idempotency_key_reused' &&
          e.code != 'payments.idempotency_expired') {
        rethrow;
      }
      _rotateKey();
      created = await backend.createCheckout(idempotencyKey: _key);
    }
    if (created.isExpired) {
      _rotateKey();
      created = await backend.createCheckout(idempotencyKey: _key);
    }
    return created;
  }

  Future<TuaCheckout?> _resume(TuaOpenCheckout open) async {
    try {
      if (open.status == 'pending') {
        return (await backend.getPayment(open.paymentId)).checkout;
      }
      return await backend.retryPayment(open.paymentId);
    } on TuaBackendException {
      return null;
    }
  }

  /// Call with the SDK's result. Confirms it with the backend and prepares
  /// the next attempt. A cancelled card form changes nothing: the next
  /// [start] replays the same checkout.
  Future<TuaCheckoutResult> finish(
    PaymentResult sdkResult, {
    String? locale,
  }) async {
    final paymentId = checkout?.paymentId;
    if (sdkResult.isCanceled || paymentId == null) {
      return TuaCheckoutResult(sdkResult: sdkResult);
    }

    // After a submitted payment HyperPay may need a moment, so poll; after an
    // SDK error one read is enough.
    final attempts = sdkResult.isSuccess ? pollAttempts : 1;
    TuaPayment? payment;
    try {
      for (var i = 0; i < attempts; i++) {
        if (i > 0) await Future<void>.delayed(pollInterval);
        payment = await backend.getPayment(paymentId, locale: locale);
        if (!payment.isOpen) break;
      }
    } on TuaBackendException {
      // Reported as not confirmed below.
    }

    // Still `pending`: nothing was charged (e.g. the SDK rejected the card
    // before submitting), so the next attempt reuses this checkout and key.
    if (payment?.status == 'pending' && !sdkResult.isSuccess) {
      return TuaCheckoutResult(sdkResult: sdkResult, payment: payment);
    }
    _failedPaymentId = payment?.status == 'failed' ? paymentId : null;
    _rotateKey();
    checkout = null;
    return TuaCheckoutResult(sdkResult: sdkResult, payment: payment);
  }
}
