import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:hyperpay_sdk/hyperpay_sdk.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tua_api.dart';

class PaymentService {
  PaymentService._();

  static const shopperResultUrl = 'com.example.hyperpaysdk';

  static String get entityId => dotenv.env['HYPERPAY_ENTITY_ID'] ?? '';
  static String get accessToken => dotenv.env['HYPERPAY_ACCESS_TOKEN'] ?? '';

  /// Direct HyperPay REST access (test shortcut, never in production).
  /// Optional: only needed for the saved-cards and registration demos.
  static bool get hasHyperpayCredentials =>
      entityId.isNotEmpty && accessToken.isNotEmpty;

  /// Brands enabled for the most recent checkout. With the Tua backend these
  /// come from its response (`hyperpay.brands`).
  static List<String> checkoutBrands = const ['VISA', 'MASTER', 'MADA'];

  /// Call with every finished payment result and use the result it returns.
  ///
  /// With the Tua backend the SDK's "success" is checked against the backend,
  /// because it only means the payment was submitted: a declined card or a
  /// failed 3-D Secure check ends the same way. A successful or failed payment
  /// rotates the `Idempotency-Key`; a cancelled one keeps it.
  static Future<PaymentResult> completePayment(
    PaymentResult result, {
    String? locale,
  }) async {
    if (!TuaApi.isConfigured || result.isCanceled) return result;

    final paymentId = TuaApi.current?.paymentId;
    var verified = result;
    if (result.isSuccess && paymentId != null) {
      try {
        final outcome = await TuaApi.paymentOutcome(paymentId, locale: locale);
        if (!outcome.isPaid) {
          verified = PaymentResult(
            isSuccess: false,
            isCanceled: false,
            resourcePath: result.resourcePath,
            transactionType: result.transactionType,
            errorCode: 'PAYMENT_${outcome.status.toUpperCase()}',
            errorMessage: outcome.isOpen || outcome.status == 'review'
                ? 'Payment not confirmed yet (status: ${outcome.status}). '
                    'Check it again later.'
                : outcome.failureMessage ?? 'Payment ${outcome.status}',
          );
        }
      } catch (e) {
        verified = PaymentResult(
          isSuccess: false,
          isCanceled: false,
          resourcePath: result.resourcePath,
          transactionType: result.transactionType,
          errorCode: 'PAYMENT_UNVERIFIED',
          errorMessage: 'Could not confirm the payment with the backend: $e',
        );
      }
    }
    await TuaApi.paymentFinished(succeeded: verified.isSuccess);
    return verified;
  }

  static Future<String?> getCheckoutId({
    required String amount,
    String? paymentType = 'DB',
    bool tokenize = false,
    List<String> registrationIds = const [],
  }) async {
    if (TuaApi.isConfigured) {
      if (paymentType == null) {
        throw UnsupportedError(
            'Registration-only checkouts need a backend endpoint (the Tua '
            'checkout API creates donations) or HYPERPAY_* in .env.');
      }
      if (tokenize || registrationIds.isNotEmpty) {
        print('[HyperPay] Tua backend decides tokenization and stored cards; '
            'ignoring tokenize/registrationIds.');
      }
      final checkout = await TuaApi.createCheckout();
      checkoutBrands = checkout.brands;
      print('[HyperPay] Tua checkout ${checkout.reference}: '
          '${checkout.amount} ${checkout.currency}, brands ${checkout.brands}, '
          'mode ${checkout.mode}');
      return checkout.checkoutId;
    }
    if (!hasHyperpayCredentials) {
      throw StateError('Configure TUA_* (recommended) or HYPERPAY_* in .env');
    }

    // paymentType: null + tokenize: true = stand-alone registration (save a
    // card without paying; see HyperpaySdk.registerCard).
    final body = <String, String>{
      'entityId': entityId,
      'amount': amount,
      'currency': 'SAR',
      if (paymentType != null) 'paymentType': paymentType,
    };
    if (tokenize) body['createRegistration'] = 'true';
    for (var i = 0; i < registrationIds.length; i++) {
      body['registrations[$i].id'] = registrationIds[i];
    }

    print('[HyperPay] Checkout request body: $body');

    final response = await http.post(
      Uri.parse('https://eu-test.oppwa.com/v1/checkouts'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: body,
    );

    print(
        '[HyperPay] Checkout response ${response.statusCode}: ${response.body}');

    final data = jsonDecode(response.body);
    if (response.statusCode == 200 && data['id'] != null) {
      return data['id'] as String;
    }

    final msg = data['result']?['description'] ?? response.body;
    throw Exception('Failed to get checkout ID: $msg');
  }

  static Future<String?> extractAndSaveRegistration(String checkoutId) async {
    // Reading the registration ID needs HyperPay's REST API; with the Tua
    // backend your server stores it instead.
    if (!hasHyperpayCredentials) return null;
    final uri = Uri.parse(
      'https://eu-test.oppwa.com/v1/checkouts/$checkoutId/payment'
      '?entityId=$entityId',
    );
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $accessToken'},
    );

    if (response.statusCode != 200) return null;

    final data = jsonDecode(response.body);
    final registrationId = data['registrationId'] as String?;
    if (registrationId == null || registrationId.isEmpty) return null;

    final brand = data['paymentBrand'] as String? ?? '';
    final last4 = data['card']?['last4Digits'] as String? ?? '';
    final cardKey = '$brand:$last4';

    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList('saved_registration_ids') ?? [];
    final cardKeys = prefs.getStringList('saved_card_keys') ?? [];

    final existingIndex = cardKeys.indexOf(cardKey);
    if (existingIndex != -1 && existingIndex < ids.length) {
      ids[existingIndex] = registrationId;
    } else {
      ids.add(registrationId);
      cardKeys.add(cardKey);
    }
    await prefs.setStringList('saved_registration_ids', ids);
    await prefs.setStringList('saved_card_keys', cardKeys);

    return registrationId;
  }

  static String formatResult(PaymentResult result) {
    final buf = StringBuffer();
    if (result.isSuccess) {
      buf.writeln('Payment successful!');
      buf.writeln('Type: ${result.transactionType}');
      if (result.resourcePath != null) {
        buf.writeln('Resource: ${result.resourcePath}');
      }
    } else if (result.isCanceled) {
      buf.writeln('Payment canceled by user');
    } else {
      buf.writeln('Payment failed');
      if (result.errorCode != null) buf.writeln('Code: ${result.errorCode}');
      if (result.errorMessage != null) {
        buf.writeln('Message: ${result.errorMessage}');
      }
    }
    return buf.toString().trimRight();
  }
}
