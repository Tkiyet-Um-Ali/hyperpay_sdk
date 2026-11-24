import Foundation
import UIKit
import PassKit
import OPPWAMobile
import ipworks3ds_sdk

/// Typed accessors for method-channel argument values. Flutter's standard
/// codec delivers numbers and booleans as `NSNumber`, maps as `NSDictionary`
/// and lists as `NSArray`.
enum HPArgs {
    static func string(_ value: Any?) -> String? {
        return value as? String
    }

    static func bool(_ value: Any?) -> Bool? {
        return (value as? NSNumber)?.boolValue
    }

    static func int(_ value: Any?) -> Int? {
        return (value as? NSNumber)?.intValue
    }

    static func double(_ value: Any?) -> Double? {
        return (value as? NSNumber)?.doubleValue
    }

    static func map(_ value: Any?) -> [String: Any]? {
        return value as? [String: Any]
    }

    static func stringList(_ value: Any?) -> [String]? {
        guard let list = value as? [Any] else { return nil }
        return list.compactMap { $0 as? String }
    }

    static func mapList(_ value: Any?) -> [[String: Any]]? {
        guard let list = value as? [Any] else { return nil }
        return list.compactMap { $0 as? [String: Any] }
    }

    static func stringMap(_ value: Any?) -> [String: String]? {
        guard let raw = value as? [String: Any] else { return nil }
        var out: [String: String] = [:]
        for (key, item) in raw {
            if let s = item as? String { out[key] = s }
        }
        return out
    }

    /// ARGB int (0xAARRGGBB, Int or Long) → UIColor.
    static func color(_ value: Any?) -> UIColor? {
        guard let number = value as? NSNumber else { return nil }
        let argb = UInt32(truncatingIfNeeded: number.int64Value)
        let alpha = CGFloat((argb >> 24) & 0xFF) / 255.0
        let red   = CGFloat((argb >> 16) & 0xFF) / 255.0
        let green = CGFloat((argb >> 8)  & 0xFF) / 255.0
        let blue  = CGFloat( argb        & 0xFF) / 255.0
        return UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    /// Decimal amount from a Dart double, going through its shortest string
    /// form so 10.1 stays 10.1 (not 10.0999999…).
    static func decimal(_ amount: Double) -> NSDecimalNumber {
        let number = NSDecimalNumber(string: "\(amount)", locale: Locale(identifier: "en_US_POSIX"))
        return number == NSDecimalNumber.notANumber ? NSDecimalNumber(value: amount) : number
    }

    /// `{family?, size, bold}` → UIFont. A missing / unknown family falls back
    /// to the system font of that size.
    static func font(_ value: Any?) -> UIFont? {
        guard let m = map(value), let rawSize = double(m["size"]) else { return nil }
        let size = CGFloat(rawSize)
        let bold = bool(m["bold"]) ?? false

        if let family = string(m["family"]), !family.isEmpty {
            let named = UIFont(name: family, size: size)
                ?? UIFont.fontNames(forFamilyName: family).first.flatMap { UIFont(name: $0, size: size) }
            if let font = named {
                if bold, let descriptor = font.fontDescriptor.withSymbolicTraits(.traitBold) {
                    return UIFont(descriptor: descriptor, size: size)
                }
                return font
            }
            NSLog("[HyperPay] Font '%@' is not registered in the app; using the system font", family)
        }
        return bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size)
    }
}

// MARK: - 3-D Secure

