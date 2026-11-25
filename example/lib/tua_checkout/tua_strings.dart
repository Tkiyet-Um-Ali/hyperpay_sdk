import 'package:flutter/widgets.dart';

/// English and Arabic copy for the TUA checkout.
class TuaStrings {
  final String locale;
  const TuaStrings(this.locale);

  bool get isArabic => locale == 'ar';
  TextDirection get direction =>
      isArabic ? TextDirection.rtl : TextDirection.ltr;

  String _t(String en, String ar) => isArabic ? ar : en;

  String get title => _t('Donate', 'تبرّع');
  String get cardNumber => _t('Card number', 'رقم البطاقة');
  String get cardHolder => _t('Name on card', 'الاسم على البطاقة');
  String get expiry => _t('Expiry', 'تاريخ الانتهاء');
  String get cvv => _t('CVV', 'رمز CVV');
  String get cardHolderPlaceholder =>
      _t('As printed on the card', 'كما هو مطبوع على البطاقة');
  String get expiryPlaceholder => _t('MM / YY', 'MM / YY');

  String currency(String? code) =>
      (code == null || code == 'JOD') ? _t('JOD', 'د.أ') : code;

  String pay(String amount, String? code) => isArabic
      ? 'تبرّع بـ $amount ${currency(code)}'
      : 'Donate $amount ${currency(code)}';

  String summaryHead(int programs) => isArabic
      ? 'تبرّعك · ${programs > 1 ? '$programs برامج' : 'برنامج واحد'}'
      : 'Your donation · $programs ${programs == 1 ? 'program' : 'programs'}';
  String get total => _t('Total', 'المجموع');
  String more(int n) => isArabic
      ? (n == 1
          ? '+ برنامج آخر'
          : n == 2
              ? '+ برنامجان آخران'
              : '+ $n برامج أخرى')
      : '+$n more ${n == 1 ? 'program' : 'programs'}';
  String get less => _t('Show fewer', 'عرض أقل');

  String get trust => _t(
        'Card details go straight to HyperPay. We never see them.',
        'تُرسل بيانات البطاقة مباشرة إلى HyperPay ولا نطّلع عليها.',
      );
  String get orByCard => _t('or donate by card', 'أو تبرّع بالبطاقة');
  String get donateWith => _t('Donate with', 'تبرّع عبر');
  String get processing => _t('Processing…', 'جارٍ المعالجة…');
  String get paid => _t('Paid. Thank you', 'تم الدفع، شكراً لك');

  String get cardNumberError =>
      _t('Invalid card number or brand', 'رقم البطاقة غير صحيح');
  String get cardNotAccepted =>
      _t('This card type isn\'t accepted', 'نوع البطاقة هذا غير مقبول');
  String get cardHolderError => _t(
      'Enter the name exactly as on the card', 'أدخل الاسم كما هو على البطاقة');
  String get cardHolderEnglishOnly => _t(
      'Use English letters, as printed on the card',
      'استخدم الأحرف الإنجليزية كما هي مطبوعة على البطاقة');
  String get saveCard => _t('Save this card for future donations',
      'احفظ هذه البطاقة للتبرعات القادمة');
  String get expiryError =>
      _t('Invalid expiry date', 'تاريخ الانتهاء غير صحيح');
  String get cvvError => _t('Invalid CVV', 'رمز CVV غير صحيح');
  String cvvHint({required bool amex}) => amex
      ? _t('4 digits on the front of your Amex', '4 أرقام على وجه بطاقة Amex')
      : _t('3 digits on the back', '3 أرقام على ظهر البطاقة');

  String get loadError =>
      _t('We couldn\'t start the payment.', 'تعذّر بدء عملية الدفع.');
  String get tryAgain => _t('Try again', 'حاول مجدداً');
  String get paymentFailed => _t(
        'The payment didn\'t go through. Check the card details or try another card.',
        'لم تتم عملية الدفع. تحقّق من بيانات البطاقة أو جرّب بطاقة أخرى.',
      );
  String get declinedTitle =>
      _t('Payment not completed', 'لم تكتمل عملية الدفع');
}
