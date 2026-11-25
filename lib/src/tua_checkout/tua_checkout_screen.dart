import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../hyperpay_sdk.dart';
import 'card_input.dart';
import 'tua_backend.dart';
import 'tua_checkout_session.dart';
import 'tua_models.dart';
import 'tua_strings.dart';
import 'tua_theme.dart';

/// Ready-to-use TUA donation checkout: the donation summary, Apple Pay /
/// Google Pay when the checkout offers them, and a validated card form that
/// pays with [HyperpaySdk.payCustomUI]. Checkouts come from the Tua backend
/// through [backend]; every result is confirmed with it before the screen
/// reports success.
///
/// Call `HyperpaySdk.setup(mode:)` first, with the mode the backend's
/// checkouts use.
///
/// ```dart
/// final result = await TuaCheckoutScreen.open(
///   context,
///   backend: TuaRestBackend(send: mySend, checkoutBody: cart.toBody),
///   shopperResultUrl: 'com.example.app.payments',
///   locale: 'ar',
/// );
/// if (result?.isPaid == true) showThankYou(result!.reference);
/// ```
class TuaCheckoutScreen extends StatefulWidget {
  const TuaCheckoutScreen({
    super.key,
    required this.backend,
    required this.shopperResultUrl,
    this.locale = 'en',
    this.showItems = true,
    this.allowSaveCard = false,
    this.applePayMerchantId,
    this.googlePayGatewayMerchantId,
    this.merchantName = 'Tkiyet Um Ali',
    this.countryCode = 'JO',
    this.onOpenCheckouts,
  });

  /// The Tua backend calls, made with your app's authenticated client.
  final TuaCheckoutBackend backend;

  /// Your app's payment return URL scheme (used for 3-D Secure redirects).
  final String shopperResultUrl;

  /// `en` or `ar` (right to left). The donor can switch from the top bar.
  final String locale;

  /// Lists the donation's program lines above the total. With several lines
  /// the first is shown and an arrow expands the rest. `false` shows only the
  /// total, e.g. when your app already showed the cart.
  final bool showItems;

  /// Shows a "Save this card for future donations" checkbox. When ticked the
  /// card is registered with HyperPay along with the payment (`tokenize`);
  /// your backend reads the registration ID from the payment result.
  final bool allowSaveCard;

  /// Shows Apple Pay (iOS) when set and the checkout offers `APPLEPAY`.
  final String? applePayMerchantId;

  /// Shows Google Pay (Android) when set and the checkout offers `GOOGLEPAY`.
  /// The HyperPay entity ID that receives Google Pay payments.
  final String? googlePayGatewayMerchantId;

  /// Shown on the Apple Pay / Google Pay sheets.
  final String merchantName;
  final String countryCode;

  /// Decides what happens when the donor already has unfinished donations
  /// (`payments.too_many_open_checkouts`). By default the screen asks the
  /// donor to continue one or start over.
  final TuaOpenCheckoutsHandler? onOpenCheckouts;

  /// Pushes the screen and returns the result, or `null` when the donor
  /// leaves without paying. Use [TuaCheckoutResult.isPaid]: it is confirmed
  /// by the backend.
  static Future<TuaCheckoutResult?> open(
    BuildContext context, {
    required TuaCheckoutBackend backend,
    required String shopperResultUrl,
    String locale = 'en',
    bool showItems = true,
    bool allowSaveCard = false,
    String? applePayMerchantId,
    String? googlePayGatewayMerchantId,
    String merchantName = 'Tkiyet Um Ali',
    String countryCode = 'JO',
    TuaOpenCheckoutsHandler? onOpenCheckouts,
  }) {
    return Navigator.of(context).push<TuaCheckoutResult>(
      MaterialPageRoute(
        builder: (_) => TuaCheckoutScreen(
          backend: backend,
          shopperResultUrl: shopperResultUrl,
          locale: locale,
          showItems: showItems,
          allowSaveCard: allowSaveCard,
          applePayMerchantId: applePayMerchantId,
          googlePayGatewayMerchantId: googlePayGatewayMerchantId,
          merchantName: merchantName,
          countryCode: countryCode,
          onOpenCheckouts: onOpenCheckouts,
        ),
      ),
    );
  }

