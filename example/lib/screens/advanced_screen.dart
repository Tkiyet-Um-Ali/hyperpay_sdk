import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hyperpay_sdk/hyperpay_sdk.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/payment_service.dart';
import '../widgets/payment_tile.dart';
import '../widgets/status_card.dart';

/// Demos of the less common SDK features: Ready-UI options and callbacks,
/// single-brand checkout, stored-token payments, card registration, card
/// validation and 3DS security warnings.
class AdvancedScreen extends StatefulWidget {
  const AdvancedScreen({super.key, required this.amount});

  final String amount;

  @override
  State<AdvancedScreen> createState() => _AdvancedScreenState();
}

class _AdvancedScreenState extends State<AdvancedScreen> {
  String _status = 'Pick a feature to try';
  bool _isLoading = false;

  // Visa test card from HyperPay's testing guide.
  static const _testCard = (
    number: '4200000000000000',
    holder: 'Test Holder',
    month: '12',
    year: '2030',
    cvv: '123',
  );

  Future<void> _run(String label, Future<String> Function() action) async {
    setState(() {
      _isLoading = true;
      _status = '$label…';
    });
    try {
      final status = await action();
      if (mounted) setState(() => _status = status);
    } catch (e) {
      if (mounted) setState(() => _status = '$label error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<List<String>> _savedRegistrationIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('saved_registration_ids') ?? [];
  }

  /// Ready-UI with options and a before-submit confirmation (order summary).
  Future<String> _readyUIWithOptions() async {
    final accent = Theme.of(context).colorScheme.primary.toARGB32();
    final checkoutId = await PaymentService.getCheckoutId(
      amount: widget.amount,
      registrationIds: await _savedRegistrationIds(),
    );
    if (checkoutId == null) return 'No checkout ID';

    final sdkResult = await HyperpaySdk.checkoutReadyUI(
      checkoutId: checkoutId,
      brands: PaymentService.checkoutBrands,
      shopperResultUrl: PaymentService.shopperResultUrl,
      options: CheckoutOptions(
        storePaymentDetails: StorePaymentDetailsMode.prompt,
        displayTotalAmount: true,
        brandDetectionType: BrandDetectionType.binList,
        brandDetectionPriority: PaymentService.checkoutBrands,
        billingAddress: const BillingAddress(country: 'SA', city: 'Riyadh'),
        tokensSecurityPolicy: SecurityPolicyMode.requiredIfAvailable,
        cardHolderPattern: r"^[A-Za-z][A-Za-z .'-]{1,49}$",
        theme: CheckoutTheme(
          accentColor: accent,
        ),
      ),
      onBeforeSubmit: (info) async {
        if (!mounted) return const BeforeSubmitDecision.abort();
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Confirm payment'),
            content:
                Text('Pay ${widget.amount} SAR with ${info.paymentBrand}?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Pay'),
              ),
            ],
          ),
        );
        return confirmed == true
            ? const BeforeSubmitDecision.proceed()
            : const BeforeSubmitDecision.abort();
      },
    );
    final result = await PaymentService.completePayment(sdkResult);
    return PaymentService.formatResult(result);
  }

  /// Open the Ready-UI straight on one brand's form.
  Future<String> _singleBrand(String brand) async {
    final checkoutId =
        await PaymentService.getCheckoutId(amount: widget.amount);
    if (checkoutId == null) return 'No checkout ID';
    final sdkResult = await HyperpaySdk.checkoutReadyUI(
      checkoutId: checkoutId,
      brands: brand == 'CARD' ? PaymentService.checkoutBrands : [brand],
      paymentBrand: brand,
      shopperResultUrl: PaymentService.shopperResultUrl,
    );
    final result = await PaymentService.completePayment(sdkResult);
    return PaymentService.formatResult(result);
  }

  /// List the checkout's stored tokens and pay with the first one from our
  /// own UI.
  Future<String> _payWithStoredToken() async {
    final ids = await _savedRegistrationIds();
    if (ids.isEmpty) {
      return 'No saved cards yet. Pay once with "save card" switched on.';
    }
    final checkoutId = await PaymentService.getCheckoutId(
      amount: widget.amount,
      registrationIds: ids,
    );
    if (checkoutId == null) return 'No checkout ID';

    final info = await HyperpaySdk.getCheckoutInfo(checkoutId: checkoutId);
    if (info.tokens.isEmpty) return 'Checkout has no tokens: $info';
    final token = info.tokens.first;

    final sdkResult = await HyperpaySdk.payWithToken(
      checkoutId: checkoutId,
      tokenId: token.tokenId,
      brand: token.paymentBrand,
      cvv: _testCard.cvv,
      shopperResultUrl: PaymentService.shopperResultUrl,
    );
    final result = await PaymentService.completePayment(sdkResult);
    return 'Paid with ${token.paymentBrand} •••• ${token.cardLast4Digits}\n'
        '${PaymentService.formatResult(result)}';
  }

  /// Save a card without paying (stand-alone registration).
  Future<String> _registerCard() async {
    final checkoutId = await PaymentService.getCheckoutId(
      amount: widget.amount,
      paymentType: null,
      tokenize: true,
    );
    if (checkoutId == null) return 'No checkout ID';
    final result = await HyperpaySdk.registerCard(
      checkoutId: checkoutId,
      brand: 'VISA',
      cardNumber: _testCard.number,
      holder: _testCard.holder,
      expiryMonth: _testCard.month,
      expiryYear: _testCard.year,
      cvv: _testCard.cvv,
      shopperResultUrl: PaymentService.shopperResultUrl,
    );
    return 'Registration: ${PaymentService.formatResult(result)}\n'
        'Query the token from your server with the resource path.';
  }

  Future<String> _validateCard() async {
    final good = await HyperpaySdk.validateCard(
      number: _testCard.number,
      holder: _testCard.holder,
      expiryMonth: _testCard.month,
      expiryYear: _testCard.year,
      cvv: _testCard.cvv,
      brand: 'VISA',
    );
    final bad = await HyperpaySdk.validateCard(
      number: '4200000000000001',
      expiryMonth: '13',
      expiryYear: '2020',
    );
    return 'Test card: $good\n\nBroken card: $bad';
  }

  Future<String> _threeDSWarnings() async {
    final warnings = await HyperpaySdk.getThreeDSWarnings();
    final applePay = Platform.isIOS
        ? '\nApple Pay available: ${await HyperpaySdk.isApplePayAvailable()}'
        : '';
    return warnings.isEmpty
        ? 'No 3DS security warnings$applePay'
        : '${warnings.join('\n')}$applePay';
  }

  @override
  Widget build(BuildContext context) {
    VoidCallback? tap(String label, Future<String> Function() action) =>
        _isLoading ? null : () => _run(label, action);

    return Scaffold(
      appBar: AppBar(title: const Text('Advanced features')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PaymentTile(
            icon: Icons.tune,
            title: 'ReadyUI with options',
            subtitle: 'Total, BIN detection, billing, confirm step',
            onTap: tap('ReadyUI with options', _readyUIWithOptions),
          ),
          PaymentTile(
            icon: Icons.credit_card,
            title: 'Card form only',
            subtitle: 'Single-brand checkout (CARD)',
            onTap: tap('Card form', () => _singleBrand('CARD')),
          ),
          PaymentTile(
            icon: Icons.phone_iphone,
            title: 'STC Pay only',
            subtitle: 'Single-brand checkout (STC_PAY)',
            onTap: tap('STC Pay', () => _singleBrand('STC_PAY')),
          ),
          PaymentTile(
            icon: Icons.bookmark,
            title: 'Pay with stored token',
            subtitle: 'getCheckoutInfo + payWithToken',
            onTap: tap('Stored token', _payWithStoredToken),
          ),
          PaymentTile(
            icon: Icons.save,
            title: 'Save card without paying',
            subtitle: 'registerCard',
            onTap: tap('Register card', _registerCard),
          ),
          PaymentTile(
            icon: Icons.rule,
            title: 'Validate card fields',
            subtitle: 'Native SDK validators',
            onTap: tap('Validate', _validateCard),
          ),
          PaymentTile(
            icon: Icons.security,
            title: 'Device checks',
            subtitle: '3DS security warnings, Apple Pay availability',
            onTap: tap('Device checks', _threeDSWarnings),
          ),
          const SizedBox(height: 16),
          StatusCard(status: _status, isLoading: _isLoading, isSuccess: false),
        ],
      ),
    );
  }
}
