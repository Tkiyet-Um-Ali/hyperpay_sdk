/// Light or dark base style for the iOS Ready-UI checkout.
enum CheckoutThemeStyle { light, dark }

/// A font for the iOS checkout theme. [family] is a font family or
/// PostScript name registered in the app (e.g. a font bundled through
/// `pubspec.yaml` and listed in Info.plist `UIAppFonts`); `null` uses the
/// system font at [size].
class CheckoutFont {
  final String? family;
  final double size;
  final bool bold;

  const CheckoutFont({this.family, required this.size, this.bold = false});

  Map<String, dynamic> toMap() => {
    if (family != null) 'family': family,
    'size': size,
    'bold': bold,
  };
}

/// iOS Ready-UI checkout theme (`OPPCheckoutSettings.theme`). Colors are ARGB
/// ints, e.g. `Colors.teal.value` or `0xFF00897B`. Unset fields keep the SDK
/// default for [style].
///
/// Android checkout styling is done with an XML style resource instead; see
/// [CheckoutOptions.androidThemeResource].
class CheckoutTheme {
  final CheckoutThemeStyle? style;

  final int? primaryBackgroundColor;
  final int? primaryForegroundColor;
  final int? accentColor;
  final int? confirmationButtonColor;
  final int? confirmationButtonTextColor;
  final int? textFieldTextColor;
  final int? textFieldPlaceholderColor;
  final int? textFieldBorderColor;
  final int? errorColor;
  final int? navigationBarTintColor;
  final int? navigationBarBackgroundColor;
  final int? navigationBarTextColor;
  final int? navigationItemTextColor;
  final int? cellTintColor;
  final int? cellHighlightedBackgroundColor;
  final int? cellHighlightedTextColor;
  final int? sectionBackgroundColor;
  final int? sectionTextColor;
  final int? separatorColor;
  final int? paymentBrandIconBackgroundColor;
  final int? paymentBrandIconBorderColor;
  final int? storedPaymentMethodIconBackgroundColor;
  final int? storedPaymentMethodIconBorderColor;

  final CheckoutFont? primaryFont;
  final CheckoutFont? secondaryFont;
  final CheckoutFont? textFieldFont;
  final CheckoutFont? confirmationButtonFont;
  final CheckoutFont? errorFont;
  final CheckoutFont? amountLabelFont;
  final CheckoutFont? cellTextFont;
  final CheckoutFont? sectionFont;

  /// Text of the cancel button in the navigation bar. Not localized by the
  /// SDK; pass a localized string.
  final String? cancelBarButtonText;

  /// Flutter asset path of an image that replaces the cancel button text.
  final String? cancelBarButtonImageAsset;

  const CheckoutTheme({
    this.style,
    this.primaryBackgroundColor,
    this.primaryForegroundColor,
    this.accentColor,
    this.confirmationButtonColor,
    this.confirmationButtonTextColor,
    this.textFieldTextColor,
    this.textFieldPlaceholderColor,
    this.textFieldBorderColor,
    this.errorColor,
    this.navigationBarTintColor,
    this.navigationBarBackgroundColor,
    this.navigationBarTextColor,
    this.navigationItemTextColor,
    this.cellTintColor,
    this.cellHighlightedBackgroundColor,
    this.cellHighlightedTextColor,
    this.sectionBackgroundColor,
    this.sectionTextColor,
    this.separatorColor,
    this.paymentBrandIconBackgroundColor,
    this.paymentBrandIconBorderColor,
    this.storedPaymentMethodIconBackgroundColor,
    this.storedPaymentMethodIconBorderColor,
    this.primaryFont,
    this.secondaryFont,
    this.textFieldFont,
    this.confirmationButtonFont,
    this.errorFont,
    this.amountLabelFont,
    this.cellTextFont,
    this.sectionFont,
    this.cancelBarButtonText,
    this.cancelBarButtonImageAsset,
  });

  Map<String, dynamic> toMap() {
    final colors = <String, int?>{
      'primaryBackgroundColor': primaryBackgroundColor,
      'primaryForegroundColor': primaryForegroundColor,
      'accentColor': accentColor,
      'confirmationButtonColor': confirmationButtonColor,
      'confirmationButtonTextColor': confirmationButtonTextColor,
      'textFieldTextColor': textFieldTextColor,
      'textFieldPlaceholderColor': textFieldPlaceholderColor,
      'textFieldBorderColor': textFieldBorderColor,
      'errorColor': errorColor,
      'navigationBarTintColor': navigationBarTintColor,
      'navigationBarBackgroundColor': navigationBarBackgroundColor,
      'navigationBarTextColor': navigationBarTextColor,
      'navigationItemTextColor': navigationItemTextColor,
      'cellTintColor': cellTintColor,
      'cellHighlightedBackgroundColor': cellHighlightedBackgroundColor,
      'cellHighlightedTextColor': cellHighlightedTextColor,
      'sectionBackgroundColor': sectionBackgroundColor,
      'sectionTextColor': sectionTextColor,
      'separatorColor': separatorColor,
      'paymentBrandIconBackgroundColor': paymentBrandIconBackgroundColor,
      'paymentBrandIconBorderColor': paymentBrandIconBorderColor,
      'storedPaymentMethodIconBackgroundColor':
          storedPaymentMethodIconBackgroundColor,
      'storedPaymentMethodIconBorderColor': storedPaymentMethodIconBorderColor,
    }..removeWhere((_, v) => v == null);
    final fonts = <String, CheckoutFont?>{
      'primaryFont': primaryFont,
      'secondaryFont': secondaryFont,
      'textFieldFont': textFieldFont,
      'confirmationButtonFont': confirmationButtonFont,
      'errorFont': errorFont,
      'amountLabelFont': amountLabelFont,
      'cellTextFont': cellTextFont,
      'sectionFont': sectionFont,
    }..removeWhere((_, v) => v == null);
    return {
      if (style != null) 'style': style!.name,
      'colors': colors,
      'fonts': fonts.map((k, v) => MapEntry(k, v!.toMap())),
      if (cancelBarButtonText != null)
        'cancelBarButtonText': cancelBarButtonText,
      if (cancelBarButtonImageAsset != null)
        'cancelBarButtonImageAsset': cancelBarButtonImageAsset,
    };
  }
}