enum HPThreeDS {
    static func config(from m: [String: Any]) -> OPPThreeDSConfig {
        let config = OPPThreeDSConfig()

        if let types = HPArgs.stringList(m["challengeUiTypes"]) {
            var uiTypes: OPPThreeDSChallengeUiType = []
            for type in types {
                switch type {
                case "text": uiTypes.insert(.text)
                case "singleSelect": uiTypes.insert(.singleSelect)
                case "multiSelect": uiTypes.insert(.multiSelect)
                case "oob": uiTypes.insert(.oob)
                case "html": uiTypes.insert(.html)
                case "htmlOob": uiTypes.insert(.htmlOob)
                case "information": uiTypes.insert(.information)
                default: NSLog("[HyperPay] Unknown 3DS challenge UI type '%@' ignored", type)
                }
            }
            config.challengeUiTypes = uiTypes
        }
        if let timeout = HPArgs.int(m["sdkMaxTimeout"]) {
            config.sdkMaxTimeout = timeout
        }
        if let locale = HPArgs.string(m["locale"]) {
            config.locale = locale
        }
        if let blacklist = HPArgs.stringList(m["deviceParameterBlacklist"]) {
            config.deviceParameterBlacklist = blacklist
        }
        if let url = HPArgs.string(m["requestorAppUrl"]) {
            config.threeDSRequestorAppURL = url
        }
        if let browserData = HPArgs.bool(m["browserDataRequired"]) {
            config.isBrowserDataRequired = browserData
        }
        if let params = HPArgs.stringMap(m["clientConfigParams"]) {
            config.clientConfigParams = params
        }
        if let bundleId = HPArgs.string(m["appBundleId"]) {
            config.appBundleID = bundleId
        }
        if let ui = HPArgs.map(m["uiCustomization"]) {
            applyUiCustomization(ui, to: config.uiCustomization)
        }
        return config
    }

    private static func applyText(_ m: [String: Any], to customization: Customization) {
        if let color = HPArgs.color(m["textColor"]) {
            customization.setTextColor(color: color)
        }
        if let fontName = HPArgs.string(m["fontName"]) {
            attempt("text font name") { try customization.setTextFontName(fontName: fontName) }
        }
        if let fontSize = HPArgs.int(m["fontSize"]) {
            attempt("text font size") { try customization.setTextFontSize(fontSize: fontSize) }
        }
    }

    private static func attempt(_ what: String, _ block: () throws -> Void) {
        do {
            try block()
        } catch {
            NSLog("[HyperPay] 3DS UI customization: invalid %@ ignored (%@)", what, error.localizedDescription)
        }
    }

    private static func applyUiCustomization(_ m: [String: Any], to ui: UiCustomization) {
        if let toolbarMap = HPArgs.map(m["toolbar"]) {
            let toolbar = ToolbarCustomization()
            applyText(toolbarMap, to: toolbar)
            if let color = HPArgs.color(toolbarMap["backgroundColor"]) {
                toolbar.setBackgroundColor(color: color)
            }
            if let header = HPArgs.string(toolbarMap["headerText"]) {
                attempt("toolbar header text") { try toolbar.setHeaderText(headerText: header) }
            }
            if let button = HPArgs.string(toolbarMap["buttonText"]) {
                attempt("toolbar button text") { try toolbar.setButtonText(buttonText: button) }
            }
            attempt("toolbar") { try ui.setToolbarCustomization(toolbarCustomization: toolbar) }
        }

        if let labelMap = HPArgs.map(m["label"]) {
            let label = LabelCustomization()
            applyText(labelMap, to: label)
            if let heading = HPArgs.map(labelMap["heading"]) {
                if let color = HPArgs.color(heading["textColor"]) {
                    label.setHeadingTextColor(color: color)
                }
                if let fontName = HPArgs.string(heading["fontName"]) {
                    attempt("heading font name") { try label.setHeadingTextFontName(fontName: fontName) }
                }
                if let fontSize = HPArgs.int(heading["fontSize"]) {
                    attempt("heading font size") { try label.setHeadingTextFontSize(fontSize: fontSize) }
                }
            }
            attempt("label") { try ui.setLabelCustomization(labelCustomization: label) }
        }

        if let textBoxMap = HPArgs.map(m["textBox"]) {
            let textBox = TextBoxCustomization()
            applyText(textBoxMap, to: textBox)
            if let width = HPArgs.int(textBoxMap["borderWidth"]) {
                attempt("text box border width") { try textBox.setBorderWidth(borderWidth: width) }
            }
            if let color = HPArgs.color(textBoxMap["borderColor"]) {
                textBox.setBorderColor(color: color)
            }
            if let radius = HPArgs.int(textBoxMap["cornerRadius"]) {
                attempt("text box corner radius") { try textBox.setCornerRadius(cornerRadius: radius) }
            }
            attempt("text box") { try ui.setTextBoxCustomization(textBoxCustomization: textBox) }
        }

        if let buttons = HPArgs.map(m["buttons"]) {
            for (typeName, raw) in buttons {
                guard let buttonMap = HPArgs.map(raw) else { continue }
                let type: ButtonType
                switch typeName {
                case "submit": type = .SUBMIT
                case "continueButton": type = .CONTINUE
                case "next": type = .NEXT
                case "cancel": type = .CANCEL
                case "resend": type = .RESEND
                default:
                    NSLog("[HyperPay] Unknown 3DS button type '%@' ignored", typeName)
                    continue
                }
                let button = ButtonCustomization()
                applyText(buttonMap, to: button)
                if let color = HPArgs.color(buttonMap["backgroundColor"]) {
                    button.setBackgroundColor(color: color)
                }
                if let radius = HPArgs.int(buttonMap["cornerRadius"]) {
                    attempt("button corner radius") { try button.setCornerRadius(cornerRadius: radius) }
                }
                attempt("button \(typeName)") {
                    try ui.setButtonCustomization(buttonCustomization: button, buttonType: type)
                }
            }
        }
    }

