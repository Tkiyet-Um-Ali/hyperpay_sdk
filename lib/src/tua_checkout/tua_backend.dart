import 'dart:async';

import 'tua_models.dart';

/// The Tua backend calls the checkout needs. Implement it with your app's
/// authenticated API client, or use [TuaRestBackend] and give it one request
/// function.
///
/// Every method throws [TuaBackendException] for an error answer
/// ([TuaOpenCheckoutsException] for `payments.too_many_open_checkouts`).
abstract class TuaCheckoutBackend {
  /// `POST /v1/donations/checkout` with the donation body and this
  /// `Idempotency-Key`.
  Future<TuaCheckout> createCheckout({required String idempotencyKey});

  /// `GET /v1/donations/payments/{paymentId}` (names in [locale], `en`/`ar`).
  Future<TuaPayment> getPayment(String paymentId, {String? locale});

  /// `POST /v1/donations/payments/{paymentId}/retry`: a new checkout for a
  /// `failed` payment.
  Future<TuaCheckout> retryPayment(String paymentId);

  /// `POST /v1/donations/payments/{paymentId}/cancel`.
  Future<void> cancelPayment(String paymentId);
}

/// A decoded HTTP answer for [TuaRestBackend].
class TuaHttpResponse {
  final int statusCode;

  /// The decoded JSON body (`null` when empty).
  final Object? body;

  const TuaHttpResponse(this.statusCode, this.body);
}

/// Sends one request to the Tua backend. [path] starts with `/v1/...`; the
/// function adds the base URL and the donor's `Authorization`, refreshes the
/// token if needed, sends [body] as JSON with [headers], and returns the
/// status and decoded JSON. It should not throw for HTTP error statuses.
typedef TuaSend =
    Future<TuaHttpResponse> Function(
      String method,
      String path, {
      Map<String, dynamic>? body,
      Map<String, String>? headers,
    });

/// [TuaCheckoutBackend] over the Tua REST API, using your app's own request
/// function for auth and networking.
///
/// ```dart
/// final backend = TuaRestBackend(
///   send: (method, path, {body, headers}) async {
///     final r = await myApi.request(method, path, json: body, headers: headers);
///     return TuaHttpResponse(r.statusCode, r.json);
///   },
///   checkoutBody: () => cart.toCheckoutBody(), // programSlug, items, …
/// );
/// ```
class TuaRestBackend implements TuaCheckoutBackend {
  TuaRestBackend({required this.send, required this.checkoutBody});

  final TuaSend send;

  /// The body of `POST /v1/donations/checkout` for the donation being paid
  /// (`programSlug`, `programVersion`, `items`, `currency`, `billing`, …).
  /// `client: mobile` is added for you.
  final FutureOr<Map<String, dynamic>> Function() checkoutBody;

  @override
  Future<TuaCheckout> createCheckout({required String idempotencyKey}) async {
    final body = {...await checkoutBody(), 'client': 'mobile'};
    final response = await send(
      'POST',
      '/v1/donations/checkout',
      body: body,
      headers: {'Idempotency-Key': idempotencyKey},
    );
    return _checkout(response);
  }

  @override
  Future<TuaPayment> getPayment(String paymentId, {String? locale}) async {
    final query = locale == null ? '' : '?locale=$locale';
    final response = await send(
      'GET',
      '/v1/donations/payments/$paymentId$query',
    );
    return TuaPayment.fromJson(_json(response));
  }

  @override
  Future<TuaCheckout> retryPayment(String paymentId) async {
    final response = await send(
      'POST',
      '/v1/donations/payments/$paymentId/retry',
    );
    return _checkout(response);
  }

  @override
  Future<void> cancelPayment(String paymentId) async {
    final response = await send(
      'POST',
      '/v1/donations/payments/$paymentId/cancel',
    );
    _json(response);
  }

  TuaCheckout _checkout(TuaHttpResponse response) {
    final checkout = TuaCheckout.fromPaymentJson(_json(response));
    if (checkout == null) {
      throw TuaBackendException(
        response.statusCode,
        'The response has no hyperpay.checkoutId',
      );
    }
    return checkout;
  }

  /// The JSON object of a 2xx answer, or the backend's error as an exception.
  static Map<String, dynamic> _json(TuaHttpResponse response) {
    final body = response.body;
    final data = body is Map<String, dynamic>
        ? body
        : body is Map
        ? Map<String, dynamic>.from(body)
        : <String, dynamic>{};
    if (response.statusCode >= 200 && response.statusCode < 300) return data;

    final code = data['code']?.toString();
    final message =
        data['message']?.toString() ?? 'HTTP ${response.statusCode}';
    if (code == 'payments.too_many_open_checkouts') {
      final list = data['openCheckouts'];
      throw TuaOpenCheckoutsException(
        message,
        openCheckouts: list is List
            ? list.whereType<Map>().map(TuaOpenCheckout.fromJson).toList()
            : const [],
        retryAfterSeconds: (data['retryAfterSeconds'] as num?)?.toInt(),
      );
    }
    throw TuaBackendException(response.statusCode, message, code: code);
  }
}
