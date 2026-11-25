import 'package:flutter_test/flutter_test.dart';
import 'package:hyperpay_sdk/hyperpay_sdk.dart';
import 'package:hyperpay_sdk/tua_checkout.dart';

/// Answers like the Tua backend; [statuses] is what GET returns per call.
class _FakeBackend implements TuaCheckoutBackend {
  final calls = <String>[];
  final keys = <String>[];
  Object? createError;
  Object? retryError;
  List<String> statuses = ['succeeded'];
  String? failureMessage;
  int _get = 0;

  TuaCheckout _checkout(String id, String paymentId) =>
      TuaCheckout(checkoutId: id, brands: const ['VISA'], paymentId: paymentId);

  @override
  Future<TuaCheckout> createCheckout({required String idempotencyKey}) async {
    calls.add('create');
    keys.add(idempotencyKey);
    final error = createError;
    if (error != null) {
      createError = null;
      throw error;
    }
    return _checkout('c${keys.length}', 'p${keys.length}');
  }

  @override
  Future<TuaPayment> getPayment(String paymentId, {String? locale}) async {
    calls.add('get $paymentId');
    final status =
        statuses[_get < statuses.length ? _get++ : statuses.length - 1];
    return TuaPayment(
      paymentId: paymentId,
      status: status,
      failureMessage: status == 'failed' ? failureMessage : null,
      checkout: status == 'pending' ? _checkout('resumed', paymentId) : null,
    );
  }

  @override
  Future<TuaCheckout> retryPayment(String paymentId) async {
    calls.add('retry $paymentId');
    final error = retryError;
    if (error != null) throw error;
    return _checkout('retried', paymentId);
  }

  @override
  Future<void> cancelPayment(String paymentId) async =>
      calls.add('cancel $paymentId');
}

const _submitted = PaymentResult(isSuccess: true, isCanceled: false);

