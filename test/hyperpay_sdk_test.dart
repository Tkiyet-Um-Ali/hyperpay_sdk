import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperpay_sdk/hyperpay_sdk.dart';

const _channel = MethodChannel('com.hyperpay.sdk/channel');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Simulates the native side calling Dart and returns Dart's reply.
  Future<Object?> callDart(String method, Object? args) async {
    final reply = await messenger.handlePlatformMessage(
      _channel.name,
      _channel.codec.encodeMethodCall(MethodCall(method, args)),
      (_) {},
    );
    return reply == null ? null : _channel.codec.decodeEnvelope(reply);
  }

  tearDown(() => messenger.setMockMethodCallHandler(_channel, null));

  group('CheckoutOptions.toMap', () {
    test('sends enum names and only set fields', () {
      final map = const CheckoutOptions(
        storePaymentDetails: StorePaymentDetailsMode.always,
        skipCvv: SkipCvvMode.forStoredCards,
        brandDetectionType: BrandDetectionType.binListAndType,
        tokensSecurityPolicy: SecurityPolicyMode.requiredIfAvailable,
        brandSecurityPolicies: {'VISA': SecurityPolicyMode.required},
        applePayButtonType: ApplePayButtonType.continueButton,
        applePayContactTypes: {ApplePayContactType.customer},
        installmentOptions: [1, 3],
        billingAddress: BillingAddress(country: 'SA', cityRequired: true),
        wpwlOptions: {
          'ONEY': WpwlOptions(configuration: {'locale': 'fr-BE'}),
        },
      ).toMap();

      expect(map['storePaymentDetails'], 'always');
      expect(map['skipCvv'], 'forStoredCards');
      expect(map['brandDetectionType'], 'binListAndType');
      expect(map['tokensSecurityPolicy'], 'requiredIfAvailable');
      expect(map['brandSecurityPolicies'], {'VISA': 'required'});
      expect(map['applePayButtonType'], 'continueButton');
      expect(map['applePayContactTypes'], ['customer']);
      expect(map['installmentOptions'], [1, 3]);
      expect(map['billingAddress'], containsPair('country', 'SA'));
      expect(map['billingAddress'], containsPair('cityRequired', true));
      expect(map['wpwlOptions']['ONEY']['configuration'], {'locale': 'fr-BE'});
      expect(map.containsKey('cardHolderVisible'), isFalse);
      expect(map.containsKey('theme'), isFalse);
    });

    test('theme drops unset colors and fonts', () {
      final map = const CheckoutTheme(
        style: CheckoutThemeStyle.dark,
        accentColor: 0xFF00897B,
        primaryFont: CheckoutFont(size: 15, bold: true),
      ).toMap();
      expect(map['style'], 'dark');
      expect(map['colors'], {'accentColor': 0xFF00897B});
      expect(map['fonts'], {
        'primaryFont': {'size': 15.0, 'bold': true},
      });
    });
  });

  test('ThreeDSConfig.toMap maps button types by name', () {
    final map = const ThreeDSConfig(
      challengeUiTypes: {ThreeDSChallengeUiType.text},
      requestorAppUrl: 'https://example.com/3ds',
      uiCustomization: ThreeDSUiCustomization(
        buttons: {
          ThreeDSButtonType.submit: ThreeDSButtonCustomization(
            backgroundColor: 0xFF000000,
          ),
        },
      ),
    ).toMap();
    expect(map['challengeUiTypes'], ['text']);
    expect(map['requestorAppUrl'], 'https://example.com/3ds');
    expect(map['uiCustomization']['buttons']['submit'], {
      'backgroundColor': 0xFF000000,
    });
  });

  test('CheckoutInfo.fromMap parses tokens and brands', () {
    final info = CheckoutInfo.fromMap({
      'amount': 10,
      'currencyCode': 'SAR',
      'resourcePath': '/v1/checkouts/x/payment',
      'brands': ['VISA', 'MADA'],
      'tokens': [
        {
          'tokenId': 't1',
          'paymentBrand': 'VISA',
          'cardLast4Digits': '1111',
          'cardExpiryMonth': '12',
          'cardExpiryYear': '2030',
        },
      ],
    });
    expect(info.amount, 10.0);
    expect(info.brands, ['VISA', 'MADA']);
    expect(info.tokens.single.tokenId, 't1');
    expect(info.tokens.single.isCard, isTrue);
  });

  test('CardValidationResult.isValid ignores unchecked fields', () {
    expect(const CardValidationResult(numberValid: true).isValid, isTrue);
    expect(const CardValidationResult(expired: true).isValid, isFalse);
    expect(const CardValidationResult(cvvValid: false).isValid, isFalse);
  });

  group('checkoutReadyUI', () {
    test('sends callback flags and options, maps the result', () async {
      late Map<String, dynamic> sent;
      messenger.setMockMethodCallHandler(_channel, (call) async {
        sent = Map<String, dynamic>.from(call.arguments as Map);
        return {'isSuccess': true, 'isCanceled': false, 'resourcePath': '/p'};
      });

      final result = await HyperpaySdk.checkoutReadyUI(
        checkoutId: 'c1',
        brands: ['MADA', 'VISA'],
        paymentBrand: 'CARD',
        options: const CheckoutOptions(displayTotalAmount: true),
        onBeforeSubmit: (_) async => const BeforeSubmitDecision.proceed(),
      );

      expect(result.isSuccess, isTrue);
      expect(result.resourcePath, '/p');
      expect(sent['brands'], ['MADA', 'VISA']);
      expect(sent['paymentBrand'], 'CARD');
      expect(sent['options'], {'displayTotalAmount': true});
      expect(sent['hasBeforeSubmit'], isTrue);
      expect(sent['hasApplePayShippingContactHandler'], isFalse);
    });

    test('routes onBeforeSubmit while the checkout is open', () async {
      Object? nativeReply;
      BeforeSubmitInfo? seen;
      messenger.setMockMethodCallHandler(_channel, (call) async {
        nativeReply = await callDart('onBeforeSubmit', {
          'checkoutId': 'c1',
          'paymentBrand': 'MADA',
        });
        return {'isSuccess': true, 'isCanceled': false};
      });

      await HyperpaySdk.checkoutReadyUI(
        checkoutId: 'c1',
        brands: ['MADA'],
        onBeforeSubmit: (info) async {
          seen = info;
          return const BeforeSubmitDecision.proceed(checkoutId: 'c2');
        },
      );

      expect(seen?.paymentBrand, 'MADA');
      expect(nativeReply, {'checkoutId': 'c2', 'abort': false});
    });

    test('a throwing onBeforeSubmit aborts the payment', () async {
      Object? nativeReply;
      messenger.setMockMethodCallHandler(_channel, (call) async {
        nativeReply = await callDart('onBeforeSubmit', {
          'checkoutId': 'c1',
          'paymentBrand': 'VISA',
        });
        return {'isSuccess': false, 'isCanceled': true};
      });

      final result = await HyperpaySdk.checkoutReadyUI(
        checkoutId: 'c1',
        brands: ['VISA'],
        onBeforeSubmit: (_) async => throw StateError('server down'),
      );

      expect(nativeReply, {'abort': true});
      expect(result.isCanceled, isTrue);
    });

    test('routes Apple Pay shipping callbacks', () async {
      Object? contactReply;
      messenger.setMockMethodCallHandler(_channel, (call) async {
        contactReply = await callDart('applePayShippingContactSelected', {
          'contact': {'city': 'Riyadh', 'isoCountryCode': 'SA'},
        });
        return {'isSuccess': true, 'isCanceled': false};
      });

      await HyperpaySdk.checkoutReadyUI(
        checkoutId: 'c1',
        brands: ['APPLEPAY'],
        onApplePayShippingContactSelected: (contact) async =>
            ApplePayShippingUpdate(
              summaryItems: [
                ApplePaySummaryItem(
                  label: 'Shop',
                  amount: contact.city == 'Riyadh' ? 10 : 20,
                ),
              ],
            ),
      );

      expect(contactReply, {
        'summaryItems': [
          {'label': 'Shop', 'amount': 10.0, 'pending': false},
        ],
      });
    });
  });

  test('payCustomUI omits brand when null (auto-detect)', () async {
    late Map<String, dynamic> sent;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      sent = Map<String, dynamic>.from(call.arguments as Map);
      return {'isSuccess': true, 'isCanceled': false};
    });
    await HyperpaySdk.payCustomUI(
      checkoutId: 'c1',
      cardNumber: '4200000000000000',
      holder: 'A B',
      expiryMonth: '12',
      expiryYear: '2030',
      cvv: '123',
    );
    expect(sent.containsKey('brand'), isFalse);
  });

  test('platform errors become a failed PaymentResult', () async {
    messenger.setMockMethodCallHandler(_channel, (call) async {
      throw PlatformException(code: 'UNSUPPORTED', message: 'iOS only');
    });
    final result = await HyperpaySdk.payApplePay(
      checkoutId: 'c1',
      merchantId: 'm',
      countryCode: 'SA',
      currencyCode: 'SAR',
      amount: 1,
      companyName: 'Shop',
      shopperResultUrl: 'app.payments',
    );
    expect(result.isSuccess, isFalse);
    expect(result.errorCode, 'UNSUPPORTED');
  });
}