    static func severityName(_ severity: Severity) -> String {
        switch severity {
        case .LOW: return "LOW"
        case .MEDIUM: return "MEDIUM"
        case .HIGH: return "HIGH"
        @unknown default: return "\(severity.rawValue)"
        }
    }
}

// MARK: - Apple Pay

enum HPApplePay {
    static func summaryItems(_ value: Any?) -> [PKPaymentSummaryItem]? {
        guard let list = HPArgs.mapList(value), !list.isEmpty else { return nil }
        return list.map { item in
            let label = HPArgs.string(item["label"]) ?? ""
            let amount = HPArgs.decimal(HPArgs.double(item["amount"]) ?? 0)
            let pending = HPArgs.bool(item["pending"]) ?? false
            return PKPaymentSummaryItem(label: label, amount: amount, type: pending ? .pending : .final)
        }
    }

    static func shippingMethods(_ value: Any?) -> [PKShippingMethod]? {
        guard let list = HPArgs.mapList(value) else { return nil }
        return list.map { item in
            let method = PKShippingMethod(
                label: HPArgs.string(item["label"]) ?? "",
                amount: HPArgs.decimal(HPArgs.double(item["amount"]) ?? 0)
            )
            method.identifier = HPArgs.string(item["identifier"])
            method.detail = HPArgs.string(item["detail"])
            return method
        }
    }

    static func networks(_ value: Any?) -> [PKPaymentNetwork]? {
        guard let list = HPArgs.stringList(value), !list.isEmpty else { return nil }
        return list.map { PKPaymentNetwork(rawValue: $0) }
    }

    static func contactFields(_ value: Any?) -> Set<PKContactField>? {
        guard let list = HPArgs.stringList(value) else { return nil }
        var fields = Set<PKContactField>()
        for name in list {
            switch name {
            case "postalAddress": fields.insert(.postalAddress)
            case "emailAddress": fields.insert(.emailAddress)
            case "phoneNumber": fields.insert(.phoneNumber)
            case "name": fields.insert(.name)
            default: NSLog("[HyperPay] Unknown Apple Pay contact field '%@' ignored", name)
            }
        }
        return fields
    }

    /// Builds the Apple Pay request shared by every Apple Pay flow from the
    /// ApplePayConfig keys (`merchantId`, `countryCode`, `currencyCode`,
    /// `amount`, `companyName` plus the optional extras).
    static func paymentRequest(
        merchantId: String,
        countryCode: String,
        currencyCode: String,
        amount: Double,
        companyName: String,
        config: [String: Any]
    ) -> PKPaymentRequest {
        let request = OPPPaymentProvider.paymentRequest(
            withMerchantIdentifier: merchantId,
            countryCode: countryCode
        )
        request.currencyCode = currencyCode
        request.paymentSummaryItems = summaryItems(config["summaryItems"]) ?? [
            PKPaymentSummaryItem(label: companyName, amount: HPArgs.decimal(amount))
        ]
        if let networks = networks(config["supportedNetworks"]) {
            request.supportedNetworks = networks
        }
        if let fields = contactFields(config["requiredBillingContactFields"]) {
            request.requiredBillingContactFields = fields
        }
        if let fields = contactFields(config["requiredShippingContactFields"]) {
            request.requiredShippingContactFields = fields
        }
        if let methods = shippingMethods(config["shippingMethods"]), !methods.isEmpty {
            request.shippingMethods = methods
        }
        return request
    }

