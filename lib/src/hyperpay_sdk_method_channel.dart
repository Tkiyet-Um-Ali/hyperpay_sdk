import 'package:flutter/services.dart';
import 'models.dart';

/// Internal MethodChannel communication layer.
/// Not intended for direct use — use [HyperpaySdk] instead.
///
/// Native → Dart calls (all return a map):
/// - `resolveApplePayCheckout {network}` → `{checkoutId}` | `{error}`
/// - `onBeforeSubmit {checkoutId, paymentBrand, selectedInstallmentPlan?}`
///   → `{checkoutId?, abort}`
/// - `applePayShippingContactSelected {contact}` → shipping update map
/// - `applePayShippingMethodSelected {method}` → shipping update map
class HyperpaySdkMethodChannel {
  static const MethodChannel _channel = MethodChannel(
    'com.hyperpay.sdk/channel',
  );

  /// Resolver active for the duration of a single [payApplePayDynamic] call.
  static Future<String> Function(String network)? _pendingApplePayResolver;

  /// Ready-UI callbacks active for the duration of one [checkoutReadyUI] call.
  static Future<BeforeSubmitDecision> Function(BeforeSubmitInfo info)?
  _onBeforeSubmit;
  static Future<ApplePayShippingUpdate> Function(ApplePayContact contact)?
  _onShippingContact;
  static Future<ApplePayShippingUpdate> Function(ApplePayShippingMethod method)?
  _onShippingMethod;

  static bool _nativeHandlerInstalled = false;

  static void _ensureNativeHandler() {
    if (_nativeHandlerInstalled) return;
    _nativeHandlerInstalled = true;
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  static Map<String, dynamic> _args(Object? raw) =>
      raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};

  static Future<Object?> _handleNativeCall(MethodCall call) async {
    final args = _args(call.arguments);
    switch (call.method) {
      case 'resolveApplePayCheckout':
        final resolver = _pendingApplePayResolver;
        if (resolver == null) {
          return <String, dynamic>{'error': 'No pending Apple Pay resolver'};
        }
        try {
          final checkoutId = await resolver((args['network'] as String?) ?? '');
          return <String, dynamic>{'checkoutId': checkoutId};
        } catch (e) {
          return <String, dynamic>{'error': e.toString()};
        }
      case 'onBeforeSubmit':
        final callback = _onBeforeSubmit;
        if (callback == null) {
          return const BeforeSubmitDecision.proceed().toMap();
        }
        try {
          final decision = await callback(BeforeSubmitInfo.fromMap(args));
          return decision.toMap();
        } catch (_) {
          // A throwing callback must not submit a payment the app didn't
          // approve.
          return const BeforeSubmitDecision.abort().toMap();
        }
      case 'applePayShippingContactSelected':
        final callback = _onShippingContact;
        if (callback == null) return null;
        final update = await callback(
          ApplePayContact.fromMap(_args(args['contact'])),
        );
        return update.toMap();
      case 'applePayShippingMethodSelected':
        final callback = _onShippingMethod;
        if (callback == null) return null;
        final update = await callback(
          ApplePayShippingMethod.fromMap(_args(args['method'])),
        );
        return update.toMap();
    }
    return null;
  }

