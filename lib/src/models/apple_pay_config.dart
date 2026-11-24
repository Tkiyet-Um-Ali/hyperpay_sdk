/// A line on the Apple Pay sheet (`PKPaymentSummaryItem`). The last item is
/// the total; Apple shows its label as "Pay <label>".
class ApplePaySummaryItem {
  final String label;
  final double amount;

  /// `true` for an amount that isn't final yet (`PKPaymentSummaryItemType.pending`).
  final bool pending;

  const ApplePaySummaryItem({
    required this.label,
    required this.amount,
    this.pending = false,
  });

  Map<String, dynamic> toMap() => {
    'label': label,
    'amount': amount,
    'pending': pending,
  };
}

/// A shipping option on the Apple Pay sheet (`PKShippingMethod`).
class ApplePayShippingMethod {
  final String identifier;
  final String label;
  final String? detail;
  final double amount;

  const ApplePayShippingMethod({
    required this.identifier,
    required this.label,
    required this.amount,
    this.detail,
  });

  factory ApplePayShippingMethod.fromMap(Map<String, dynamic> map) =>
      ApplePayShippingMethod(
        identifier: map['identifier']?.toString() ?? '',
        label: map['label']?.toString() ?? '',
        detail: map['detail'] as String?,
        amount: (map['amount'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toMap() => {
    'identifier': identifier,
    'label': label,
    if (detail != null) 'detail': detail,
    'amount': amount,
  };
}

/// Contact fields Apple Pay can ask for (`PKContactField`).
enum ApplePayContactField { postalAddress, emailAddress, phoneNumber, name }

/// A contact from the Apple Pay sheet. Before authorization Apple redacts the
/// shipping contact to what's needed to compute shipping (city, state,
/// postal code, country).
class ApplePayContact {
  final String? givenName;
  final String? familyName;
  final String? emailAddress;
  final String? phoneNumber;
  final String? street;
  final String? city;
  final String? state;
  final String? postalCode;
  final String? country;
  final String? isoCountryCode;

  const ApplePayContact({
    this.givenName,
    this.familyName,
    this.emailAddress,
    this.phoneNumber,
    this.street,
    this.city,
    this.state,
    this.postalCode,
    this.country,
    this.isoCountryCode,
  });

  factory ApplePayContact.fromMap(Map<String, dynamic> map) => ApplePayContact(
    givenName: map['givenName'] as String?,
    familyName: map['familyName'] as String?,
    emailAddress: map['emailAddress'] as String?,
    phoneNumber: map['phoneNumber'] as String?,
    street: map['street'] as String?,
    city: map['city'] as String?,
    state: map['state'] as String?,
    postalCode: map['postalCode'] as String?,
    country: map['country'] as String?,
    isoCountryCode: map['isoCountryCode'] as String?,
  );

  @override
  String toString() =>
      'ApplePayContact($givenName $familyName, $city, $isoCountryCode)';
}

/// New sheet contents returned from an Apple Pay shipping callback. Return
/// `errors` to show a field error (e.g. "we don't ship there").
class ApplePayShippingUpdate {
  final List<ApplePaySummaryItem> summaryItems;
  final List<ApplePayShippingMethod>? shippingMethods;

  /// Shown on the sheet as an invalid shipping address.
  final String? shippingAddressError;

  const ApplePayShippingUpdate({
    required this.summaryItems,
    this.shippingMethods,
    this.shippingAddressError,
  });

  Map<String, dynamic> toMap() => {
    'summaryItems': summaryItems.map((i) => i.toMap()).toList(),
    if (shippingMethods != null)
      'shippingMethods': shippingMethods!.map((m) => m.toMap()).toList(),
    if (shippingAddressError != null)
      'shippingAddressError': shippingAddressError,
  };
}

/// Configuration for Apple Pay payments (iOS only).
class ApplePayConfig {
  /// Apple Pay merchant identifier configured in your Apple Developer account.
  final String merchantId;

  /// ISO 3166-1 alpha-2 country code (e.g. `"SA"`, `"AE"`).
  final String countryCode;

  /// ISO 4217 currency code (e.g. `"SAR"`, `"AED"`, `"USD"`).
  final String currencyCode;

  /// Payment amount. Used for the single total line when [summaryItems] is
  /// not set.
  final double amount;

  /// Company name displayed on the Apple Pay sheet (shown as "Pay companyName").
  final String companyName;

  /// Full list of sheet lines; the last one is the total. Overrides
  /// [amount] / [companyName] when set.
  final List<ApplePaySummaryItem>? summaryItems;

  /// Card networks to accept, as `PKPaymentNetwork` raw values (e.g.
  /// `['Visa', 'MasterCard', 'Mada', 'AmEx']`). Default: every network
  /// HyperPay supports.
  final List<String>? supportedNetworks;

  /// Contact fields required in the billing contact.
  final Set<ApplePayContactField>? requiredBillingContactFields;

  /// Contact fields required in the shipping contact.
  final Set<ApplePayContactField>? requiredShippingContactFields;

  /// Shipping options to offer.
  final List<ApplePayShippingMethod>? shippingMethods;

  /// Send the Apple Pay billing / shipping contacts to HyperPay with the
  /// payment (your-own-UI `payApplePay` / `payApplePayDynamic`).
  final bool submitContacts;

  /// Payment brand: `'APPLEPAY'` (default) or `'APPLEPAYTKN'` when your
  /// acquirer decrypts the token.
  final String? paymentBrand;

  const ApplePayConfig({
    required this.merchantId,
    required this.countryCode,
    required this.currencyCode,
    required this.amount,
    required this.companyName,
    this.summaryItems,
    this.supportedNetworks,
    this.requiredBillingContactFields,
    this.requiredShippingContactFields,
    this.shippingMethods,
    this.submitContacts = false,
    this.paymentBrand,
  });

  Map<String, dynamic> toMap() {
    return {
      'merchantId': merchantId,
      'countryCode': countryCode,
      'currencyCode': currencyCode,
      'amount': amount,
      'companyName': companyName,
      if (summaryItems != null)
        'summaryItems': summaryItems!.map((i) => i.toMap()).toList(),
      if (supportedNetworks != null) 'supportedNetworks': supportedNetworks,
      if (requiredBillingContactFields != null)
        'requiredBillingContactFields': requiredBillingContactFields!
            .map((f) => f.name)
            .toList(),
      if (requiredShippingContactFields != null)
        'requiredShippingContactFields': requiredShippingContactFields!
            .map((f) => f.name)
            .toList(),
      if (shippingMethods != null)
        'shippingMethods': shippingMethods!.map((m) => m.toMap()).toList(),
      'submitContacts': submitContacts,
      if (paymentBrand != null) 'paymentBrand': paymentBrand,
    };
  }
}
