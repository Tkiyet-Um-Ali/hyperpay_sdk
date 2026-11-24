import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperpay_sdk_example/tua_checkout/card_input.dart';

TextEditingValue _type(TextInputFormatter f, String old, String next) =>
    f.formatEditUpdate(
      TextEditingValue(text: old),
      TextEditingValue(text: next),
    );

void main() {
  test('card number keeps digits only and caps the length', () {
    final f = CardNumberFormatter();
    expect(_type(f, '', '4200abc0000-0000 0000 9999').text,
        '4200 0000 0000 0000');
    expect(_type(f, '', '377777777777770123').text, '3777 777777 77770');
  });

  test('deleting a separator deletes the digit before it', () {
    expect(_type(CardNumberFormatter(), '4200 1', '42001').text, '4200');
    expect(_type(ExpiryFormatter(), '05 / 3', '05 /3').text, '05');
  });

  test('brand detection', () {
    expect(CardBrand.detect('4200'), CardBrand.visa);
    expect(CardBrand.detect('5123'), CardBrand.master);
    expect(CardBrand.detect('2221'), CardBrand.master);
    expect(CardBrand.detect('3777'), CardBrand.amex);
    expect(CardBrand.detect('6011'), isNull);
  });

  test('Luhn', () {
    expect(passesLuhn('4200000000000000'), isTrue);
    expect(passesLuhn('377777777777770'), isTrue);
    expect(passesLuhn('4200000000000001'), isFalse);
  });

  test('holder name accepts English letters only', () {
    expect(holderPattern.hasMatch("Sara O'Neil-Haddad Jr."), isTrue);
    expect(holderPattern.hasMatch('سارة حداد'), isFalse);
    expect(holderPattern.hasMatch('Sara 2'), isFalse);
    expect(holderPattern.hasMatch(' Sara'), isFalse);
  });
}
