import 'dart:math';

import 'package:flutter/services.dart';

/// Card brands the TUA form recognises from the number as it is typed.
enum CardBrand {
  visa('VISA', 'VISA'),
  master('MASTER', 'MASTERCARD'),
  amex('AMEX', 'AMEX');

  const CardBrand(this.hyperpayBrand, this.label);

  /// Brand code HyperPay expects.
  final String hyperpayBrand;

  /// Shown inside the card-number field.
  final String label;

  static CardBrand? detect(String digits) {
    if (RegExp(r'^3[47]').hasMatch(digits)) return amex;
    if (digits.startsWith('4')) return visa;
    if (RegExp(r'^(5[1-5]|2[2-7])').hasMatch(digits)) return master;
    return null;
  }
}

String digitsOnly(String text) => text.replaceAll(RegExp(r'\D'), '');

/// Shared behaviour: keep digits only, re-group them, and when the user
/// deletes a separator, delete the digit before it instead (otherwise the
/// separator would come straight back).
abstract class _GroupingFormatter extends TextInputFormatter {
  String format(String digits);

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = digitsOnly(newValue.text);
    if (newValue.text.length < oldValue.text.length &&
        digits == digitsOnly(oldValue.text) &&
        digits.isNotEmpty) {
      digits = digits.substring(0, digits.length - 1);
    }
    final text = format(digits);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// `4200 0000 0000 0000`, or `3777 777777 77770` (4-6-5) for Amex.
class CardNumberFormatter extends _GroupingFormatter {
  @override
  String format(String digits) {
    final amex = CardBrand.detect(digits) == CardBrand.amex;
    final d = digits.substring(0, min(digits.length, amex ? 15 : 16));
    final groups = amex ? const [4, 6, 5] : const [4, 4, 4, 4];
    final parts = <String>[];
    var i = 0;
    for (final size in groups) {
      if (i >= d.length) break;
      parts.add(d.substring(i, min(i + size, d.length)));
      i += size;
    }
    return parts.join(' ');
  }
}

/// `MM / YY`.
class ExpiryFormatter extends _GroupingFormatter {
  @override
  String format(String digits) {
    final d = digits.substring(0, min(digits.length, 4));
    return d.length > 2 ? '${d.substring(0, 2)} / ${d.substring(2)}' : d;
  }
}

/// Name on card: English letters, spaces and `. ' -`, starting with a letter.
final holderPattern = RegExp(r"^[A-Za-z][A-Za-z .'-]*$");

/// Luhn checksum, which every Visa, Mastercard and Amex number passes.
bool passesLuhn(String digits) {
  var sum = 0;
  var double = false;
  for (var i = digits.length - 1; i >= 0; i--) {
    var d = digits.codeUnitAt(i) - 48;
    if (d < 0 || d > 9) return false;
    if (double) {
      d *= 2;
      if (d > 9) d -= 9;
    }
    sum += d;
    double = !double;
  }
  return digits.isNotEmpty && sum % 10 == 0;
}