void main() {
  late _FakeBackend backend;
  late TuaCheckoutSession session;
  var n = 0;

  setUp(() {
    backend = _FakeBackend();
    session = TuaCheckoutSession(
      backend,
      newIdempotencyKey: () => 'key${++n}',
      pollInterval: Duration.zero,
    );
  });

  test(
    'a submitted payment is only paid when the backend confirms it',
    () async {
      await session.start();
      backend.statuses = ['processing', 'succeeded'];
      final result = await session.finish(_submitted);
      expect(result.isPaid, isTrue);
      expect(backend.calls, ['create', 'get p1', 'get p1']);
    },
  );

  test('an SDK success the backend reports failed is not paid; next '
      'attempt retries the same payment', () async {
    await session.start();
    backend
      ..statuses = ['failed']
      ..failureMessage = 'Your bank declined the payment.';
    final result = await session.finish(_submitted);
    expect(result.isPaid, isFalse);
    expect(result.payment?.failureMessage, 'Your bank declined the payment.');
    expect(session.checkout, isNull);

    final next = await session.start();
    expect(next.checkoutId, 'retried');
    expect(backend.calls.last, 'retry p1');
  });

  test('a refused retry falls back to a new checkout with a new key', () async {
    await session.start();
    backend.statuses = ['failed'];
    await session.finish(_submitted);
    backend.retryError = TuaBackendException(
      409,
      'no',
      code: 'payments.retry_not_allowed',
    );
    await session.start();
    expect(backend.calls.sublist(backend.calls.length - 2), [
      'retry p1',
      'create',
    ]);
    expect(backend.keys[0], isNot(backend.keys[1]));
  });

  test('a cancelled card form keeps the checkout and key', () async {
    final first = await session.start();
    final result = await session.finish(
      const PaymentResult(isSuccess: false, isCanceled: true),
    );
    expect(result.isPaid, isFalse);
    expect(session.checkout, same(first));
    expect(backend.calls, ['create']);
  });

  test('an SDK error before anything was charged keeps the checkout', () async {
    final first = await session.start();
    backend.statuses = ['pending'];
    await session.finish(
      PaymentResult.error(errorCode: 'X', errorMessage: 'x'),
    );
    expect(session.checkout, same(first));
  });

  test('a reused or expired key is replaced once', () async {
    backend.createError = TuaBackendException(
      422,
      'used',
      code: 'payments.idempotency_key_reused',
    );
    await session.start();
    expect(backend.calls, ['create', 'create']);
    expect(backend.keys, ['key${n - 1}', 'key$n']);
  });

  group('too many open checkouts', () {
    TuaOpenCheckoutsException refusal() => TuaOpenCheckoutsException(
      'unfinished',
      retryAfterSeconds: 600,
      openCheckouts: const [
        TuaOpenCheckout(paymentId: 'old1', status: 'processing'),
        TuaOpenCheckout(paymentId: 'old2', status: 'pending'),
      ],
    );

    test('resume continues the oldest resumable donation', () async {
      backend
        ..createError = refusal()
        ..statuses = ['pending'];
      final checkout = await session.start(
        onOpenCheckouts: (_) async => TuaOpenCheckoutChoice.resume,
      );
      expect(checkout.checkoutId, 'resumed');
      expect(backend.calls, ['create', 'get old2']);
    });

    test('start over cancels the resumable ones and creates again', () async {
      backend.createError = refusal();
      final checkout = await session.start(
        onOpenCheckouts: (_) async => TuaOpenCheckoutChoice.startOver,
      );
      expect(checkout.checkoutId, startsWith('c'));
      expect(backend.calls, ['create', 'cancel old2', 'create']);
    });

    test('without a handler the refusal is thrown', () async {
      backend.createError = refusal();
      expect(session.start(), throwsA(isA<TuaOpenCheckoutsException>()));
    });
  });

  test('TuaRestBackend maps requests and errors', () async {
    final sent = <String>[];
    final rest = TuaRestBackend(
      checkoutBody: () => {'programSlug': 'x'},
      send: (method, path, {body, headers}) async {
        sent.add(
          '$method $path ${body?['client']} ${headers?['Idempotency-Key']}',
        );
        if (path.endsWith('/cancel')) {
          return const TuaHttpResponse(409, {
            'code': 'payments.payment_not_cancellable',
            'message': 'Being processed',
          });
        }
        if (path == '/v1/donations/checkout') {
          return const TuaHttpResponse(429, {
            'code': 'payments.too_many_open_checkouts',
            'message': 'Too many',
            'retryAfterSeconds': 60,
            'openCheckouts': [
              {'paymentId': 'p', 'status': 'failed', 'checkoutId': 'c'},
            ],
          });
        }
        return const TuaHttpResponse(200, {
          'paymentId': 'p',
          'status': 'pending',
          'lines': [
            {
              'programName': 'Food',
              'quantity': 2,
              'unitAmount': 5,
              'amount': 10,
            },
          ],
          'hyperpay': {
            'checkoutId': 'c',
            'brands': ['VISA', 'MASTER'],
            'amex': {'checkoutId': 'a'},
          },
        });
      },
    );

    await expectLater(
      rest.createCheckout(idempotencyKey: 'k'),
      throwsA(
        isA<TuaOpenCheckoutsException>()
            .having(
              (e) => e.openCheckouts.single.isResumable,
              'resumable',
              true,
            )
            .having((e) => e.retryAfterSeconds, 'retryAfter', 60),
      ),
    );
    final payment = await rest.getPayment('p', locale: 'ar');
    expect(payment.lines.single.programName, 'Food');
    expect(payment.checkout?.amexCheckoutId, 'a');
    await expectLater(
      rest.cancelPayment('p'),
      throwsA(
        isA<TuaBackendException>().having(
          (e) => e.code,
          'code',
          'payments.payment_not_cancellable',
        ),
      ),
    );
    expect(sent, [
      'POST /v1/donations/checkout mobile k',
      'GET /v1/donations/payments/p?locale=ar null null',
      'POST /v1/donations/payments/p/cancel null null',
    ]);
  });
}