    static func contactMap(_ contact: PKContact) -> [String: Any] {
        var map: [String: Any] = [:]
        if let given = contact.name?.givenName { map["givenName"] = given }
        if let family = contact.name?.familyName { map["familyName"] = family }
        if let email = contact.emailAddress { map["emailAddress"] = email }
        if let phone = contact.phoneNumber?.stringValue { map["phoneNumber"] = phone }
        if let address = contact.postalAddress {
            map["street"] = address.street
            map["city"] = address.city
            map["state"] = address.state
            map["postalCode"] = address.postalCode
            map["country"] = address.country
            map["isoCountryCode"] = address.isoCountryCode
        }
        return map
    }

    static func shippingMethodMap(_ method: PKShippingMethod) -> [String: Any] {
        var map: [String: Any] = [
            "identifier": method.identifier ?? "",
            "label": method.label,
            "amount": method.amount.doubleValue,
        ]
        if let detail = method.detail { map["detail"] = detail }
        return map
    }

    static func buttonType(_ name: String) -> PKPaymentButtonType? {
        switch name {
        case "plain": return .plain
        case "buy": return .buy
        case "setUp": return .setUp
        case "inStore": return .inStore
        case "donate": return .donate
        case "checkout": return .checkout
        case "book": return .book
        case "subscribe": return .subscribe
        default: break
        }
        if #available(iOS 14.0, *) {
            switch name {
            case "reload": return .reload
            case "addMoney": return .addMoney
            case "topUp": return .topUp
            case "order": return .order
            case "rent": return .rent
            case "support": return .support
            case "contribute": return .contribute
            case "tip": return .tip
            default: break
            }
        }
        if #available(iOS 15.0, *), name == "continueButton" {
            return .`continue`
        }
        NSLog("[HyperPay] Apple Pay button type '%@' is not available on this iOS version", name)
        return nil
    }
}

// MARK: - Ready-UI checkout options

enum HPCheckoutOptions {
    private static func securityMode(_ name: String?) -> OPPSecurityPolicyMode? {
        switch name {
        case "notRequired": return .deviceAuthNotRequired
        case "requiredIfAvailable": return .deviceAuthRequiredIfAvailable
        case "required": return .deviceAuthRequired
        default: return nil
        }
    }

