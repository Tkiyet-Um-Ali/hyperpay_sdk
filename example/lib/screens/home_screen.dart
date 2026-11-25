import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hyperpay_sdk/hyperpay_sdk.dart';
import 'package:hyperpay_sdk/tua_checkout.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../saved_cards_screen.dart';
import '../services/payment_service.dart';
import '../services/tua_api.dart';
import 'advanced_screen.dart';
import '../widgets/custom_ui_bottom_sheet.dart';
import '../widgets/payment_tile.dart';
import '../widgets/status_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _amountController = TextEditingController(text: '10.00');
  String _status = 'SDK initialized (test mode)';
  bool _isLoading = false;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _showResultSnackBar(PaymentResult result) {
    if (!mounted) return;
    final isSuccess = result.isSuccess;
    final isCanceled = result.isCanceled;
    final message = isSuccess
        ? 'Payment successful! (${result.transactionType})'
        : isCanceled
            ? 'Payment canceled'
            : 'Payment failed: ${result.errorMessage ?? result.errorCode}';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isSuccess
            ? Colors.green
            : isCanceled
                ? null
                : Colors.red,
      ),
    );
  }

  Future<void> _openTuaCheckout(
    String locale, {
    bool showItems = true,
    bool allowSaveCard = false,
  }) async {
    String? env(String key) {
      final value = dotenv.env[key]?.trim();
      return value == null || value.isEmpty ? null : value;
    }

    final result = await TuaCheckoutScreen.open(
      context,
      backend: TuaApi.checkoutBackend(),
      shopperResultUrl: PaymentService.shopperResultUrl,
      locale: locale,
      showItems: showItems,
      allowSaveCard: allowSaveCard,
      applePayMerchantId: env('TUA_APPLE_PAY_MERCHANT_ID'),
      googlePayGatewayMerchantId: env('TUA_GOOGLE_PAY_GATEWAY_MERCHANT_ID'),
    );
    if (!mounted) return;
    if (result == null) {
      setState(() => _status = 'TUA checkout closed without paying');
      return;
    }
    setState(() => _status = result.isPaid
        ? 'Paid · ${result.reference ?? result.paymentId}'
        : 'Not paid (${result.payment?.status ?? 'unconfirmed'})');
    _showResultSnackBar(result.isPaid
        ? result.sdkResult
        : PaymentResult.error(
            errorCode: result.payment?.status ?? 'UNCONFIRMED',
            errorMessage: result.payment?.failureMessage ?? 'Not paid',
          ));
  }

  Future<void> _payReadyUI() async {
    final themeColor = Theme.of(context).colorScheme.primary.toARGB32();

    setState(() {
      _isLoading = true;
      _status = 'Requesting checkout ID...';
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedIds = prefs.getStringList('saved_registration_ids') ?? [];
      final checkoutId = await PaymentService.getCheckoutId(
        amount: _amountController.text.trim(),
        registrationIds: savedIds,
      );
      if (checkoutId == null) return;

      setState(() => _status = 'Checkout ID: $checkoutId');
      final sdkResult = await HyperpaySdk.checkoutReadyUI(
        checkoutId: checkoutId,
        brands: PaymentService.checkoutBrands,
        shopperResultUrl: PaymentService.shopperResultUrl,
        themeColor: themeColor,
      );
      final result = await PaymentService.completePayment(sdkResult);
      setState(() => _status = PaymentService.formatResult(result));
      _showResultSnackBar(result);
    } catch (e) {
      setState(() => _status = 'ReadyUI error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _openCustomUI() {
    CustomUIBottomSheet.show(
      context: context,
      amount: _amountController.text.trim(),
      onPaymentComplete: (result, statusText) {
        setState(() => _status = statusText);
        _showResultSnackBar(result);
      },
    );
  }

  Future<void> _payApplePay() async {
    setState(() {
      _isLoading = true;
      _status = 'Requesting checkout ID...';
    });

    try {
      final checkoutId = await PaymentService.getCheckoutId(
        amount: _amountController.text.trim(),
      );
      if (checkoutId == null) return;

      setState(() => _status = 'Checkout ID: $checkoutId');

      final sdkResult = await HyperpaySdk.payApplePay(
        checkoutId: checkoutId,
        merchantId: 'merchant.com.example.app',
        countryCode: 'SA',
        currencyCode: 'SAR',
        amount: double.tryParse(_amountController.text.trim()) ?? 10.0,
        companyName: 'Example Company',
        shopperResultUrl: PaymentService.shopperResultUrl,
      );
      final result = await PaymentService.completePayment(sdkResult);
      setState(() => _status = PaymentService.formatResult(result));
      _showResultSnackBar(result);
    } catch (e) {
      setState(() => _status = 'Apple Pay error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('HyperPay SDK Example')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _amountController,
            decoration: const InputDecoration(
              labelText: 'Amount (SAR)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.attach_money),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
          if (TuaApi.isConfigured) ...[
            PaymentTile(
              icon: Icons.volunteer_activism,
              title: 'TUA checkout',
              subtitle: 'English · program list · save-card option',
              onTap: _isLoading
                  ? null
                  : () => _openTuaCheckout('en', allowSaveCard: true),
            ),
            PaymentTile(
              icon: Icons.translate,
              title: 'TUA checkout (العربية)',
              subtitle: 'Arabic, right to left · total only',
              onTap: _isLoading
                  ? null
                  : () => _openTuaCheckout('ar', showItems: false),
            ),
          ],
          PaymentTile(
            icon: Icons.storefront,
            title: 'ReadyUI Checkout',
            subtitle: 'Pre-built payment screen',
            onTap: _isLoading ? null : _payReadyUI,
          ),
          PaymentTile(
            icon: Icons.credit_card,
            title: 'Custom Card Payment',
            subtitle: 'Enter card details manually',
            onTap: _isLoading ? null : _openCustomUI,
          ),
          if (Platform.isIOS)
            PaymentTile(
              icon: Icons.apple,
              title: 'Apple Pay',
              subtitle: 'Pay with Apple Pay',
              onTap: _isLoading ? null : _payApplePay,
            ),
          PaymentTile(
            icon: Icons.wallet,
            title: 'Saved Cards',
            subtitle: 'Manage tokenized cards',
            onTap: _isLoading
                ? null
                : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const SavedCardsScreen()),
                    ),
          ),
          PaymentTile(
            icon: Icons.science,
            title: 'Advanced features',
            subtitle: 'Options, tokens, registration, validation',
            onTap: _isLoading
                ? null
                : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AdvancedScreen(
                            amount: _amountController.text.trim()),
                      ),
                    ),
          ),
          const SizedBox(height: 16),
          StatusCard(
            status: _status,
            isLoading: _isLoading,
            isSuccess: _status.startsWith('SDK initialized'),
          ),
        ],
      ),
    );
  }
}