  @override
  State<TuaCheckoutScreen> createState() => _TuaCheckoutScreenState();
}

enum _Field { number, holder, expiry, cvv }

enum _PayState { idle, processing, paid }

class _TuaCheckoutScreenState extends State<TuaCheckoutScreen> {
  late String _locale = widget.locale;
  TuaStrings get _s => TuaStrings(_locale);

  late final _session = TuaCheckoutSession(widget.backend);
  TuaCheckout? _checkout;
  TuaPayment? _payment;
  bool _loading = true;
  String? _loadError;
  bool _showAllLines = false;

  final _number = TextEditingController();
  final _holder = TextEditingController();
  final _expiry = TextEditingController();
  final _cvv = TextEditingController();
  CardBrand? _brand;
  bool _saveCard = false;
  final Map<_Field, String> _errors = {};

  _PayState _payState = _PayState.idle;
  String? _wallet; // wallet being paid with, if any
  String? _declined;

  @override
  void initState() {
    super.initState();
    _number.addListener(_onNumberChanged);
    _load();
  }

  @override
  void dispose() {
    _number.dispose();
    _holder.dispose();
    _expiry.dispose();
    _cvv.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- data

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final checkout = await _session.start(
        onOpenCheckouts: widget.onOpenCheckouts ?? _askOpenCheckouts,
      );
      final payment = await _readPayment(checkout);
      if (!mounted) return;
      setState(() {
        _checkout = checkout;
        _payment = payment;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = _messageFor(e);
        _loading = false;
      });
    }
  }

  String _messageFor(Object e) {
    if (e is TuaOpenCheckoutsException && e.retryAfterSeconds != null) {
      return '${e.message} ${_s.tryAgainIn(e.retryAfterSeconds!)}';
    }
    if (e is TuaBackendException) return e.message;
    debugPrint('[TuaCheckout] $e');
    return _s.paymentFailed;
  }

  /// Asks the donor what to do with their unfinished donations.
  Future<TuaOpenCheckoutChoice> _askOpenCheckouts(
    List<TuaOpenCheckout> open,
  ) async {
    if (!mounted) return TuaOpenCheckoutChoice.dismiss;
    final s = _s;
    final choice = await showDialog<TuaOpenCheckoutChoice>(
      context: context,
      builder: (ctx) => Theme(
        data: tuaTheme(ctx),
        child: Directionality(
          textDirection: s.direction,
          child: AlertDialog(
            backgroundColor: TuaColors.surface,
            title: Text(
              s.openCheckoutsTitle,
              style: TuaText.cairo(size: 18, weight: FontWeight.w700),
            ),
            content: Text(
              s.openCheckoutsBody,
              style: TuaText.cairo(size: 14, color: TuaColors.muted),
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.pop(ctx, TuaOpenCheckoutChoice.startOver),
                child: Text(
                  s.startOver,
                  style: TuaText.cairo(
                    size: 14,
                    weight: FontWeight.w600,
                    color: TuaColors.muted,
                  ),
                ),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.pop(ctx, TuaOpenCheckoutChoice.resume),
                child: Text(
                  s.continueDonation,
                  style: TuaText.cairo(
                    size: 14,
                    weight: FontWeight.w700,
                    color: TuaColors.brand,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return choice ?? TuaOpenCheckoutChoice.dismiss;
  }

  /// Program lines for the summary, in the current language. The summary
  /// falls back to the checkout's total if this read fails.
  Future<TuaPayment?> _readPayment(TuaCheckout checkout) async {
    final id = checkout.paymentId;
    if (id == null) return null;
    try {
      return await widget.backend.getPayment(id, locale: _locale);
    } catch (e) {
      debugPrint('[TuaCheckout] Could not read the payment lines: $e');
      return null;
    }
  }

  Future<void> _setLocale(String locale) async {
    setState(() => _locale = locale);
    final checkout = _checkout;
    if (checkout == null) return;
    final payment = await _readPayment(checkout);
    if (mounted && payment != null) setState(() => _payment = payment);
  }

  num? get _amount => _payment?.amount ?? _checkout?.amount;
  String? get _currency => _payment?.currency ?? _checkout?.currency;
  String get _amountText => (_amount ?? 0).toStringAsFixed(2);

  // ---------------------------------------------------------------- card

  void _onNumberChanged() {
    final brand = CardBrand.detect(digitsOnly(_number.text));
    if (brand == _brand) return;
    setState(() {
      _brand = brand;
      final maxCvv = brand == CardBrand.amex ? 4 : 3;
      if (_cvv.text.length > maxCvv) {
        _cvv.text = _cvv.text.substring(0, maxCvv);
      }
    });
  }

  void _clearError(_Field field) {
    if (_errors.containsKey(field) || _declined != null) {
      setState(() {
        _errors.remove(field);
        _declined = null;
      });
    }
  }

  /// Checks the fields locally and with the SDK's validators. Returns the
  /// errors (empty when the card can be submitted).
  Future<Map<_Field, String>> _validate() async {
    final errors = <_Field, String>{};
    final digits = digitsOnly(_number.text);
    final brand = CardBrand.detect(digits);
    final expiry = digitsOnly(_expiry.text);
    final month = expiry.length == 4 ? int.parse(expiry.substring(0, 2)) : 0;
    final year = expiry.length == 4 ? 2000 + int.parse(expiry.substring(2)) : 0;
    final now = DateTime.now();

    if (brand == null ||
        digits.length != (brand == CardBrand.amex ? 15 : 16) ||
        !passesLuhn(digits)) {
      errors[_Field.number] = _s.cardNumberError;
    } else if (!_accepts(brand)) {
      errors[_Field.number] = _s.cardNotAccepted;
    }
    final holderError = _holderError(_holder.text, onSubmit: true);
    if (holderError != null) errors[_Field.holder] = holderError;
    if (month < 1 ||
        month > 12 ||
        year < now.year ||
        (year == now.year && month < now.month)) {
      errors[_Field.expiry] = _s.expiryError;
    }
    if (!RegExp(r'^\d+$').hasMatch(_cvv.text) ||
        _cvv.text.length != (brand == CardBrand.amex ? 4 : 3)) {
      errors[_Field.cvv] = _s.cvvError;
    }

    if (!errors.containsKey(_Field.number) ||
        !errors.containsKey(_Field.holder)) {
      try {
        final result = await HyperpaySdk.validateCard(
          number: digits,
          holder: _holder.text.trim(),
          brand: brand?.hyperpayBrand,
        );
        if (result.numberValid == false) {
          errors.putIfAbsent(_Field.number, () => _s.cardNumberError);
        }
        if (result.holderValid == false) {
          errors.putIfAbsent(_Field.holder, () => _s.cardHolderError);
        }
      } catch (e) {
        debugPrint('[TuaCheckout] validateCard failed: $e');
      }
    }
    return errors;
  }

  /// Card holder: English letters, spaces and `. ' -` only, as embossed on
  /// the card. While typing only the characters are checked; on submit the
  /// name must also have at least two letters.
  String? _holderError(String value, {bool onSubmit = false}) {
    final name = value.trim();
    if (name.isNotEmpty && !holderPattern.hasMatch(name)) {
      return _s.cardHolderEnglishOnly;
    }
    if (onSubmit && name.replaceAll(RegExp(r'[^A-Za-z]'), '').length < 2) {
      return _s.cardHolderError;
    }
    return null;
  }

  /// Amex pays through its own checkout (`hyperpay.amex`); other brands must
  /// be in the checkout's brand list.
  bool _accepts(CardBrand brand) {
    final checkout = _checkout;
    if (checkout == null) return false;
    if (brand == CardBrand.amex) return checkout.amexCheckoutId != null;
    return checkout.brands.contains(brand.hyperpayBrand);
  }

  // ---------------------------------------------------------------- pay

  Future<void> _payByCard() async {
    if (_payState != _PayState.idle) return;
    FocusScope.of(context).unfocus();
    setState(() => _declined = null);

    final errors = await _validate();
    if (!mounted) return;
    setState(() {
      _errors
        ..clear()
        ..addAll(errors);
    });
    if (errors.isNotEmpty) return;

    final brand = CardBrand.detect(digitsOnly(_number.text))!;
    final expiry = digitsOnly(_expiry.text);
    await _pay(
      (checkout) => HyperpaySdk.payCustomUI(
        checkoutId: brand == CardBrand.amex
            ? checkout.amexCheckoutId!
            : checkout.checkoutId,
        brand: brand.hyperpayBrand,
        cardNumber: digitsOnly(_number.text),
        holder: _holder.text.trim(),
        expiryMonth: expiry.substring(0, 2),
        expiryYear: '20${expiry.substring(2)}',
        cvv: _cvv.text,
        shopperResultUrl: widget.shopperResultUrl,
        tokenize: widget.allowSaveCard && _saveCard,
      ),
    );
  }

  Future<void> _payWithWallet(String brand) async {
    if (_payState != _PayState.idle) return;
    final amount = (_amount ?? 0).toDouble();
    final currency = _currency ?? 'JOD';
    setState(() {
      _wallet = brand;
      _declined = null;
    });
    await _pay(
      (checkout) => HyperpaySdk.checkoutReadyUI(
        checkoutId: checkout.checkoutId,
        brands: [brand],
        paymentBrand: brand,
        lang: _locale,
        shopperResultUrl: widget.shopperResultUrl,
        applePayConfig: brand == 'APPLEPAY'
            ? ApplePayConfig(
                merchantId: widget.applePayMerchantId!,
                countryCode: widget.countryCode,
                currencyCode: currency,
                amount: amount,
                companyName: widget.merchantName,
                supportedNetworks: const ['amex', 'masterCard', 'visa'],
              )
            : null,
        googlePayConfig: brand == 'GOOGLEPAY'
            ? GooglePayConfig(
                gatewayMerchantId: widget.googlePayGatewayMerchantId!,
                merchantName: widget.merchantName,
                countryCode: widget.countryCode,
                totalPrice: amount,
                currencyCode: currency,
                allowedCardNetworks: const ['AMEX', 'MASTERCARD', 'VISA'],
              )
            : null,
      ),
    );
    if (mounted) setState(() => _wallet = null);
  }

  /// Runs one payment attempt and confirms it with the backend.
  Future<void> _pay(
    Future<PaymentResult> Function(TuaCheckout checkout) submit,
  ) async {
    setState(() => _payState = _PayState.processing);
    try {
      final checkout =
          _session.checkout ??
          await _session.start(
            onOpenCheckouts: widget.onOpenCheckouts ?? _askOpenCheckouts,
          );
      _checkout = checkout;
      final sdkResult = await submit(checkout);
      if (sdkResult.isCanceled) {
        if (mounted) setState(() => _payState = _PayState.idle);
        return;
      }
      final result = await _session.finish(sdkResult, locale: _locale);
      if (!mounted) return;
      if (result.isPaid) {
        HapticFeedback.mediumImpact();
        setState(() => _payState = _PayState.paid);
        await Future<void>.delayed(const Duration(milliseconds: 1600));
        if (mounted) Navigator.of(context).pop(result);
        return;
      }
      final payment = result.payment;
      if (payment?.failureMessage == null) {
        debugPrint(
          '[TuaCheckout] Not paid: status=${payment?.status} '
          'sdk=${sdkResult.errorCode} ${sdkResult.errorMessage}',
        );
      }
      setState(() {
        _payState = _PayState.idle;
        _declined =
            payment?.failureMessage ??
            (payment != null &&
                    (payment.status == 'processing' ||
                        payment.status == 'review' ||
                        (payment.status == 'pending' && sdkResult.isSuccess))
                ? _s.notConfirmed
                : _s.paymentFailed);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _payState = _PayState.idle;
        _declined = _messageFor(e);
      });
    }
  }

  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return Theme(
      data: tuaTheme(context),
      child: Directionality(
        textDirection: s.direction,
        child: Scaffold(
          appBar: AppBar(
            title: Text(s.title),
            actions: [
              TextButton(
                onPressed: _payState == _PayState.idle
                    ? () => _setLocale(s.isArabic ? 'en' : 'ar')
                    : null,
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                child: Text(
                  s.isArabic ? 'English' : 'العربية',
                  style: TuaText.cairo(
                    size: 14,
                    weight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          body: _body(s),
        ),
      ),
    );
  }

  Widget _body(TuaStrings s) {
    if (_loadError != null) {
      return _LoadError(s: s, message: _loadError!, onRetry: _load);
    }
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _Summary(
            s: s,
            payment: _payment,
            amount: _loading ? null : _amountText,
            currency: _currency,
            showItems: widget.showItems,
            showAll: _showAllLines,
            onToggle: () => setState(() => _showAllLines = !_showAllLines),
          ),
          if (_loading)
            const _FormSkeleton()
          else
            SafeArea(
              top: false,
              left: false,
              right: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 20),
                child: _form(s),
              ),
            ),
        ],
      ),
    );
  }

  List<String> get _wallets {
    final checkout = _checkout;
    if (checkout == null) return const [];
    return [
      if (Platform.isIOS &&
          widget.applePayMerchantId != null &&
          checkout.brands.contains('APPLEPAY'))
        'APPLEPAY',
      if (Platform.isAndroid &&
          widget.googlePayGatewayMerchantId != null &&
          checkout.brands.contains('GOOGLEPAY'))
        'GOOGLEPAY',
    ];
  }

  Widget _form(TuaStrings s) {
    final amex = _brand == CardBrand.amex;
    final busy = _payState != _PayState.idle;
    final wallets = _wallets;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (wallets.isNotEmpty) ...[
          const SizedBox(height: 14),
          for (final w in wallets) ...[
            _WalletButton(
              brand: w,
              label: s.donateWith,
              busy: _wallet == w && busy,
              paid: _wallet == w && _payState == _PayState.paid,
              s: s,
              onPressed: busy ? null : () => _payWithWallet(w),
            ),
            const SizedBox(height: 10),
          ],
          _OrDivider(text: s.orByCard),
        ],
        const SizedBox(height: 14),
        _TuaField(
          label: s.cardNumber,
          controller: _number,
          hint: '0000 0000 0000 0000',
          error: _errors[_Field.number],
          ltr: true,
          keyboardType: TextInputType.number,
          formatters: [CardNumberFormatter()],
          autofillHints: const [AutofillHints.creditCardNumber],
          letterSpacing: 1,
          enabled: !busy,
          trailing: _brand?.label,
          onChanged: (_) => _clearError(_Field.number),
        ),
        const SizedBox(height: 16),
        _TuaField(
          label: s.cardHolder,
          controller: _holder,
          hint: s.cardHolderPlaceholder,
          error: _errors[_Field.holder],
          keyboardType: TextInputType.name,
          textCapitalization: TextCapitalization.words,
          autofillHints: const [AutofillHints.creditCardName],
          enabled: !busy,
          onChanged: (value) {
            final error = _holderError(value);
            setState(() {
              _declined = null;
              if (error == null) {
                _errors.remove(_Field.holder);
              } else {
                _errors[_Field.holder] = error;
              }
            });
          },
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _TuaField(
                label: s.expiry,
                controller: _expiry,
                hint: s.expiryPlaceholder,
                error: _errors[_Field.expiry],
                ltr: true,
                keyboardType: TextInputType.number,
                formatters: [ExpiryFormatter()],
                autofillHints: const [AutofillHints.creditCardExpirationDate],
                enabled: !busy,
                onChanged: (_) => _clearError(_Field.expiry),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _TuaField(
                label: s.cvv,
                controller: _cvv,
                hint: amex ? '1234' : '123',
                error: _errors[_Field.cvv],
                helper: s.cvvHint(amex: amex),
                ltr: true,
                keyboardType: TextInputType.number,
                formatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(amex ? 4 : 3),
                ],
                autofillHints: const [AutofillHints.creditCardSecurityCode],
                letterSpacing: 3,
                enabled: !busy,
                onChanged: (_) => _clearError(_Field.cvv),
              ),
            ),
          ],
        ),
        if (widget.allowSaveCard) ...[
          const SizedBox(height: 12),
          _SaveCardToggle(
            label: s.saveCard,
            value: _saveCard,
            onChanged: busy ? null : (v) => setState(() => _saveCard = v),
          ),
        ],
        if (_declined != null) ...[
          const SizedBox(height: 16),
          _DeclinedBanner(title: s.declinedTitle, message: _declined!),
        ],
        const SizedBox(height: 20),
        _PayButton(
          label: s.pay(_amountText, _currency),
          processing: s.processing,
          paid: s.paid,
          state: _wallet == null ? _payState : _PayState.idle,
          enabled: !busy,
          onPressed: _payByCard,
        ),
        const SizedBox(height: 16),
        _Trust(text: s.trust),
      ],
    );
  }
}

// ------------------------------------------------------------------ summary

class _Summary extends StatelessWidget {
  const _Summary({
    required this.s,
    required this.payment,
    required this.amount,
    required this.currency,
    required this.showItems,
    required this.showAll,
    required this.onToggle,
  });

  final TuaStrings s;
  final TuaPayment? payment;
  final String? amount;
  final String? currency;
  final bool showItems;
  final bool showAll;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final lines = showItems
        ? payment?.lines ?? const <TuaPaymentLine>[]
        : const <TuaPaymentLine>[];
    // Several programs: show the first, the rest behind an arrow.
    final fold = lines.length > 1 && !showAll;
    final shown = fold ? lines.take(1).toList() : lines;
    const white78 = Color(0xC7FFFFFF);
    const white70 = Color(0xB3FFFFFF);

    return Container(
      color: TuaColors.hero,
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (lines.isNotEmpty)
            Text(
              s.summaryHead(lines.length),
              style: TuaText.cairo(
                size: 13,
                weight: FontWeight.w600,
                color: white78,
              ),
            ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: AlignmentDirectional.topStart,
            child: Column(
              children: [
                for (final line in shown)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                line.programName,
                                style: TuaText.cairo(
                                  size: 15,
                                  weight: FontWeight.w600,
                                  color: Colors.white,
                                  height: 1.4,
                                ),
                              ),
                              Text(
                                '${line.quantity} × ${line.unitAmount.toStringAsFixed(2)} ${s.currency(currency)}',
                                textDirection: TextDirection.ltr,
                                style: TuaText.cairo(
                                  size: 13,
                                  color: white70,
                                  features: TuaText.tabular,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          line.amount.toStringAsFixed(2),
                          style: TuaText.cairo(
                            size: 15,
                            weight: FontWeight.w600,
                            color: Colors.white,
                            features: TuaText.tabular,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (lines.length > 1)
            Semantics(
              button: true,
              expanded: !fold,
              child: InkWell(
                onTap: onToggle,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 2),
                  child: Row(
                    children: [
                      Text(
                        fold ? s.more(lines.length - 1) : s.less,
                        style: TuaText.cairo(
                          size: 13,
                          weight: FontWeight.w600,
                          color: TuaColors.accent,
                        ),
                      ),
                      const SizedBox(width: 4),
                      AnimatedRotation(
                        turns: fold ? 0 : .5,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(
                          Icons.keyboard_arrow_down,
                          size: 20,
                          color: TuaColors.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Container(
            margin: EdgeInsets.only(top: lines.isEmpty ? 0 : 10),
            padding: EdgeInsets.only(top: lines.isEmpty ? 0 : 12),
            decoration: lines.isEmpty
                ? null
                : const BoxDecoration(
                    border: Border(top: BorderSide(color: Color(0x2EFFFFFF))),
                  ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(s.total, style: TuaText.cairo(size: 14, color: white78)),
                const Spacer(),
                if (amount == null)
                  const _Bar(width: 120, height: 30, dark: true)
                else
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: amount,
                          style: TuaText.cairo(
                            size: 30,
                            weight: FontWeight.w800,
                            color: Colors.white,
                            height: 1.2,
                            features: TuaText.tabular,
                          ),
                        ),
                        TextSpan(
                          text: '  ${s.currency(currency)}',
                          style: TuaText.cairo(
                            size: 15,
                            weight: FontWeight.w600,
                            color: TuaColors.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ fields

class _TuaField extends StatefulWidget {
  const _TuaField({
    required this.label,
    required this.controller,
    this.hint,
    this.error,
    this.helper,
    this.ltr = false,
    this.keyboardType,
    this.formatters,
    this.autofillHints,
    this.textCapitalization = TextCapitalization.none,
    this.letterSpacing,
    this.trailing,
    this.enabled = true,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final String? error;
  final String? helper;

  /// Card digits and expiry stay left-to-right in Arabic.
  final bool ltr;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? formatters;
  final Iterable<String>? autofillHints;
  final TextCapitalization textCapitalization;
  final double? letterSpacing;

  /// Text pinned to the end of the field (the detected card brand).
  final String? trailing;
  final bool enabled;
  final ValueChanged<String>? onChanged;

  @override
  State<_TuaField> createState() => _TuaFieldState();
}

class _TuaFieldState extends State<_TuaField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasError = widget.error != null;
    final focused = _focus.hasFocus;
    final rtl = Directionality.of(context) == TextDirection.rtl;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            widget.label,
            style: TuaText.cairo(
              size: 13,
              weight: FontWeight.w600,
              color: TuaColors.ink2,
            ),
          ),
        ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 48,
          decoration: BoxDecoration(
            color: hasError
                ? TuaColors.errorBg
                : focused
                ? TuaColors.surface
                : TuaColors.field,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: hasError
                  ? TuaColors.error
                  : focused
                  ? TuaColors.brand
                  : TuaColors.line,
            ),
            boxShadow: focused && !hasError
                ? const [BoxShadow(color: TuaColors.accent, spreadRadius: 3)]
                : null,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              TextField(
                controller: widget.controller,
                focusNode: _focus,
                enabled: widget.enabled,
                keyboardType: widget.keyboardType,
                inputFormatters: widget.formatters,
                autofillHints: widget.autofillHints,
                textCapitalization: widget.textCapitalization,
                textDirection: widget.ltr ? TextDirection.ltr : null,
                textAlign: widget.ltr && rtl
                    ? TextAlign.right
                    : TextAlign.start,
                onChanged: widget.onChanged,
                style: TuaText.cairo(
                  size: 16, // 16px keeps iOS from zooming
                  color: TuaColors.ink2,
                  letterSpacing: widget.letterSpacing,
                  features: TuaText.tabular,
                ),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: widget.hint,
                  hintTextDirection: widget.ltr ? TextDirection.ltr : null,
                  hintStyle: TuaText.cairo(
                    size: 16,
                    color: TuaColors.muted,
                    letterSpacing: widget.letterSpacing,
                  ),
                  contentPadding: EdgeInsetsDirectional.only(
                    start: 14,
                    end: widget.trailing != null ? 96 : 14,
                  ),
                ),
              ),
              if (widget.trailing != null)
                PositionedDirectional(
                  end: 14,
                  child: IgnorePointer(
                    child: Text(
                      widget.trailing!,
                      style: TuaText.cairo(
                        size: 12,
                        weight: FontWeight.w700,
                        color: TuaColors.brand,
                        letterSpacing: .5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (widget.helper != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              widget.helper!,
              style: TuaText.cairo(size: 12, color: TuaColors.muted),
            ),
          ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              widget.error!,
              style: TuaText.cairo(
                size: 12,
                weight: FontWeight.w600,
                color: TuaColors.error,
              ),
            ),
          ),
      ],
    );
  }
}

// ------------------------------------------------------------------ buttons

class _Pressable extends StatefulWidget {
  const _Pressable({required this.child, required this.onPressed});
  final Widget child;
  final VoidCallback? onPressed;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  void _set(bool down) {
    if (widget.onPressed != null && down != _down) {
      setState(() => _down = down);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: widget.onPressed != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _down ? .96 : 1,
          duration: const Duration(milliseconds: 120),
          child: widget.child,
        ),
      ),
    );
  }
}

class _PayButton extends StatelessWidget {
  const _PayButton({
    required this.label,
    required this.processing,
    required this.paid,
    required this.state,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final String processing;
  final String paid;
  final _PayState state;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final style = TuaText.cairo(
      size: 16,
      weight: FontWeight.w700,
      color: TuaColors.brandInk,
    );
    final Widget content = switch (state) {
      _PayState.idle => Text(label, style: style),
      _PayState.processing => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _Spinner(color: TuaColors.brandInk),
          const SizedBox(width: 10),
          Text(processing, style: style),
        ],
      ),
      _PayState.paid => Text('✓ $paid', style: style),
    };
    return _Pressable(
      onPressed: enabled ? onPressed : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          // TUA app-size button: 48px tall, 14px corners.
          borderRadius: BorderRadius.circular(14),
          color: state == _PayState.paid
              ? TuaColors.ok
              : TuaColors.brand.withValues(
                  alpha: state == _PayState.processing ? .75 : 1,
                ),
        ),
        child: content,
      ),
    );
  }
}

class _WalletButton extends StatelessWidget {
  const _WalletButton({
    required this.brand,
    required this.label,
    required this.busy,
    required this.paid,
    required this.s,
    required this.onPressed,
  });

  final String brand;
  final String label;
  final bool busy;
  final bool paid;
  final TuaStrings s;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final google = brand == 'GOOGLEPAY';
    final ink = google ? const Color(0xFF3C4043) : Colors.black;
    final style = TuaText.cairo(size: 15, weight: FontWeight.w600, color: ink);
    return _Pressable(
      onPressed: onPressed,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: google ? const Color(0xFF747775) : Colors.black,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: paid
              ? [Text('✓ ${s.paid}', style: style)]
              : busy
              ? [
                  _Spinner(color: ink),
                  const SizedBox(width: 8),
                  Text(s.processing, style: style),
                ]
              : [
                  Text(label, style: style),
                  const SizedBox(width: 8),
                  Image.asset(
                    google
                        ? 'assets/tua/google_pay.png'
                        : 'assets/tua/apple_pay.png',
                    height: 22,
                    package: TuaText.fontPackage,
                    semanticLabel: google ? 'Google Pay' : 'Apple Pay',
                  ),
                ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ bits

class _OrDivider extends StatelessWidget {
  const _OrDivider({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          const Expanded(child: Divider(color: TuaColors.line, height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              text,
              style: TuaText.cairo(size: 13, color: TuaColors.muted),
            ),
          ),
          const Expanded(child: Divider(color: TuaColors.line, height: 1)),
        ],
      ),
    );
  }
}

class _DeclinedBanner extends StatelessWidget {
  const _DeclinedBanner({required this.title, required this.message});
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: TuaColors.errorBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: TuaColors.error.withValues(alpha: .35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, color: TuaColors.error, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TuaText.cairo(
                      size: 14,
                      weight: FontWeight.w700,
                      color: TuaColors.error,
                    ),
                  ),
                  Text(
                    message,
                    style: TuaText.cairo(size: 13, color: TuaColors.ink2),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Trust extends StatelessWidget {
  const _Trust({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 3),
          child: Icon(Icons.lock_outline, size: 13, color: TuaColors.muted),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TuaText.cairo(size: 12, color: TuaColors.muted),
          ),
        ),
      ],
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 16,
    height: 16,
    child: CircularProgressIndicator(strokeWidth: 2, color: color),
  );
}

class _Bar extends StatelessWidget {
  const _Bar({required this.width, required this.height, this.dark = false});
  final double width;
  final double height;
  final bool dark;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: dark ? const Color(0x26FFFFFF) : TuaColors.field,
      borderRadius: BorderRadius.circular(8),
    ),
  );
}

/// Same height as the form, so nothing jumps when the checkout arrives.
class _FormSkeleton extends StatelessWidget {
  const _FormSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget field() => const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Bar(width: 90, height: 14),
        SizedBox(height: 8),
        _Bar(width: double.infinity, height: 48),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
      child: Column(
        children: [
          field(),
          const SizedBox(height: 16),
          field(),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: field()),
              const SizedBox(width: 12),
              Expanded(child: field()),
            ],
          ),
          const SizedBox(height: 46),
          const _Bar(width: double.infinity, height: 48),
        ],
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({
    required this.s,
    required this.message,
    required this.onRetry,
  });
  final TuaStrings s;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 40, color: TuaColors.muted),
            const SizedBox(height: 12),
            Text(
              s.loadError,
              textAlign: TextAlign.center,
              style: TuaText.cairo(size: 17, weight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TuaText.cairo(size: 13, color: TuaColors.muted),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: 200,
              child: _PayButton(
                label: s.tryAgain,
                processing: s.processing,
                paid: s.paid,
                state: _PayState.idle,
                enabled: true,
                onPressed: onRetry,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SaveCardToggle extends StatelessWidget {
  const _SaveCardToggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: InkWell(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: value,
                  onChanged: onChanged == null
                      ? null
                      : (v) => onChanged!(v ?? false),
                  activeColor: TuaColors.brand,
                  side: const BorderSide(color: TuaColors.line, width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TuaText.cairo(size: 14, color: TuaColors.ink2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
