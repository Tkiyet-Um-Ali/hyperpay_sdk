/// Configuration for Google Pay payments in the Ready-UI (Android only).
class GooglePayConfig {
  /// Your gateway merchant ID (HyperPay entity ID).
  final String gatewayMerchantId;

  /// Display name shown on the Google Pay sheet.
  final String merchantName;

  /// ISO 3166-1 alpha-2 country code (e.g. `"SA"`, `"AE"`).
  final String countryCode;

  /// Total price to charge.
  final double totalPrice;

  /// ISO 4217 currency code (e.g. `"SAR"`, `"AED"`, `"USD"`).
  final String currencyCode;

  /// Card networks to accept. Default `['VISA', 'MASTERCARD']`.
  final List<String>? allowedCardNetworks;

  /// Authentication methods. Default `['PAN_ONLY', 'CRYPTOGRAM_3DS']`.
  final List<String>? allowedAuthMethods;

  /// `FINAL` (default), `ESTIMATED` or `NOT_CURRENTLY_KNOWN`.
  final String? totalPriceStatus;

  /// Ask Google Pay for the billing address.
  final bool billingAddressRequired;

  /// `MIN` or `FULL` (default when [billingAddressRequired]).
  final String? billingAddressFormat;

  /// Also ask for the phone number with the billing address.
  final bool phoneNumberRequired;

  /// Ask for the shopper's email.
  final bool emailRequired;

  /// Ask for a shipping address.
  final bool shippingAddressRequired;

  /// Gateway name from your acquirer, for the `GOOGLEPAYTKN` brand only.
  final String? gateway;

  const GooglePayConfig({
    required this.gatewayMerchantId,
    required this.merchantName,
    required this.countryCode,
    required this.totalPrice,
    required this.currencyCode,
    this.allowedCardNetworks,
    this.allowedAuthMethods,
    this.totalPriceStatus,
    this.billingAddressRequired = false,
    this.billingAddressFormat,
    this.phoneNumberRequired = false,
    this.emailRequired = false,
    this.shippingAddressRequired = false,
    this.gateway,
  });

  Map<String, dynamic> toMap() {
    return {
      'gatewayMerchantId': gatewayMerchantId,
      'merchantName': merchantName,
      'countryCode': countryCode,
      'totalPrice': totalPrice,
      'currencyCode': currencyCode,
      if (allowedCardNetworks != null)
        'allowedCardNetworks': allowedCardNetworks,
      if (allowedAuthMethods != null) 'allowedAuthMethods': allowedAuthMethods,
      if (totalPriceStatus != null) 'totalPriceStatus': totalPriceStatus,
      'billingAddressRequired': billingAddressRequired,
      if (billingAddressFormat != null)
        'billingAddressFormat': billingAddressFormat,
      'phoneNumberRequired': phoneNumberRequired,
      'emailRequired': emailRequired,
      'shippingAddressRequired': shippingAddressRequired,
      if (gateway != null) 'gateway': gateway,
    };
  }
}
