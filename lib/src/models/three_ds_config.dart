/// 3-D Secure 2 challenge UI types the app accepts.
enum ThreeDSChallengeUiType {
  text,
  singleSelect,
  multiSelect,
  oob,
  html,
  htmlOob,
  information,
}

/// Text style shared by the 3DS challenge-screen customizations.
/// Colors are ARGB ints; font names must be registered in the app.
class ThreeDSTextStyle {
  final int? textColor;
  final String? fontName;
  final int? fontSize;

  const ThreeDSTextStyle({this.textColor, this.fontName, this.fontSize});

  Map<String, dynamic> toMap() => {
    if (textColor != null) 'textColor': textColor,
    if (fontName != null) 'fontName': fontName,
    if (fontSize != null) 'fontSize': fontSize,
  };
}

/// Toolbar (header) of the 3DS challenge screen.
class ThreeDSToolbarCustomization {
  final ThreeDSTextStyle text;
  final int? backgroundColor;
  final String? headerText;
  final String? buttonText;

  const ThreeDSToolbarCustomization({
    this.text = const ThreeDSTextStyle(),
    this.backgroundColor,
    this.headerText,
    this.buttonText,
  });

  Map<String, dynamic> toMap() => {
    ...text.toMap(),
    if (backgroundColor != null) 'backgroundColor': backgroundColor,
    if (headerText != null) 'headerText': headerText,
    if (buttonText != null) 'buttonText': buttonText,
  };
}

/// Labels of the 3DS challenge screen.
class ThreeDSLabelCustomization {
  final ThreeDSTextStyle text;
  final ThreeDSTextStyle heading;

  const ThreeDSLabelCustomization({
    this.text = const ThreeDSTextStyle(),
    this.heading = const ThreeDSTextStyle(),
  });

  Map<String, dynamic> toMap() => {...text.toMap(), 'heading': heading.toMap()};
}

/// Text boxes of the 3DS challenge screen.
class ThreeDSTextBoxCustomization {
  final ThreeDSTextStyle text;
  final int? borderWidth;
  final int? borderColor;
  final int? cornerRadius;

  const ThreeDSTextBoxCustomization({
    this.text = const ThreeDSTextStyle(),
    this.borderWidth,
    this.borderColor,
    this.cornerRadius,
  });

  Map<String, dynamic> toMap() => {
    ...text.toMap(),
    if (borderWidth != null) 'borderWidth': borderWidth,
    if (borderColor != null) 'borderColor': borderColor,
    if (cornerRadius != null) 'cornerRadius': cornerRadius,
  };
}

/// Buttons of the 3DS challenge screen.
enum ThreeDSButtonType { submit, continueButton, next, cancel, resend }

class ThreeDSButtonCustomization {
  final ThreeDSTextStyle text;
  final int? backgroundColor;
  final int? cornerRadius;

  const ThreeDSButtonCustomization({
    this.text = const ThreeDSTextStyle(),
    this.backgroundColor,
    this.cornerRadius,
  });

  Map<String, dynamic> toMap() => {
    ...text.toMap(),
    if (backgroundColor != null) 'backgroundColor': backgroundColor,
    if (cornerRadius != null) 'cornerRadius': cornerRadius,
  };
}

/// Look of the 3-D Secure 2 challenge screens (EMVCo UI customization).
class ThreeDSUiCustomization {
  final ThreeDSToolbarCustomization? toolbar;
  final ThreeDSLabelCustomization? label;
  final ThreeDSTextBoxCustomization? textBox;
  final Map<ThreeDSButtonType, ThreeDSButtonCustomization>? buttons;

  const ThreeDSUiCustomization({
    this.toolbar,
    this.label,
    this.textBox,
    this.buttons,
  });

  Map<String, dynamic> toMap() => {
    if (toolbar != null) 'toolbar': toolbar!.toMap(),
    if (label != null) 'label': label!.toMap(),
    if (textBox != null) 'textBox': textBox!.toMap(),
    if (buttons != null)
      'buttons': buttons!.map((type, b) => MapEntry(type.name, b.toMap())),
  };
}

