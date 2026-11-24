import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// A HyperPay checkout created by the Tua backend.
class TuaCheckout {
  final String checkoutId;
  final List<String> brands;

  /// `test` or `live` — must match `HyperpaySdk.setup(mode:)`.
  final String? mode;
  final String? paymentId;
  final String? reference;
  final num? amount;
  final String? currency;
  final DateTime? expiresAt;

  const TuaCheckout({
    required this.checkoutId,
    required this.brands,
    this.mode,
    this.paymentId,
    this.reference,
    this.amount,
    this.currency,
    this.expiresAt,
  });

  bool get isExpired =>
      expiresAt != null && DateTime.now().toUtc().isAfter(expiresAt!);
}

class TuaApiException implements Exception {
  final int statusCode;
  final String message;

  /// Backend error code, e.g. `payments.idempotency_key_reused`.
  final String? code;
  TuaApiException(this.statusCode, this.message, {this.code});

  @override
  String toString() => 'TuaApiException($statusCode): $message';
}

/// A payment's state on the backend.
class TuaPaymentOutcome {
  /// `pending`, `processing`, `succeeded`, `review`, `failed`, `expired` or
  /// `cancelled`.
  final String status;

  /// Why it failed (`failure.message`), when `failed`.
  final String? failureMessage;
  final String? failureReason;

  /// Whether `POST .../retry` is allowed (`retry.allowed`).
  final bool retryAllowed;

  const TuaPaymentOutcome({
    required this.status,
    this.failureMessage,
    this.failureReason,
    this.retryAllowed = false,
  });

  factory TuaPaymentOutcome.fromMap(Map<String, dynamic> map) {
    final failure = map['failure'];
    final retry = map['retry'];
    return TuaPaymentOutcome(
      status: map['status']?.toString() ?? 'unknown',
      failureMessage: failure is Map ? failure['message']?.toString() : null,
      failureReason: failure is Map ? failure['reason']?.toString() : null,
      retryAllowed: retry is Map && retry['allowed'] == true,
    );
  }

  bool get isPaid => status == 'succeeded';

  /// Still waiting on HyperPay.
  bool get isOpen => status == 'pending' || status == 'processing';
}

/// One of the donor's unpaid checkouts, listed on a
/// `payments.too_many_open_checkouts` 429.
class TuaOpenCheckout {
  final String paymentId;

  /// `pending` (card form still open), `processing` (submitted) or `failed`
  /// (can be retried).
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

  factory TuaOpenCheckout.fromMap(Map map) => TuaOpenCheckout(
        paymentId: map['paymentId'].toString(),
        status: map['status']?.toString() ?? '',
        checkoutId: map['checkoutId'] as String?,
        expiresAt: DateTime.tryParse(map['expiresAt']?.toString() ?? ''),
      );
}

/// `payments.too_many_open_checkouts`: the donor (3) or their address (5) has
/// too many unpaid checkouts. [openCheckouts] lists the donor's own, oldest
/// first, and is empty when only the address cap was hit.
class TuaOpenCheckoutsException extends TuaApiException {
  final List<TuaOpenCheckout> openCheckouts;
  final int? retryAfterSeconds;

  TuaOpenCheckoutsException(
    String message, {
    required this.openCheckouts,
    this.retryAfterSeconds,
  }) : super(429, message, code: 'payments.too_many_open_checkouts');

  @override
  String toString() => 'TuaApiException(429): $message'
      '${retryAfterSeconds != null ? ' Try again in ${retryAfterSeconds}s.' : ''}';
}

/// Talks to the Tua backend, which creates HyperPay checkouts server-side so
/// the app never holds HyperPay credentials.
///
/// Configuration comes from `.env` (see `.env.example`). Tokens rotated by
/// `/v1/auth/refresh` and the current `Idempotency-Key` are kept in
/// SharedPreferences, because `.env` is a bundled asset and can't be updated.
class TuaApi {
  TuaApi._();