  /// Invokes a native method that resolves to a payment result map.
  static Future<PaymentResult> _invokePayment(
    String method,
    Map<String, dynamic> arguments,
  ) async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        method,
        arguments,
      );
      if (result == null) {
        return PaymentResult.canceled();
      }
      return PaymentResult.fromMap(Map<String, dynamic>.from(result));
    } on PlatformException catch (e) {
      return PaymentResult.error(
        errorCode: e.code,
        errorMessage: e.message ?? 'Unknown error',
      );
    }
  }

  static Future<void> setup({
    required PaymentMode mode,
    ThreeDSConfig? threeDSConfig,
  }) async {
    await _channel.invokeMethod('setup', {
      'mode': mode == PaymentMode.test ? 'test' : 'live',
      if (threeDSConfig != null) 'threeDSConfig': threeDSConfig.toMap(),
    });
  }

  static Future<PaymentResult> checkoutReadyUI({
    required String checkoutId,
    required List<String> brands,
    String? shopperResultUrl,
    GooglePayConfig? googlePayConfig,
    ApplePayConfig? applePayConfig,
    String? lang,
    int? themeColor,
    String? paymentBrand,
    CheckoutOptions? options,
    ThreeDSConfig? threeDSConfig,
    Future<BeforeSubmitDecision> Function(BeforeSubmitInfo info)?
    onBeforeSubmit,
    Future<ApplePayShippingUpdate> Function(ApplePayContact contact)?
    onApplePayShippingContactSelected,
    Future<ApplePayShippingUpdate> Function(ApplePayShippingMethod method)?
    onApplePayShippingMethodSelected,
  }) async {
    _ensureNativeHandler();
    _onBeforeSubmit = onBeforeSubmit;
    _onShippingContact = onApplePayShippingContactSelected;
    _onShippingMethod = onApplePayShippingMethodSelected;
    try {
      return await _invokePayment('checkoutReadyUI', {
        'checkoutId': checkoutId,
        'brands': brands,
        if (shopperResultUrl != null) 'shopperResultUrl': shopperResultUrl,
        if (googlePayConfig != null) 'googlePayConfig': googlePayConfig.toMap(),
        if (applePayConfig != null) 'applePayConfig': applePayConfig.toMap(),
        if (lang != null) 'lang': lang,
        if (themeColor != null) 'themeColor': themeColor,
        if (paymentBrand != null) 'paymentBrand': paymentBrand,
        if (options != null) 'options': options.toMap(),
        if (threeDSConfig != null) 'threeDSConfig': threeDSConfig.toMap(),
        'hasBeforeSubmit': onBeforeSubmit != null,
        'hasApplePayShippingContactHandler':
            onApplePayShippingContactSelected != null,
        'hasApplePayShippingMethodHandler':
            onApplePayShippingMethodSelected != null,
      });
    } finally {
      _onBeforeSubmit = null;
      _onShippingContact = null;
      _onShippingMethod = null;
    }
  }

  static Future<PaymentResult> payCustomUI({
    required String checkoutId,
    String? brand,
    required String cardNumber,
    required String holder,
    required String expiryMonth,
    required String expiryYear,
    required String cvv,
    String? shopperResultUrl,
    bool tokenize = false,
  }) {
    return _invokePayment('payCustomUI', {
      'checkoutId': checkoutId,
      if (brand != null && brand.isNotEmpty) 'brand': brand,
      'cardNumber': cardNumber,
      'holder': holder,
      'expiryMonth': expiryMonth,
      'expiryYear': expiryYear,
      'cvv': cvv,
      'tokenize': tokenize,
      if (shopperResultUrl != null) 'shopperResultUrl': shopperResultUrl,
    });
  }

  static Future<PaymentResult> payWithToken({
    required String checkoutId,
    required String tokenId,
    required String brand,
    String? cvv,
    String? shopperResultUrl,
  }) {
    return _invokePayment('payWithToken', {
      'checkoutId': checkoutId,
      'tokenId': tokenId,
      'brand': brand,
      if (cvv != null && cvv.isNotEmpty) 'cvv': cvv,
      if (shopperResultUrl != null) 'shopperResultUrl': shopperResultUrl,
    });
  }

  static Future<PaymentResult> registerCard({
    required String checkoutId,
    String? brand,
    required String cardNumber,
    required String holder,
    required String expiryMonth,
    required String expiryYear,
    required String cvv,
    String? shopperResultUrl,
  }) {
    return _invokePayment('registerCard', {
      'checkoutId': checkoutId,
      if (brand != null && brand.isNotEmpty) 'brand': brand,
      'cardNumber': cardNumber,
      'holder': holder,
      'expiryMonth': expiryMonth,
      'expiryYear': expiryYear,
      'cvv': cvv,
      if (shopperResultUrl != null) 'shopperResultUrl': shopperResultUrl,
    });
  }

  static Future<PaymentResult> payStcPay({
    required String checkoutId,
    required StcPayVerificationOption verificationOption,
    String? mobilePhone,
    String? shopperResultUrl,
  }) {
    return _invokePayment('payStcPay', {
      'checkoutId': checkoutId,
      'verificationOption': verificationOption.name,
      if (mobilePhone != null) 'mobilePhone': mobilePhone,
      if (shopperResultUrl != null) 'shopperResultUrl': shopperResultUrl,
    });
  }

  static Future<PaymentResult> payWithBrand({
    required String checkoutId,
    required String brand,
    Map<String, String>? parameters,
    String? shopperResultUrl,
  }) {
    return _invokePayment('payWithBrand', {
      'checkoutId': checkoutId,
      'brand': brand,
      if (parameters != null) 'parameters': parameters,
      if (shopperResultUrl != null) 'shopperResultUrl': shopperResultUrl,
    });
  }

  static Future<PaymentResult> payGooglePay({
    required String checkoutId,
    required String paymentToken,
    required String cardBrand,
    String? brand,
    String? shopperResultUrl,
  }) {
    return _invokePayment('payGooglePay', {
      'checkoutId': checkoutId,
      'paymentToken': paymentToken,
      'cardBrand': cardBrand,
      if (brand != null) 'brand': brand,
      if (shopperResultUrl != null) 'shopperResultUrl': shopperResultUrl,
    });
  }

  static Future<PaymentResult> paySamsungPay({
    required String checkoutId,
    required String paymentCredential,
    String? brand,
    String? shopperResultUrl,
  }) {
    return _invokePayment('paySamsungPay', {
      'checkoutId': checkoutId,
      'paymentCredential': paymentCredential,
      if (brand != null) 'brand': brand,
      if (shopperResultUrl != null) 'shopperResultUrl': shopperResultUrl,
    });
  }

  static Future<KlarnaSession> _invokeKlarna(
    String method,
    Map<String, dynamic> arguments,
  ) async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      method,
      arguments,
    );
    return KlarnaSession.fromMap(
      result == null ? {} : Map<String, dynamic>.from(result),
    );
  }

  static Future<KlarnaSession> klarnaCreateSession({
    required String checkoutId,
    required String brand,
    required String shopperResultUrl,
  }) {
    return _invokeKlarna('klarnaCreateSession', {
      'checkoutId': checkoutId,
      'brand': brand,
      'shopperResultUrl': shopperResultUrl,
    });
  }

  static Future<KlarnaSession> klarnaSubmitPayment({
    required String checkoutId,
    required String brand,
    required String initialTransactionId,
    required String shopperResultUrl,
  }) {
    return _invokeKlarna('klarnaSubmitPayment', {
      'checkoutId': checkoutId,
      'brand': brand,
      'initialTransactionId': initialTransactionId,
      'shopperResultUrl': shopperResultUrl,
    });
  }

  static Future<CardValidationResult> validateCard({
    String? number,
    String? holder,
    String? expiryMonth,
    String? expiryYear,
    String? cvv,
    String? brand,
    bool luhnCheck = true,
  }) async {
    final result = await _channel
        .invokeMethod<Map<dynamic, dynamic>>('validateCard', {
          if (number != null) 'number': number,
          if (holder != null) 'holder': holder,
          if (expiryMonth != null) 'expiryMonth': expiryMonth,
          if (expiryYear != null) 'expiryYear': expiryYear,
          if (cvv != null) 'cvv': cvv,
          if (brand != null) 'brand': brand,
          'luhnCheck': luhnCheck,
        });
    return CardValidationResult.fromMap(
      result == null ? {} : Map<String, dynamic>.from(result),
    );
  }

  static Future<PaymentResult> payApplePay({
    required String checkoutId,
    required String merchantId,
    required String countryCode,
    required String currencyCode,
    required double amount,
    required String companyName,
    required String shopperResultUrl,
    ApplePayConfig? config,
  }) {
    return _invokePayment('payApplePay', {
      if (config != null) ...config.toMap(),
      'checkoutId': checkoutId,
      'merchantId': merchantId,
      'countryCode': countryCode,
      'currencyCode': currencyCode,
      'amount': amount,
      'companyName': companyName,
      'shopperResultUrl': shopperResultUrl,
    });
  }

  static Future<PaymentResult> payApplePayDynamic({
    required Future<String> Function(String network) resolveCheckout,
    required String merchantId,
    required String countryCode,
    required String currencyCode,
    required double amount,
    required String companyName,
    required String shopperResultUrl,
    ApplePayConfig? config,
  }) async {
    _ensureNativeHandler();
    _pendingApplePayResolver = resolveCheckout;
    try {
      return await _invokePayment('payApplePayDynamic', {
        if (config != null) ...config.toMap(),
        'merchantId': merchantId,
        'countryCode': countryCode,
        'currencyCode': currencyCode,
        'amount': amount,
        'companyName': companyName,
        'shopperResultUrl': shopperResultUrl,
      });
    } finally {
      _pendingApplePayResolver = null;
    }
  }

  static Future<bool> isApplePayAvailable({List<String>? networks}) async {
    final result = await _channel.invokeMethod<bool>('isApplePayAvailable', {
      if (networks != null) 'networks': networks,
    });
    return result ?? false;
  }

  static Future<HyperpayBinInfo> requestBinInfo({
    required String checkoutId,
    required String bin,
  }) async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'requestBinInfo',
      {'checkoutId': checkoutId, 'bin': bin},
    );
    if (result == null) {
      return const HyperpayBinInfo(brands: <String>[]);
    }
    return HyperpayBinInfo.fromMap(Map<String, dynamic>.from(result));
  }

  static Future<CheckoutInfo> getCheckoutInfo({
    required String checkoutId,
  }) async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getCheckoutInfo',
        {'checkoutId': checkoutId},
      );
      if (result == null) {
        return const CheckoutInfo();
      }
      return CheckoutInfo.fromMap(Map<String, dynamic>.from(result));
    } on PlatformException catch (e) {
      throw Exception('Failed to get checkout info: ${e.message}');
    }
  }

  static Future<CheckoutInfo> getPaymentStatus({
    required String checkoutId,
    String? resourcePath,
  }) async {
    try {
      final result = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('getPaymentStatus', {
            'checkoutId': checkoutId,
            if (resourcePath != null) 'resourcePath': resourcePath,
          });
      if (result == null) {
        return const CheckoutInfo();
      }
      return CheckoutInfo.fromMap(Map<String, dynamic>.from(result));
    } on PlatformException catch (e) {
      throw Exception('Failed to get payment status: ${e.message}');
    }
  }

  static Future<List<ThreeDSWarning>> getThreeDSWarnings() async {
    final result = await _channel.invokeMethod<List<dynamic>>(
      'getThreeDSWarnings',
    );
    return (result ?? const [])
        .whereType<Map>()
        .map((w) => ThreeDSWarning.fromMap(Map<String, dynamic>.from(w)))
        .toList(growable: false);
  }
}