    /// Applies `CheckoutOptions.toMap()` to the checkout settings.
    /// `loadImage` resolves a Flutter asset path to an image.
    static func apply(
        _ m: [String: Any],
        to settings: OPPCheckoutSettings,
        loadImage: (String) -> UIImage?
    ) {
        switch HPArgs.string(m["storePaymentDetails"]) {
        case "never": settings.storePaymentDetails = .never
        case "always": settings.storePaymentDetails = .always
        case "prompt": settings.storePaymentDetails = .prompt
        default: break
        }

        switch HPArgs.string(m["skipCvv"]) {
        case "never": settings.skipCVV = .never
        case "forStoredCards": settings.skipCVV = .forStoredCards
        case "always": settings.skipCVV = .always
        default: break
        }

        if let visible = HPArgs.bool(m["cardHolderVisible"]) {
            settings.isCardHolderVisible = visible
        }
        if let display = HPArgs.bool(m["displayTotalAmount"]) {
            settings.displayTotalAmount = display
        }
        if let back = HPArgs.bool(m["backButtonAvailable"]) {
            settings.isBackButtonAvailable = back
        }
        if let installments = HPArgs.bool(m["installmentEnabled"]) {
            settings.isInstallmentEnabled = installments
        }
        if let options = m["installmentOptions"] as? [Any] {
            settings.installmentOptions = options.compactMap { $0 as? NSNumber }
        }

        if let address = HPArgs.map(m["billingAddress"]) {
            let builder = OPPBillingAddressBuilder()
            if let v = HPArgs.string(address["country"]) { _ = builder.withCountry(v) }
            if let v = HPArgs.string(address["state"]) { _ = builder.withState(v) }
            if let v = HPArgs.string(address["city"]) { _ = builder.withCity(v) }
            if let v = HPArgs.string(address["postCode"]) { _ = builder.withPostCode(v) }
            if let v = HPArgs.string(address["street1"]) { _ = builder.withStreet1(v) }
            if let v = HPArgs.string(address["street2"]) { _ = builder.withStreet2(v) }
            _ = builder.withCountryRequired(HPArgs.bool(address["countryRequired"]) ?? false)
            _ = builder.withStateRequired(HPArgs.bool(address["stateRequired"]) ?? false)
            _ = builder.withCityRequired(HPArgs.bool(address["cityRequired"]) ?? false)
            _ = builder.withPostCodeRequired(HPArgs.bool(address["postCodeRequired"]) ?? false)
            _ = builder.withStreet1Required(HPArgs.bool(address["street1Required"]) ?? false)
            _ = builder.withStreet2Required(HPArgs.bool(address["street2Required"]) ?? false)
            settings.billingAddress = builder.build()
        }

        switch HPArgs.string(m["brandDetectionType"]) {
        case "regex": settings.brandDetectionType = .regex
        case "binList": settings.brandDetectionType = .binList
        case "binListAndType": settings.brandDetectionType = .binListAndType
        default: break
        }
        if let priority = HPArgs.stringList(m["brandDetectionPriority"]) {
            settings.brandDetectionPriority = priority
        }
        switch HPArgs.string(m["brandDetectionAppearanceStyle"]) {
        case "active": settings.brandDetectionAppearanceStyle = .active
        case "inactive": settings.brandDetectionAppearanceStyle = .inactive
        case "none": settings.brandDetectionAppearanceStyle = .none
        default: break
        }

        var policies: [OPPSecurityPolicy] = []
        if let mode = securityMode(HPArgs.string(m["tokensSecurityPolicy"])) {
            policies.append(OPPSecurityPolicy(forTokensWith: mode))
        }
        if let perBrand = HPArgs.map(m["brandSecurityPolicies"]) {
            for brand in perBrand.keys.sorted() {
                if let mode = securityMode(HPArgs.string(perBrand[brand])) {
                    policies.append(OPPSecurityPolicy(paymentBrands: [brand], mode: mode))
                }
            }
        }
        if !policies.isEmpty {
            settings.securityPolicies = policies
        }

        if let scanning = HPArgs.bool(m["cardScanningEnabled"]) {
            settings.isCardScanningEnabled = scanning
        }

        if let logos = HPArgs.stringMap(m["customLogoAssets"]) {
            var images: [String: UIImage] = settings.customLogos ?? [:]
            for (brand, asset) in logos {
                if let image = loadImage(asset) {
                    images[brand] = image
                }
            }
            if !images.isEmpty {
                settings.customLogos = images
            }
        }

        if let name = HPArgs.string(m["applePayButtonType"]), let type = HPApplePay.buttonType(name) {
            settings.applePayType = type
        }

        if let contactTypes = HPArgs.stringList(m["applePayContactTypes"]) {
            var types: OPPCheckoutApplePayContactType = []
            for type in contactTypes {
                switch type {
                case "billingAddress": types.insert(.billingAddress)
                case "customer": types.insert(.customer)
                default: break
                }
            }
            settings.applePayContactTypes = types
        }

        // Options the Dart API documents for Android whose iOS equivalent
        // exists in OPPCheckoutSettings 7.11.0 — applied on iOS too.
        if let qr = HPArgs.bool(m["stcPayQrCodeRequired"]) {
            settings.isSTCPayQrCodeRequired = qr
        }
        if let disabled = HPArgs.bool(m["cardExpiryDateValidationDisabled"]) {
            settings.disableCardExpiryDateValidation = disabled
        }
        if let iban = HPArgs.bool(m["ibanRequired"]) {
            settings.isIBANRequired = iban
        }
        if let birthDate = HPArgs.bool(m["showBirthDate"]) {
            settings.isShowBirthDateForRatePay = birthDate
        }
        if let order = HPArgs.bool(m["paymentBrandsOrderUsedForTokens"]) {
            settings.isPaymentBrandsOrderUsedForTokens = order
        }

        if let wpwl = HPArgs.map(m["wpwlOptions"]) {
            var options = settings.wpwlOptions
            for (brand, raw) in wpwl {
                guard let o = HPArgs.map(raw) else { continue }
                let configuration = HPArgs.map(o["configuration"]) ?? [:]
                let jsFunctions = HPArgs.stringMap(o["jsFunctions"])
                if let built = OPPWpwlOptions(configuration: configuration, jsFunctions: jsFunctions) {
                    options[brand] = built
                } else {
                    NSLog("[HyperPay] Invalid wpwlOptions for %@ ignored", brand)
                }
            }
            settings.wpwlOptions = options
        }
    }