/// 3-D Secure 2 settings (`OPPThreeDSConfig` / `ThreeDSConfig`).
///
/// Pass it to [HyperpaySdk.setup] for your-own-UI payments and/or to
/// [HyperpaySdk.checkoutReadyUI] for the Ready-UI. Unset fields keep the SDK
/// defaults.
class ThreeDSConfig {
  /// Challenge UI types the app supports.
  final Set<ThreeDSChallengeUiType>? challengeUiTypes;

  /// Maximum time for the challenge, in minutes (minimum 5).
  final int? sdkMaxTimeout;

  /// Locale for the challenge screens, e.g. `'ar-SA'`.
  final String? locale;

  /// Device parameters not to collect (EMVCo parameter IDs, e.g. `'A001'`).
  final List<String>? deviceParameterBlacklist;

  /// Look of the challenge screens.
  final ThreeDSUiCustomization? uiCustomization;

  /// iOS: your app URL (universal link or custom scheme) the issuer's app
  /// returns to after out-of-band (app-to-app) authentication.
  /// Android: any non-null value turns on `threeDSRequestorAppUrlUsed`; the
  /// SDK derives the URL from the app.
  final String? requestorAppUrl;

  /// Also collect browser data for a 3DS web fallback.
  final bool? browserDataRequired;

  /// Extra SDK client config parameters.
  final Map<String, String>? clientConfigParams;

  /// iOS: bundle ID reported to the 3DS server (defaults to the app's).
  final String? appBundleId;

  /// Android: SHA-256 of the signing certificate, used by the 3DS SDK's
  /// tamper checks.
  final String? appSignature;

  /// Android: package names of trusted app stores (installer check).
  final List<String>? trustedAppStores;

  /// Android: package names of apps treated as malicious.
  final List<String>? maliciousApps;

  const ThreeDSConfig({
    this.challengeUiTypes,
    this.sdkMaxTimeout,
    this.locale,
    this.deviceParameterBlacklist,
    this.uiCustomization,
    this.requestorAppUrl,
    this.browserDataRequired,
    this.clientConfigParams,
    this.appBundleId,
    this.appSignature,
    this.trustedAppStores,
    this.maliciousApps,
  });

  Map<String, dynamic> toMap() => {
    if (challengeUiTypes != null)
      'challengeUiTypes': challengeUiTypes!.map((t) => t.name).toList(),
    if (sdkMaxTimeout != null) 'sdkMaxTimeout': sdkMaxTimeout,
    if (locale != null) 'locale': locale,
    if (deviceParameterBlacklist != null)
      'deviceParameterBlacklist': deviceParameterBlacklist,
    if (uiCustomization != null) 'uiCustomization': uiCustomization!.toMap(),
    if (requestorAppUrl != null) 'requestorAppUrl': requestorAppUrl,
    if (browserDataRequired != null) 'browserDataRequired': browserDataRequired,
    if (clientConfigParams != null) 'clientConfigParams': clientConfigParams,
    if (appBundleId != null) 'appBundleId': appBundleId,
    if (appSignature != null) 'appSignature': appSignature,
    if (trustedAppStores != null) 'trustedAppStores': trustedAppStores,
    if (maliciousApps != null) 'maliciousApps': maliciousApps,
  };
}

/// A 3DS SDK security warning (EMVCo `SW01`–`SW05`), e.g. a jailbroken /
/// rooted device or a debugger attached.
class ThreeDSWarning {
  final String id;
  final String message;

  /// `LOW`, `MEDIUM` or `HIGH`.
  final String severity;

  const ThreeDSWarning({
    required this.id,
    required this.message,
    required this.severity,
  });

  factory ThreeDSWarning.fromMap(Map<String, dynamic> map) => ThreeDSWarning(
    id: map['id']?.toString() ?? '',
    message: map['message']?.toString() ?? '',
    severity: map['severity']?.toString() ?? '',
  );

  @override
  String toString() => 'ThreeDSWarning($id, $severity: $message)';
}
