import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hyperpay_sdk/hyperpay_sdk.dart';
import 'package:hyperpay_sdk_example/services/payment_service.dart';
import 'package:hyperpay_sdk_example/services/tua_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _hyperpay(String checkoutId) => {
      'checkoutId': checkoutId,
      'brands': ['VISA', 'MASTER'],
      'mode': 'test',
      'amex': null,
    };

http.Response _json(int status, Object body) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

http.Response _tooManyOpen(List<Map<String, dynamic>> open) => _json(429, {
      'statusCode': 429,
      'message': 'You already have several unfinished payments.',
      'code': 'payments.too_many_open_checkouts',
      'openCheckouts': open,
      'retryAfterSeconds': 1200,
    });

void main() {
  late List<String> calls;

  setUp(() {
    calls = [];
    TuaApi.current = null;
    SharedPreferences.setMockInitialValues({});
    dotenv.loadFromString(envString: '''
TUA_API_BASE_URL=https://api.test
TUA_ACCESS_TOKEN=access
TUA_REFRESH_TOKEN=refresh
''');
  });

  Future<T> withServer<T>(
    http.Response Function(http.Request) handler,
    Future<T> Function() body,
  ) =>
      http.runWithClient(
        body,
        () => MockClient((request) async {
          calls.add('${request.method} ${request.url.path}');
          return handler(request);
        }),
      );

  test('429 resumes the oldest pending checkout', () async {
    final checkout = await withServer((r) {
      if (r.url.path == '/v1/donations/checkout') {
        return _tooManyOpen([
          {'paymentId': 'p1', 'status': 'processing', 'checkoutId': 'c1'},
          {'paymentId': 'p2', 'status': 'pending', 'checkoutId': 'c2'},
        ]);
      }
      return _json(200, {
        'paymentId': 'p2',
        'status': 'pending',
        'amount': 58,
        'currency': 'JOD',
        'hyperpay': _hyperpay('c2'),
      });
    }, TuaApi.createCheckout);

    expect(checkout.checkoutId, 'c2');
    expect(checkout.paymentId, 'p2');
    expect(calls, [
      'POST /v1/donations/checkout',
      'GET /v1/donations/payments/p2',
    ]);
  });

  test('429 retries a failed checkout', () async {
    final checkout = await withServer((r) {
      if (r.url.path == '/v1/donations/checkout') {
        return _tooManyOpen([
          {'paymentId': 'p3', 'status': 'failed', 'checkoutId': 'c3'},
        ]);
      }
      return _json(200, {'paymentId': 'p3', 'hyperpay': _hyperpay('c3b')});
    }, TuaApi.createCheckout);

    expect(checkout.checkoutId, 'c3b');
    expect(calls.last, 'POST /v1/donations/payments/p3/retry');
  });

  test('429 with nothing to recover throws with retryAfter', () async {
    final call = withServer(
      (r) => _tooManyOpen(const []),
      TuaApi.createCheckout,
    );
    await expectLater(
      call,
      throwsA(isA<TuaOpenCheckoutsException>()
          .having((e) => e.retryAfterSeconds, 'retryAfterSeconds', 1200)),
    );
  });

  test('a failed payment is retried on the next checkout', () async {
    await withServer(
      (r) => _json(201, {'paymentId': 'p4', 'hyperpay': _hyperpay('c4')}),
      TuaApi.createCheckout,
    );
    final keyBefore = await TuaApi.idempotencyKey();
    await TuaApi.paymentFinished(succeeded: false);
    expect(await TuaApi.idempotencyKey(), isNot(keyBefore));

    calls.clear();
    final checkout = await withServer(
      (r) => _json(200, {'paymentId': 'p4', 'hyperpay': _hyperpay('c4b')}),
      TuaApi.createCheckout,
    );
    expect(checkout.checkoutId, 'c4b');
    expect(calls, ['POST /v1/donations/payments/p4/retry']);
  });

  test('retry not allowed falls back to a new checkout', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tua_failed_payment_id', 'p5');
    final checkout = await withServer((r) {
      if (r.url.path.endsWith('/retry')) {
        return _json(409, {'code': 'payments.retry_not_allowed'});
      }
      return _json(201, {'paymentId': 'p6', 'hyperpay': _hyperpay('c6')});
    }, TuaApi.createCheckout);

    expect(checkout.checkoutId, 'c6');
    expect(calls, [
      'POST /v1/donations/payments/p5/retry',
      'POST /v1/donations/checkout',
    ]);
    expect(prefs.getString('tua_failed_payment_id'), isNull);
  });

  test('an SDK success that the backend reports declined is a failure',
      () async {
    await withServer(
      (r) => _json(201, {'paymentId': 'p7', 'hyperpay': _hyperpay('c7')}),
      TuaApi.createCheckout,
    );
    final result = await withServer(
      (r) => _json(200, {
        'paymentId': 'p7',
        'status': 'failed',
        'failure': {'reason': 'declined', 'message': 'Your bank declined.'},
        'retry': {'allowed': true},
      }),
      () => PaymentService.completePayment(
        const PaymentResult(isSuccess: true, isCanceled: false),
      ),
    );
    expect(result.isSuccess, isFalse);
    expect(result.errorCode, 'PAYMENT_FAILED');
    expect(result.errorMessage, 'Your bank declined.');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('tua_failed_payment_id'), 'p7');
  });

  test('an SDK success the backend confirms stays a success', () async {
    await withServer(
      (r) => _json(201, {'paymentId': 'p8', 'hyperpay': _hyperpay('c8')}),
      TuaApi.createCheckout,
    );
    final result = await withServer(
      (r) => _json(200, {'paymentId': 'p8', 'status': 'succeeded'}),
      () => PaymentService.completePayment(
        const PaymentResult(isSuccess: true, isCanceled: false),
      ),
    );
    expect(result.isSuccess, isTrue);
    expect(calls.last, 'GET /v1/donations/payments/p8');
  });
}