    /// Legacy `themeColor`: the main accent colors.
    static func applyThemeColor(_ color: UIColor, to theme: OPPCheckoutTheme) {
        theme.navigationBarBackgroundColor = color
        theme.confirmationButtonColor = color
        theme.accentColor = color
        theme.cellHighlightedBackgroundColor = color
    }

    static func applyThemeStyle(_ m: [String: Any], to theme: OPPCheckoutTheme) {
        switch HPArgs.string(m["style"]) {
        case "light": theme.style = .light
        case "dark": theme.style = .dark
        default: break
        }
    }

    private static let colorKeys: [String: ReferenceWritableKeyPath<OPPCheckoutTheme, UIColor?>] = [
        "primaryBackgroundColor": \.primaryBackgroundColor,
        "primaryForegroundColor": \.primaryForegroundColor,
        "accentColor": \.accentColor,
        "confirmationButtonColor": \.confirmationButtonColor,
        "confirmationButtonTextColor": \.confirmationButtonTextColor,
        "textFieldTextColor": \.textFieldTextColor,
        "textFieldPlaceholderColor": \.textFieldPlaceholderColor,
        "textFieldBorderColor": \.textFieldBorderColor,
        "errorColor": \.errorColor,
        "navigationBarTintColor": \.navigationBarTintColor,
        "navigationBarBackgroundColor": \.navigationBarBackgroundColor,
        "cellTintColor": \.cellTintColor,
        "cellHighlightedBackgroundColor": \.cellHighlightedBackgroundColor,
        "cellHighlightedTextColor": \.cellHighlightedTextColor,
        "sectionBackgroundColor": \.sectionBackgroundColor,
        "sectionTextColor": \.sectionTextColor,
        "separatorColor": \.separatorColor,
        "paymentBrandIconBackgroundColor": \.paymentBrandIconBackgroundColor,
        "paymentBrandIconBorderColor": \.paymentBrandIconBorderColor,
        "storedPaymentMethodIconBackgroundColor": \.storedPaymentMethodIconBackgroundColor,
        "storedPaymentMethodIconBorderColor": \.storedPaymentMethodIconBorderColor,
    ]

    private static let fontKeys: [String: ReferenceWritableKeyPath<OPPCheckoutTheme, UIFont?>] = [
        "primaryFont": \.primaryFont,
        "secondaryFont": \.secondaryFont,
        "textFieldFont": \.textFieldFont,
        "confirmationButtonFont": \.confirmationButtonFont,
        "errorFont": \.errorFont,
        "amountLabelFont": \.amountLabelFont,
        "cellTextFont": \.cellTextFont,
        "sectionFont": \.sectionFont,
    ]

    /// Applies `CheckoutTheme.toMap()` colors, fonts and cancel button.
    /// (`style` is applied separately, before `themeColor`.)
    static func applyTheme(
        _ m: [String: Any],
        to theme: OPPCheckoutTheme,
        loadImage: (String) -> UIImage?
    ) {
        if let colors = HPArgs.map(m["colors"]) {
            for (key, raw) in colors {
                guard let color = HPArgs.color(raw) else { continue }
                if let keyPath = colorKeys[key] {
                    theme[keyPath: keyPath] = color
                } else if key == "navigationBarTextColor" {
                    theme.navigationBarTextAttributes = attributes(theme.navigationBarTextAttributes, color: color)
                } else if key == "navigationItemTextColor" {
                    theme.navigationItemTextAttributes = attributes(theme.navigationItemTextAttributes, color: color)
                } else {
                    NSLog("[HyperPay] Unknown theme color '%@' ignored", key)
                }
            }
        }

        if let fonts = HPArgs.map(m["fonts"]) {
            for (key, raw) in fonts {
                guard let keyPath = fontKeys[key], let font = HPArgs.font(raw) else { continue }
                theme[keyPath: keyPath] = font
            }
        }

        if let text = HPArgs.string(m["cancelBarButtonText"]) {
            theme.cancelBarButtonText = text
        }
        if let asset = HPArgs.string(m["cancelBarButtonImageAsset"]), let image = loadImage(asset) {
            theme.cancelBarButtonImage = image
        }
    }

    private static func attributes(_ existing: NSDictionary?, color: UIColor) -> NSDictionary {
        let dict = (existing?.mutableCopy() as? NSMutableDictionary) ?? NSMutableDictionary()
        dict[NSAttributedString.Key.foregroundColor] = color
        return dict
    }
}