  static const _kAccessToken = 'tua_access_token';
  static const _kRefreshToken = 'tua_refresh_token';
  static const _kIdempotencyKey = 'tua_idempotency_key';
  static const _kFailedPaymentId = 'tua_failed_payment_id';
  // The .env values the stored tokens were derived from. When .env changes
  // (e.g. you paste a fresh token pair), the new .env values win.
  static const _kEnvAccessToken = 'tua_env_access_token';
  static const _kEnvRefreshToken = 'tua_env_refresh_token';

  static String _env(String key) => dotenv.env[key]?.trim() ?? '';

  static String get baseUrl {
    final url = _env('TUA_API_BASE_URL');
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  /// Whether the example should create checkouts through the Tua backend.
  static bool get isConfigured =>
      baseUrl.isNotEmpty &&
      (_env('TUA_ACCESS_TOKEN').isNotEmpty ||
          _env('TUA_REFRESH_TOKEN').isNotEmpty);

  static Future<SharedPreferences> get _prefs =>
      SharedPreferences.getInstance();

  /// Returns the stored token, unless `.env` now holds a different one.
  static Future<String> _token(
      String key, String envKey, String envName) async {
    final prefs = await _prefs;
    final envValue = _env(envName);
    if (prefs.getString(envKey) != envValue) {
      await prefs.setString(envKey, envValue);
      await prefs.setString(key, envValue);
      return envValue;
    }
    return prefs.getString(key) ?? envValue;
  }

  static Future<String> _accessToken() =>
      _token(_kAccessToken, _kEnvAccessToken, 'TUA_ACCESS_TOKEN');

  static Future<String> _refreshToken() =>
      _token(_kRefreshToken, _kEnvRefreshToken, 'TUA_REFRESH_TOKEN');

  /// The `Idempotency-Key` for the next checkout request. It stays the same
  /// until a payment finishes ([rotateIdempotencyKey]), so retries of the same
  /// donation reuse the same checkout.
  static Future<String> idempotencyKey() async {
    final prefs = await _prefs;
    final stored = prefs.getString(_kIdempotencyKey);
    if (stored != null && stored.isNotEmpty) return stored;
    final initial = _env('TUA_IDEMPOTENCY_KEY');
    final key = initial.isNotEmpty ? initial : _newKey();
    await prefs.setString(_kIdempotencyKey, key);
    return key;
  }

  /// Switch to a fresh `Idempotency-Key`. Call after a payment succeeds or
  /// fails, so the next payment creates a new checkout.
  static Future<String> rotateIdempotencyKey() async {
    final key = _newKey();
    await (await _prefs).setString(_kIdempotencyKey, key);
    print('[TuaApi] Idempotency-Key rotated → $key');
    return key;
  }

  static String _newKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return 'mobile-${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  }

  /// Body of `POST /v1/donations/checkout`. Program and profile values come
  /// from `.env`.
  static Map<String, dynamic> _checkoutBody() {
    final quantity = int.tryParse(_env('TUA_QUANTITY')) ?? 1;
    String? orNull(String key) => _env(key).isEmpty ? null : _env(key);
    return {
      'source': 'direct',
      'programSlug': _env('TUA_PROGRAM_SLUG'),
      'programVersion': _env('TUA_PROGRAM_VERSION'),
      'frequency': 'one_time',
      'items': [
        {'optionId': _env('TUA_OPTION_ID'), 'quantity': quantity},
      ],
      'currency': orNull('TUA_CURRENCY') ?? 'JOD',
      'profileId': _env('TUA_PROFILE_ID'),
      'receiptEmail': orNull('TUA_RECEIPT_EMAIL'),
      'billing': {
        'country': orNull('TUA_BILLING_COUNTRY') ?? 'JO',
        'city': orNull('TUA_BILLING_CITY') ?? 'Amman',
        'street': orNull('TUA_BILLING_STREET') ?? '12 Rainbow Street',
        'state': orNull('TUA_BILLING_STATE'),
        'postcode': orNull('TUA_BILLING_POSTCODE'),
      },
      'client': 'mobile',
    };
  }

  /// The checkout most recently handed to the app. Its payment is what
  /// [paymentFinished] marks.
  static TuaCheckout? current;

  /// Creates a donation checkout and returns its HyperPay checkout.
  ///
  /// - A payment that failed earlier is tried again in place
  ///   (`POST /v1/donations/payments/{id}/retry`), so it doesn't hold one of
  ///   the donor's 3 open-checkout slots until it expires.
  /// - Refreshes the access token once on a 401.
  /// - If the `Idempotency-Key` was already used for another request, or its
  ///   checkout expired, the key is rotated and the request repeated once.
  /// - On `payments.too_many_open_checkouts` (429) it resumes or retries one
  ///   of the donor's open checkouts; see [_recoverOpenCheckout].
  static Future<TuaCheckout> createCheckout() async {
    final retried = await _retryFailedPayment();
    if (retried != null) return current = retried;

    TuaCheckout checkout;
    try {
      checkout = await _postCheckoutRotatingKey();
    } on TuaOpenCheckoutsException catch (e) {
      final recovered = await _recoverOpenCheckout(e);
      if (recovered == null) rethrow;
      checkout = recovered;
    }
    return current = checkout;
  }

  static Future<TuaCheckout> _postCheckoutRotatingKey() async {
    TuaCheckout checkout;
    try {
      checkout = await _postCheckout();
    } on TuaApiException catch (e) {
      // The key was spent on a different request body (e.g. another
      // donation, or the same key used from the web), or its checkout is
      // gone. Start a new one.
      if (e.code != 'payments.idempotency_key_reused' &&
          e.code != 'payments.idempotency_expired') {
        rethrow;
      }
      print('[TuaApi] ${e.code}; rotating the Idempotency-Key.');
      await rotateIdempotencyKey();
      checkout = await _postCheckout();
    }
    if (checkout.isExpired) {
      print('[TuaApi] Checkout for this Idempotency-Key expired at '
          '${checkout.expiresAt}; rotating the key.');
      await rotateIdempotencyKey();
      checkout = await _postCheckout();
    }
    return checkout;
  }

  static Future<TuaCheckout> _postCheckout() async {
    final key = await idempotencyKey();
    final response = await _send(
      'POST',
      '/v1/donations/checkout',
      body: _checkoutBody(),
      headers: {'Idempotency-Key': key},
    );
    print('[TuaApi] Checkout ${response.statusCode} (Idempotency-Key: $key)');
    final data = _decodeOrThrow(response);
    return _parseCheckout(data, response);
  }

  /// Call when a payment finished. A failed payment is remembered so the next
  /// [createCheckout] retries it instead of opening another checkout. Success
  /// and failure both rotate the `Idempotency-Key`; a cancelled card form
  /// keeps it, so the next request replays the same checkout.
  static Future<void> paymentFinished({required bool succeeded}) async {
    final paymentId = current?.paymentId;
    final prefs = await _prefs;
    if (succeeded) {
      await prefs.remove(_kFailedPaymentId);
    } else if (paymentId != null) {
      await prefs.setString(_kFailedPaymentId, paymentId);
    }
    current = null;
    await rotateIdempotencyKey();
  }

  static Future<TuaCheckout?> _retryFailedPayment() async {
    final prefs = await _prefs;
    final paymentId = prefs.getString(_kFailedPaymentId);
    if (paymentId == null) return null;
    try {
      final checkout = await retryPayment(paymentId);
      print('[TuaApi] Retrying failed payment $paymentId.');
      return checkout;
    } on TuaApiException catch (e) {
      // 409 payments.retry_not_allowed (expired, under review…) or 404:
      // fall back to a new checkout.
      print('[TuaApi] Can\'t retry payment $paymentId: $e');
      return null;
    } finally {
      await prefs.remove(_kFailedPaymentId);
    }
  }

  /// Handles `payments.too_many_open_checkouts`: tries the donor's open
  /// checkouts oldest first. A `pending` one is resumed (its card form is
  /// still open on HyperPay), a `failed` one is retried, and a `processing`
  /// one is left alone (it was submitted; its result is still coming).
  ///
  /// The example resumes automatically because every checkout it makes is the
  /// same donation. A real app should ask the donor whether to finish the
  /// open donation or [cancelPayment] it and start over.
  static Future<TuaCheckout?> _recoverOpenCheckout(
      TuaOpenCheckoutsException e) async {
    print('[TuaApi] Too many open checkouts: '
        '${e.openCheckouts.map((c) => '${c.paymentId} ${c.status}').join(', ')}');
    for (final open in e.openCheckouts) {
      try {
        switch (open.status) {
          case 'pending':
            final checkout = await resumePayment(open.paymentId);
            if (checkout != null) {
              print('[TuaApi] Resumed open payment ${open.paymentId}.');
              return checkout;
            }
          case 'failed':
            final checkout = await retryPayment(open.paymentId);
            print('[TuaApi] Retrying open payment ${open.paymentId}.');
            return checkout;
        }
      } on TuaApiException catch (err) {
        print('[TuaApi] Couldn\'t recover ${open.paymentId}: $err');
      }
    }
    return null;
  }

  /// Reads a payment's outcome from the backend
  /// (`GET /v1/donations/payments/{paymentId}`), which asks HyperPay. The
  /// SDK's own "success" only means the card form was submitted; a declined
  /// card or a failed 3-D Secure check also ends that way. While the payment
  /// is `pending` or `processing` this polls a few times.
  static Future<TuaPaymentOutcome> paymentOutcome(
    String paymentId, {
    int attempts = 6,
    Duration interval = const Duration(seconds: 2),
  }) async {
    late TuaPaymentOutcome outcome;
    for (var i = 0; i < attempts; i++) {
      if (i > 0) await Future<void>.delayed(interval);
      final response = await _send('GET', '/v1/donations/payments/$paymentId');
      outcome = TuaPaymentOutcome.fromMap(_decodeOrThrow(response));
      print('[TuaApi] Payment $paymentId: ${outcome.status}');
      if (!outcome.isOpen) break;
    }
    return outcome;
  }

  /// `GET /v1/donations/payments/{paymentId}`: the checkout of a payment whose
  /// card form is still open, or `null` once it is no longer `pending` (the
  /// backend only returns `hyperpay` while pending and before `expiresAt`).
  static Future<TuaCheckout?> resumePayment(String paymentId) async {
    final response = await _send('GET', '/v1/donations/payments/$paymentId');
    final data = _decodeOrThrow(response);
    if (data['hyperpay'] is! Map) return null;
    return _parseCheckout(data, response);
  }

  /// `POST /v1/donations/payments/{paymentId}/retry`: a new HyperPay checkout
  /// for a `failed` payment (same items, amount and reference).
  static Future<TuaCheckout> retryPayment(String paymentId) async {
    final response =
        await _send('POST', '/v1/donations/payments/$paymentId/retry');
    final checkout = _parseCheckout(_decodeOrThrow(response), response);
    current = checkout;
    return checkout;
  }

  /// `POST /v1/donations/payments/{paymentId}/cancel`: frees the payment's
  /// open-checkout slot and its goal hold. Throws a 409
  /// `payments.payment_not_cancellable` once the payment was submitted.
  static Future<void> cancelPayment(String paymentId) async {
    final response =
        await _send('POST', '/v1/donations/payments/$paymentId/cancel');
    _decodeOrThrow(response);
  }

  /// Sends an authenticated request, refreshing the access token once on 401.
  static Future<http.Response> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String> headers = const {},
  }) async {
    Future<http.Response> send(String token) {
      final request = http.Request(method, Uri.parse('$baseUrl$path'))
        ..headers.addAll({
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
          ...headers,
        });
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      return request.send().then(http.Response.fromStream);
    }

    var response = await send(await _accessToken());
    if (response.statusCode == 401) {
      print('[TuaApi] Access token rejected; refreshing.');
      response = await send(await refreshTokens());
    }
    return response;
  }

  /// Decodes a 2xx body, or throws the backend's error.
  static Map<String, dynamic> _decodeOrThrow(http.Response response) {
    final data = _decode(response);
    if (response.statusCode >= 200 && response.statusCode < 300) return data;
    final code = data['code']?.toString();
    final message = _errorMessage(data, response);
    if (code == 'payments.too_many_open_checkouts') {
      final list = data['openCheckouts'];
      throw TuaOpenCheckoutsException(
        message,
        openCheckouts: list is List
            ? list.whereType<Map>().map(TuaOpenCheckout.fromMap).toList()
            : const [],
        retryAfterSeconds: (data['retryAfterSeconds'] as num?)?.toInt(),
      );
    }
    throw TuaApiException(response.statusCode, message, code: code);
  }

  /// Reads a payment with a `hyperpay` block (checkout, payment read and
  /// retry responses share it).
  static TuaCheckout _parseCheckout(
      Map<String, dynamic> data, http.Response response) {
    final hyperpay = data['hyperpay'];
    final checkoutId = hyperpay is Map ? hyperpay['checkoutId'] : null;
    if (checkoutId is! String || checkoutId.isEmpty) {
      throw TuaApiException(
          response.statusCode, 'No hyperpay.checkoutId in ${response.body}');
    }
    final brands = hyperpay['brands'];
    return TuaCheckout(
      checkoutId: checkoutId,
      brands: brands is List
          ? brands.map((b) => b.toString()).toList()
          : const ['VISA', 'MASTER'],
      mode: hyperpay['mode'] as String?,
      paymentId: data['paymentId'] as String?,
      reference: data['reference'] as String?,
      amount: data['amount'] as num?,
      currency: data['currency'] as String?,
      expiresAt: DateTime.tryParse(data['expiresAt']?.toString() ?? ''),
    );
  }

  static Future<String>? _refreshing;

  /// Calls `POST /v1/auth/refresh` (`client: mobile`) and stores the new
  /// token pair. Concurrent callers share one refresh, because refresh tokens
  /// are usually single-use.
  static Future<String> refreshTokens() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  static Future<String> _doRefresh() async {
    final refreshToken = await _refreshToken();
    if (refreshToken.isEmpty) {
      throw TuaApiException(
          401, 'Access token expired and no TUA_REFRESH_TOKEN');
    }
    final response = await http.post(
      Uri.parse('$baseUrl/v1/auth/refresh'),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'client': 'mobile', 'refreshToken': refreshToken}),
    );
    final data = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TuaApiException(
        response.statusCode,
        'Token refresh failed: ${_errorMessage(data, response)}. '
        'Put a fresh TUA_ACCESS_TOKEN / TUA_REFRESH_TOKEN pair in .env.',
      );
    }

    final access =
        _findString(data, const ['accessToken', 'access_token', 'token']);
    final refresh = _findString(data, const ['refreshToken', 'refresh_token']);
    if (access == null) {
      throw TuaApiException(
          response.statusCode, 'No access token in refresh response');
    }
    final prefs = await _prefs;
    await prefs.setString(_kAccessToken, access);
    if (refresh != null) await prefs.setString(_kRefreshToken, refresh);
    print(
        '[TuaApi] Tokens refreshed${refresh != null ? ' (refresh token rotated)' : ''}.');
    return access;
  }

  /// Depth-first search for the first non-empty string under one of [keys]
  /// (the token may be top-level or nested, e.g. `data.tokens.accessToken`).
  static String? _findString(Object? node, List<String> keys) {
    if (node is Map) {
      for (final key in keys) {
        final value = node[key];
        if (value is String && value.isNotEmpty) return value;
      }
      for (final value in node.values) {
        final found = _findString(value, keys);
        if (found != null) return found;
      }
    } else if (node is List) {
      for (final value in node) {
        final found = _findString(value, keys);
        if (found != null) return found;
      }
    }
    return null;
  }

  static Map<String, dynamic> _decode(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      return decoded is Map<String, dynamic> ? decoded : {'data': decoded};
    } catch (_) {
      return {};
    }
  }

  static String _errorMessage(Map<String, dynamic> data, http.Response r) {
    final message = data['message'];
    final code = data['code'];
    if (message != null || code != null) {
      return [message, if (code != null) '($code)']
          .whereType<Object>()
          .join(' ');
    }
    return r.body.isEmpty ? 'HTTP ${r.statusCode}' : r.body;
  }
}
