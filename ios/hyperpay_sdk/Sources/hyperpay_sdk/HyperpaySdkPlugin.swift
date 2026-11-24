import Flutter
import UIKit
import SafariServices
import PassKit
import OPPWAMobile
import ipworks3ds_sdk

public class HyperpaySdkPlugin: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate {

    private var channel: FlutterMethodChannel?
    private var registrar: FlutterPluginRegistrar?
    private var paymentProvider: OPPPaymentProvider?
    private var checkoutProvider: OPPCheckoutProvider?
    /// Strong reference: `OPPCheckoutProvider.delegate` is weak.
    private var checkoutDelegate: HyperpayCheckoutDelegate?
    /// Strong reference: `OPPPaymentProvider.threeDSEventListener` is weak.
    private var threeDSListener: HyperpayThreeDSListener?
    private var pendingResult: FlutterResult?
    private var pendingResourcePath: String?
    private var safariVC: SFSafariViewController?
    private var shopperResultUrl: String?

    // MARK: - FlutterPlugin Registration

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.hyperpay.sdk/channel",
            binaryMessenger: registrar.messenger()
        )
        let instance = HyperpaySdkPlugin()
        instance.channel = channel
        instance.registrar = registrar
        registrar.addMethodCallDelegate(instance, channel: channel)
        // The shopper-result URL (async / 3DS return) arrives through the
        // scene delegate in UIScene apps (the default since Flutter 3.38, and
        // required by Xcode 27). Apps that haven't migrated still get it through
        // the application delegate, so register for both.
        registrar.addApplicationDelegate(instance)
        registrar.addSceneDelegate(instance)
    }

    // MARK: - MethodCallHandler

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "setup":
            handleSetup(call, result: result)
        case "checkoutReadyUI":
            handleCheckoutReadyUI(call, result: result)
        case "payCustomUI":
            handlePayCustomUI(call, result: result)
        case "registerCard":
            handleRegisterCard(call, result: result)
        case "payWithToken":
            handlePayWithToken(call, result: result)
        case "payStcPay":
            handlePayStcPay(call, result: result)
        case "payWithBrand":
            handlePayWithBrand(call, result: result)
        case "payGooglePay", "paySamsungPay":
            result(FlutterError(code: "UNSUPPORTED", message: "\(call.method) is only available on Android", details: nil))
        case "klarnaCreateSession":
            handleKlarna(call, result: result, submitPayment: false)
        case "klarnaSubmitPayment":
            handleKlarna(call, result: result, submitPayment: true)
        case "validateCard":
            handleValidateCard(call, result: result)
        case "payApplePay":
            handlePayApplePay(call, result: result)
        case "payApplePayDynamic":
            handlePayApplePayDynamic(call, result: result)
        case "isApplePayAvailable":
            handleIsApplePayAvailable(call, result: result)
        case "requestBinInfo":
            handleRequestBinInfo(call, result: result)
        case "getCheckoutInfo":
            handleGetCheckoutInfo(call, result: result)
        case "getPaymentStatus":
            handleGetPaymentStatus(call, result: result)
        case "getThreeDSWarnings":
            handleGetThreeDSWarnings(call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private static func notInitialized(_ action: String = "making payments") -> FlutterError {
        return FlutterError(code: "NOT_INITIALIZED", message: "Call setup() before \(action)", details: nil)
    }

    // MARK: - Setup

    private func handleSetup(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let mode = args["mode"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "mode is required", details: nil))
            return
        }

        let providerMode: OPPProviderMode = mode == "live" ? .live : .test
        let provider = OPPPaymentProvider(mode: providerMode)

        // 3-D Secure config for your-own-UI payments.
        if let threeDS = HPArgs.map(args["threeDSConfig"]) {
            let listener = HyperpayThreeDSListener(config: HPThreeDS.config(from: threeDS))
            threeDSListener = listener
            provider.threeDSEventListener = listener
        } else {
            threeDSListener = nil
        }

        paymentProvider = provider
        result(nil)
    }

    // MARK: - Asset images

    /// Flutter asset path → UIImage, or nil (logged) when it isn't bundled.
    private func image(forAsset asset: String) -> UIImage? {
        guard let registrar = registrar else { return nil }
        let key = registrar.lookupKey(forAsset: asset)
        if let path = Bundle.main.path(forResource: key, ofType: nil),
           let image = UIImage(contentsOfFile: path) {
            return image
        }
        NSLog("[HyperPay] Flutter asset '%@' not found; ignored", asset)
        return nil
    }

    // MARK: - ReadyUI Checkout

    private func handleCheckoutReadyUI(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let checkoutId = args["checkoutId"] as? String,
              var brands = args["brands"] as? [String] else {
            result(FlutterError(code: "INVALID_ARGS", message: "checkoutId and brands are required", details: nil))
            return
        }

        guard let provider = paymentProvider else {
            result(HyperpaySdkPlugin.notInitialized())
            return
        }

        let shopperUrl = args["shopperResultUrl"] as? String
        let applePayConfig = args["applePayConfig"] as? [String: Any]
        let options = HPArgs.map(args["options"]) ?? [:]

        // Apple Pay with an acquirer-decrypted token: use APPLEPAYTKN in place
        // of APPLEPAY so the Ready-UI submits with that brand.
        if let brand = HPArgs.string(applePayConfig?["paymentBrand"]),
           brand != "APPLEPAY",
           !brands.contains(brand),
           let index = brands.firstIndex(of: "APPLEPAY") {
            brands[index] = brand
        }

        // Configure checkout settings
        let checkoutSettings = OPPCheckoutSettings()
        checkoutSettings.paymentBrands = brands
        checkoutSettings.storePaymentDetails = .prompt

        if let shopperUrl = shopperUrl {
            checkoutSettings.shopperResultURL = "\(shopperUrl)://callback"
            self.shopperResultUrl = shopperUrl
        }

        // Apple Pay configuration
        if let applePayConfig = applePayConfig {
            checkoutSettings.applePayPaymentRequest = HPApplePay.paymentRequest(
                merchantId: applePayConfig["merchantId"] as? String ?? "",
                countryCode: applePayConfig["countryCode"] as? String ?? "",
                currencyCode: applePayConfig["currencyCode"] as? String ?? "",
                amount: HPArgs.double(applePayConfig["amount"]) ?? 0.0,
                companyName: applePayConfig["companyName"] as? String ?? "",
                config: applePayConfig
            )
        }

        // Language
        if let lang = args["lang"] as? String {
            checkoutSettings.language = lang
        }

        // 3-D Secure
        if let threeDS = HPArgs.map(args["threeDSConfig"]) {
            checkoutSettings.threeDSConfig = HPThreeDS.config(from: threeDS)
        }

        // Checkout options
        HPCheckoutOptions.apply(options, to: checkoutSettings) { [weak self] asset in
            self?.image(forAsset: asset)
        }

        // Theme: style first (it resets the palette), then the legacy
        // themeColor, then explicit theme keys (which win over themeColor).
        let theme = checkoutSettings.theme
        let themeMap = HPArgs.map(options["theme"])
        if let themeMap = themeMap {
            HPCheckoutOptions.applyThemeStyle(themeMap, to: theme)
        }
        if let color = HPArgs.color(args["themeColor"]) {
            HPCheckoutOptions.applyThemeColor(color, to: theme)
        }
        if let themeMap = themeMap {
            HPCheckoutOptions.applyTheme(themeMap, to: theme) { [weak self] asset in
                self?.image(forAsset: asset)
            }
        }

        // Create checkout provider
        checkoutProvider = OPPCheckoutProvider(
            paymentProvider: provider,
            checkoutID: checkoutId,
            settings: checkoutSettings
        )
        let delegate = HyperpayCheckoutDelegate(
            channel: channel,
            hasBeforeSubmit: HPArgs.bool(args["hasBeforeSubmit"]) ?? false,
            cardHolderPattern: HPArgs.string(options["cardHolderPattern"]),
            hasShippingContactHandler: HPArgs.bool(args["hasApplePayShippingContactHandler"]) ?? false,
            hasShippingMethodHandler: HPArgs.bool(args["hasApplePayShippingMethodHandler"]) ?? false,
            applePayRequest: checkoutSettings.applePayPaymentRequest
        )
        checkoutDelegate = delegate
        checkoutProvider?.delegate = delegate

        pendingResult = result
        pendingResourcePath = nil

        let paymentBrand = HPArgs.string(args["paymentBrand"]).flatMap { $0.isEmpty ? nil : $0 }

        // Present checkout
        DispatchQueue.main.async { [weak self] in
            let completion: (OPPTransaction?, Error?) -> Void = { [weak self] (transaction, error) in
                self?.handleCheckoutCompletion(transaction: transaction, error: error)
            }
            let cancel: () -> Void = { [weak self] in
                self?.handleCheckoutCancellation()
            }
            if let paymentBrand = paymentBrand {
                self?.checkoutProvider?.presentCheckout(
                    withPaymentBrand: paymentBrand,
                    loadingHandler: nil,
                    completionHandler: completion,
                    cancelHandler: cancel
                )
            } else {
                self?.checkoutProvider?.presentCheckout(
                    forSubmittingTransactionCompletionHandler: completion,
                    cancelHandler: cancel
                )
            }
        }
    }

    // OPP SDK error codes that represent the *shopper* aborting the flow rather
    // than a real failure: closing the payment page (2003), dismissing the
    // 3-D Secure challenge sheet (6001), or a processor-level cancel (9001,
    // added in OPPWA 7.11.0 — e.g. dismissing the Paze/Braintree sheet).
    // See OPPErrors.h. These must be reported to Flutter as cancellations (not
    // failures with a raw, untranslated message) so the app can silently abort.
    private static let oppErrorTransactionAborted = 2003 // OPPErrorCodeTransactionAborted
    private static let oppErrorThreeDS2ChallengeCanceled = 6001 // OPPErrorCodeThreeDS2ChallengeCanceled
    private static let oppErrorGeneralCancel = 9001 // OPPErrorCodeGeneralCancelError

    private func isUserCancellation(_ error: NSError) -> Bool {
        return error.code == HyperpaySdkPlugin.oppErrorTransactionAborted
            || error.code == HyperpaySdkPlugin.oppErrorThreeDS2ChallengeCanceled
            || error.code == HyperpaySdkPlugin.oppErrorGeneralCancel
    }

    /// Builds the Flutter result map for a failed transaction, flagging
    /// user-initiated cancellations via `isCanceled` so the UI shows nothing.
    private func transactionErrorResult(_ error: NSError) -> [String: Any] {
        if isUserCancellation(error) {
            return ["isSuccess": false, "isCanceled": true]
        }
        let detail = "domain=\(error.domain), code=\(error.code), userInfo=\(error.userInfo)"
        return [
            "isSuccess": false,
            "isCanceled": false,
            "errorCode": "\(error.code)",
            "errorMessage": "\(error.localizedDescription) [\(detail)]",
        ]
    }

    private func handleCheckoutCompletion(transaction: OPPTransaction?, error: Error?) {
        guard let pending = pendingResult else { return }

        if let error = error as NSError? {
            pending(transactionErrorResult(error))
            pendingResult = nil
            return
        }

        guard let transaction = transaction else {
            pending([
                "isSuccess": false,
                "isCanceled": false,
                "errorCode": "UNKNOWN",
                "errorMessage": "No transaction returned",
            ] as [String: Any])
            pendingResult = nil
            return
        }

        if transaction.type == .synchronous {
            pending([
                "isSuccess": true,
                "isCanceled": false,
                "resourcePath": transaction.resourcePath ?? "",
                "transactionType": "sync",
            ] as [String: Any])
            pendingResult = nil
        } else {
            // Async — keep pendingResult alive, wait for URL scheme callback
            // OPPCheckoutProvider handles the redirect UI internally
            pendingResourcePath = transaction.resourcePath
        }
    }

    private func handleCheckoutCancellation() {
        guard let pending = pendingResult else { return }
        pending([
            "isSuccess": false,
            "isCanceled": true,
        ] as [String: Any])
        pendingResult = nil
    }

    // MARK: - CustomUI Payment

    /// Card params from the payCustomUI / registerCard arguments. `brand` is
    /// optional: without it the SDK detects the brand from the card number.
    private func cardParams(_ args: [String: Any]) throws -> OPPCardPaymentParams? {
        guard let checkoutId = args["checkoutId"] as? String,
              let cardNumber = args["cardNumber"] as? String,
              let holder = args["holder"] as? String,
              let expiryMonth = args["expiryMonth"] as? String,
              let expiryYear = args["expiryYear"] as? String,
              let cvv = args["cvv"] as? String else {
            return nil
        }
        if let brand = args["brand"] as? String, !brand.isEmpty {
            return try OPPCardPaymentParams(
                checkoutID: checkoutId,
                paymentBrand: brand,
                holder: holder,
                number: cardNumber,
                expiryMonth: expiryMonth,
                expiryYear: expiryYear,
                cvv: cvv
            )
        }
        return try OPPCardPaymentParams(
            checkoutID: checkoutId,
            holder: holder,
            number: cardNumber,
            expiryMonth: expiryMonth,
            expiryYear: expiryYear,
            cvv: cvv
        )
    }

    private func handlePayCustomUI(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        handleCardTransaction(call, result: result, register: false)
    }

    private func handleRegisterCard(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        handleCardTransaction(call, result: result, register: true)
    }

    private func handleCardTransaction(_ call: FlutterMethodCall, result: @escaping FlutterResult, register: Bool) {
        guard let args = call.arguments as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGS", message: "All card fields are required", details: nil))
            return
        }

        guard let provider = paymentProvider else {
            result(HyperpaySdkPlugin.notInitialized())
            return
        }

        do {
            guard let paymentParams = try cardParams(args) else {
                result(FlutterError(code: "INVALID_ARGS", message: "All card fields are required", details: nil))
                return
            }

            let tokenize = !register && (args["tokenize"] as? Bool ?? false)
            if tokenize {
                paymentParams.isTokenizationEnabled = true
            }

            NSLog("[HyperPay] %@ native params: brand=%@, card=****%@, tokenize=%d",
                  register ? "registerCard" : "CustomUI",
                  paymentParams.paymentBrand,
                  String(paymentParams.number.suffix(4)),
                  tokenize ? 1 : 0)

            submitTransaction(
                paymentParams,
                provider: provider,
                shopperUrl: args["shopperResultUrl"] as? String,
                register: register,
                result: result
            )
        } catch {
            NSLog("[HyperPay] OPPCardPaymentParams creation failed: %@", error.localizedDescription)
            result(FlutterError(
                code: "PAYMENT_ERROR",
                message: error.localizedDescription,
                details: nil
            ))
        }
    }

    private func handlePayWithToken(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let checkoutId = args["checkoutId"] as? String,
              let tokenId = args["tokenId"] as? String,
              let brand = args["brand"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "checkoutId, tokenId and brand are required", details: nil))
            return
        }
        guard let provider = paymentProvider else {
            result(HyperpaySdkPlugin.notInitialized())
            return
        }
        do {
            let params: OPPTokenPaymentParams
            if let cvv = args["cvv"] as? String, !cvv.isEmpty {
                params = try OPPTokenPaymentParams(checkoutID: checkoutId, tokenID: tokenId, cardPaymentBrand: brand, cvv: cvv)
            } else {
                params = try OPPTokenPaymentParams(checkoutID: checkoutId, tokenID: tokenId, paymentBrand: brand)
            }
            submitTransaction(params, provider: provider, shopperUrl: args["shopperResultUrl"] as? String, result: result)
        } catch {
            result(FlutterError(code: "PAYMENT_ERROR", message: error.localizedDescription, details: nil))
        }
    }

    private func handlePayStcPay(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let checkoutId = args["checkoutId"] as? String,
              let option = args["verificationOption"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "checkoutId and verificationOption are required", details: nil))
            return
        }
        guard let provider = paymentProvider else {
            result(HyperpaySdkPlugin.notInitialized())
            return
        }
        do {
            let params = try OPPSTCPayPaymentParams(
                checkoutID: checkoutId,
                verificationOption: option == "qrCode" ? .qrCode : .phone
            )
            if let phone = args["mobilePhone"] as? String, !phone.isEmpty {
                params.phoneNumber = phone
            }
            submitTransaction(params, provider: provider, shopperUrl: args["shopperResultUrl"] as? String, result: result)
        } catch {
            result(FlutterError(code: "PAYMENT_ERROR", message: error.localizedDescription, details: nil))
        }
    }

    private func handlePayWithBrand(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let checkoutId = args["checkoutId"] as? String,
              let brand = args["brand"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "checkoutId and brand are required", details: nil))
            return
        }
        guard let provider = paymentProvider else {
            result(HyperpaySdkPlugin.notInitialized())
            return
        }
        do {
            let params = try OPPPaymentParams(checkoutID: checkoutId, paymentBrand: brand)
            if let parameters = HPArgs.stringMap(args["parameters"]) {
                for (name, value) in parameters where !params.addParam(withName: name, value: value) {
                    NSLog("[HyperPay] payWithBrand: parameter '%@' rejected by the SDK", name)
                }
            }
            submitTransaction(params, provider: provider, shopperUrl: args["shopperResultUrl"] as? String, result: result)
        } catch {
            result(FlutterError(code: "PAYMENT_ERROR", message: error.localizedDescription, details: nil))
        }
    }

    /// The single your-own-UI submit path: sync → result now; async → open
    /// the redirect in Safari and resolve on the shopper-result URL callback.
    private func submitTransaction(
        _ paymentParams: OPPPaymentParams,
        provider: OPPPaymentProvider,
        shopperUrl: String?,
        register: Bool = false,
        result: @escaping FlutterResult
    ) {
        if let shopperUrl = shopperUrl {
            paymentParams.shopperResultURL = "\(shopperUrl)://callback"
            self.shopperResultUrl = shopperUrl
        }

        let transaction = OPPTransaction(paymentParams: paymentParams)

        pendingResult = result
        pendingResourcePath = nil
        // A Ready-UI checkout from an earlier call must not be "dismissed" when
        // this payment's shopper-result URL arrives.
        checkoutProvider = nil
        checkoutDelegate = nil

        NSLog("[HyperPay] %@ transaction to provider...", register ? "Registering" : "Submitting")

        let completion: (OPPTransaction, Error?) -> Void = { [weak self] (transaction, error) in
            guard let self = self, let pending = self.pendingResult else { return }

            if let error = error as NSError? {
                self.pendingResult = nil
                pending(self.transactionErrorResult(error))
                return
            }

            if transaction.type == .synchronous {
                self.pendingResult = nil
                pending([
                    "isSuccess": true,
                    "isCanceled": false,
                    "resourcePath": transaction.resourcePath ?? "",
                    "transactionType": "sync",
                ] as [String: Any])
            } else {
                // Async — keep pendingResult alive, wait for URL scheme callback
                self.pendingResourcePath = transaction.resourcePath
                if let redirectUrl = transaction.redirectURL {
                    DispatchQueue.main.async {
                        self.openSafariVC(url: redirectUrl)
                    }
                }
            }
        }

        if register {
            provider.register(transaction, completionHandler: completion)
        } else {
            provider.submitTransaction(transaction, completionHandler: completion)
        }
    }

    // MARK: - Klarna Payments (native inline flow)

    private func handleKlarna(_ call: FlutterMethodCall, result: @escaping FlutterResult, submitPayment: Bool) {
        guard let args = call.arguments as? [String: Any],
              let checkoutId = args["checkoutId"] as? String,
              let brand = args["brand"] as? String,
              let shopperUrl = args["shopperResultUrl"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "checkoutId, brand and shopperResultUrl are required", details: nil))
            return
        }
        let initialTransactionId = args["initialTransactionId"] as? String
        if submitPayment && (initialTransactionId?.isEmpty ?? true) {
            result(FlutterError(code: "INVALID_ARGS", message: "initialTransactionId is required", details: nil))
            return
        }
        guard let provider = paymentProvider else {
            result(HyperpaySdkPlugin.notInitialized())
            return
        }

        let params: OPPKlarnaInlinePaymentParams
        do {
            params = try OPPKlarnaInlinePaymentParams(checkoutID: checkoutId, paymentBrand: brand)
        } catch {
            result(FlutterError(code: "KLARNA_ERROR", message: error.localizedDescription, details: nil))
            return
        }
        params.shopperResultURL = "\(shopperUrl)://callback"
        if submitPayment {
            params.initialTransactionId = initialTransactionId
        }

        provider.submitTransaction(OPPTransaction(paymentParams: params)) { transaction, error in
            DispatchQueue.main.async {
                if let error = error as NSError? {
                    result(FlutterError(
                        code: "KLARNA_ERROR",
                        message: error.localizedDescription,
                        details: "domain=\(error.domain), code=\(error.code)"
                    ))
                    return
                }
                let info = transaction.brandSpecificInfo ?? [:]
                var session: [String: Any] = [:]
                session["clientToken"] = info[OPPTransactionKlarnaInlineClientTokenKey]
                session["initialTransactionId"] = info[OPPTransactionKlarnaInlineInitialTransactionIdKey]
                    ?? initialTransactionId
                session["callbackUrl"] = info[OPPTransactionKlarnaInlineClientCallbackUrlKey]
                session["failureCallbackUrl"] = info[OPPTransactionKlarnaInlineClientFailureCallbackUrlKey]
                session["paymentCategory"] = HyperpaySdkPlugin.klarnaPaymentCategory(brand)
                result(session)
            }
        }
    }

    private static func klarnaPaymentCategory(_ brand: String) -> String? {
        let upper = brand.uppercased()
        if upper.hasSuffix("PAYLATER") { return "pay_later" }
        if upper.hasSuffix("SLICEIT") { return "pay_over_time" }
        if upper.hasSuffix("PAYNOW") { return "pay_now" }
        if upper.hasSuffix("ONE") { return "klarna" }
        return nil
    }

    // MARK: - Card validation

    private func handleValidateCard(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        let luhnCheck = HPArgs.bool(args["luhnCheck"]) ?? true
        var out: [String: Any] = [:]

        if let number = args["number"] as? String {
            out["numberValid"] = OPPCardPaymentParams.isNumberValid(number, luhnCheck: luhnCheck)
        }
        if let holder = args["holder"] as? String {
            out["holderValid"] = OPPCardPaymentParams.isHolderValid(holder)
        }
        let month = args["expiryMonth"] as? String
        let year = args["expiryYear"] as? String
        var monthValid = false
        var yearValid = false
        if let month = month {
            monthValid = OPPCardPaymentParams.isExpiryMonthValid(month)
            out["expiryMonthValid"] = monthValid
        }
        if let year = year {
            yearValid = OPPCardPaymentParams.isExpiryYearValid(year)
            out["expiryYearValid"] = yearValid
        }
        // Only meaningful (and only safe to hand the SDK) for a valid month/year.
        if let month = month, let year = year, monthValid, yearValid {
            out["expired"] = OPPCardPaymentParams.isExpired(month, and: year)
        }
        if let cvv = args["cvv"] as? String {
            if let brand = args["brand"] as? String, !brand.isEmpty {
                let length = OPPCardValidator.cvvLength(forPaymentBrand: brand)
                let digitsOnly = !cvv.isEmpty && cvv.allSatisfy { $0 >= "0" && $0 <= "9" }
                out["cvvValid"] = digitsOnly && cvv.count == length
            } else {
                out["cvvValid"] = OPPBaseCardPaymentParams.isCvvValid(cvv)
            }
        }
        result(out)
    }

    // MARK: - Apple Pay

    private static let applePayUnavailableResult: [String: Any] = [
        "isSuccess": false,
        "isCanceled": false,
        "errorCode": "APPLE_PAY_UNAVAILABLE",
        "errorMessage": "Apple Pay is not available on this device (no entitlement, no payment-processing certificate, or no eligible cards in Wallet).",
    ]

    private func handleIsApplePayAvailable(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]
        var available = OPPPaymentProvider.deviceSupportsApplePay()
        if available, let networks = HPApplePay.networks(args?["networks"]) {
            available = PKPaymentAuthorizationController.canMakePayments(usingNetworks: networks)
        }
        result(available)
    }

    private func handlePayApplePay(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let checkoutId = args["checkoutId"] as? String,
              let merchantId = args["merchantId"] as? String,
              let countryCode = args["countryCode"] as? String,
              let currencyCode = args["currencyCode"] as? String,
              let amount = HPArgs.double(args["amount"]),
              let companyName = args["companyName"] as? String,
              let shopperUrl = args["shopperResultUrl"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "All Apple Pay fields are required", details: nil))
            return
        }

        // Captured so paymentAuthorizationViewController(_:didAuthorizePayment:)
        // can set shopperResultURL on OPPApplePayPaymentParams before submission
        // — HyperPay rejects checkouts that have no shopperResultURL.
        self.shopperResultUrl = shopperUrl

        guard let provider = paymentProvider else {
            result(HyperpaySdkPlugin.notInitialized())
            return
        }

        // Fail gracefully when the device can't do Apple Pay — no wallet cards,
        // no entitlement, or no payment-processing certificate. Without this
        // guard PassKit will hard-abort the process via abort_with_payload
        // when the merchant ID isn't entitled.
        guard PKPaymentAuthorizationViewController.canMakePayments() else {
            result(HyperpaySdkPlugin.applePayUnavailableResult)
            return
        }

        let paymentRequest = HPApplePay.paymentRequest(
            merchantId: merchantId,
            countryCode: countryCode,
            currencyCode: currencyCode,
            amount: amount,
            companyName: companyName,
            config: args
        )
        let brand = HPArgs.string(args["paymentBrand"]).flatMap { $0.isEmpty ? nil : $0 } ?? "APPLEPAY"

        do {
            // Validates the checkout ID up front. The Apple Pay token only exists
            // after authorization, so the real OPPApplePayPaymentParams (with
            // tokenData) is built in paymentAuthorizationViewController(_:didAuthorizePayment:).
            let params = try OPPPaymentParams(
                checkoutID: checkoutId,
                paymentBrand: brand
            )

            pendingResult = result
            applePaySubmissionInFlight = false
            pendingApplePayBrand = brand
            pendingApplePaySubmitContacts = HPArgs.bool(args["submitContacts"]) ?? false

            // Present Apple Pay
            if let rootVC = self.rootViewController(),
               let applePayController = PKPaymentAuthorizationViewController(paymentRequest: paymentRequest) {
                applePayController.delegate = self

                rootVC.present(applePayController, animated: true) {
                    // Store params for submission after Apple Pay authorization
                    self.pendingApplePayParams = params
                    self.pendingApplePayProvider = provider
                }
            } else {
                pendingResult = nil
                result(FlutterError(code: "NO_VIEW_CONTROLLER", message: "Cannot present Apple Pay", details: nil))
            }
        } catch {
            result(FlutterError(
                code: "APPLE_PAY_ERROR",
                message: error.localizedDescription,
                details: nil
            ))
        }
    }

    private var pendingApplePayParams: OPPPaymentParams?
    private var pendingApplePayProvider: OPPPaymentProvider?
    private var pendingApplePayDynamic: Bool = false
    /// Payment brand to submit the Apple Pay token with (APPLEPAY / APPLEPAYTKN).
    private var pendingApplePayBrand: String = "APPLEPAY"
    /// Send the Apple Pay billing / shipping contacts to HyperPay.
    private var pendingApplePaySubmitContacts: Bool = false
    /// True from the moment Apple Pay hands us an authorized token until the
    /// HyperPay submission (or the checkout resolution that precedes it) has
    /// resolved `pendingResult`. While set, the sheet closing is NOT a
    /// cancellation: the payment is already on its way to the gateway and may
    /// still succeed, so `paymentAuthorizationViewControllerDidFinish` must
    /// leave `pendingResult` for the submit completion to resolve.
    private var applePaySubmissionInFlight: Bool = false

    /// OPPApplePayPaymentParams for an authorized payment, with the configured
    /// brand and (when requested) the shopper's contacts.
    private func applePayParams(checkoutId: String, payment: PKPayment) throws -> OPPApplePayPaymentParams {
        let params: OPPApplePayPaymentParams
        if pendingApplePaySubmitContacts {
            params = try OPPApplePayPaymentParams(
                checkoutID: checkoutId,
                paymentBrand: pendingApplePayBrand,
                tokenData: payment.token.paymentData,
                billingContact: payment.billingContact,
                shippingContact: payment.shippingContact
            )
        } else {
            params = try OPPApplePayPaymentParams(
                checkoutID: checkoutId,
                paymentBrand: pendingApplePayBrand,
                tokenData: payment.token.paymentData
            )
        }
        // HyperPay requires shopperResultURL on payment submission. Card flows
        // set it on OPPCardPaymentParams; the Apple Pay flow was missing it,
        // causing "200.300.404 invalid or missing parameter" rejections.
        if let shopperUrl = self.shopperResultUrl {
            params.shopperResultURL = "\(shopperUrl)://callback"
        }
        return params
    }

    // MARK: - Apple Pay (Dynamic — checkout chosen after card network is known)

    private func handlePayApplePayDynamic(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let merchantId = args["merchantId"] as? String,
              let countryCode = args["countryCode"] as? String,
              let currencyCode = args["currencyCode"] as? String,
              let amount = HPArgs.double(args["amount"]),
              let companyName = args["companyName"] as? String,
              let shopperUrl = args["shopperResultUrl"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "All Apple Pay fields are required", details: nil))
            return
        }

        self.shopperResultUrl = shopperUrl

        guard let provider = paymentProvider else {
            result(HyperpaySdkPlugin.notInitialized())
            return
        }

        // Same canMakePayments() guard as the static flow — without it PassKit
        // can abort_with_payload the process when the merchant ID isn't
        // entitled, killing the host app instead of returning an error.
        guard PKPaymentAuthorizationViewController.canMakePayments() else {
            result(HyperpaySdkPlugin.applePayUnavailableResult)
            return
        }

        let paymentRequest = HPApplePay.paymentRequest(
            merchantId: merchantId,
            countryCode: countryCode,
            currencyCode: currencyCode,
            amount: amount,
            companyName: companyName,
            config: args
        )

        // Unless the app chose the networks: make sure MADA cards appear in the
        // wallet picker. HyperPay's default supportedNetworks may omit it.
        if HPApplePay.networks(args["supportedNetworks"]) == nil {
            var networks = paymentRequest.supportedNetworks
            if #available(iOS 14.5, *), !networks.contains(.mada) {
                networks.append(.mada)
            }
            if !networks.contains(.visa) { networks.append(.visa) }
            if !networks.contains(.masterCard) { networks.append(.masterCard) }
            paymentRequest.supportedNetworks = networks
        }

        pendingResult = result
        pendingApplePayProvider = provider
        pendingApplePayDynamic = true
        applePaySubmissionInFlight = false
        pendingApplePayBrand = HPArgs.string(args["paymentBrand"]).flatMap { $0.isEmpty ? nil : $0 } ?? "APPLEPAY"
        pendingApplePaySubmitContacts = HPArgs.bool(args["submitContacts"]) ?? false

        if let rootVC = self.rootViewController(),
           let applePayController = PKPaymentAuthorizationViewController(paymentRequest: paymentRequest) {
            applePayController.delegate = self
            rootVC.present(applePayController, animated: true, completion: nil)
        } else {
            pendingResult = nil
            pendingApplePayProvider = nil
            pendingApplePayDynamic = false
            result(FlutterError(code: "NO_VIEW_CONTROLLER", message: "Cannot present Apple Pay", details: nil))
        }
    }

    private func finishApplePayDynamic(success: Bool, transaction: OPPTransaction?, error: Error?, errorMessage: String? = nil) {
        let pending = pendingResult
        pendingResult = nil
        pendingApplePayProvider = nil
        pendingApplePayDynamic = false
        applePaySubmissionInFlight = false

        if success {
            pending?([
                "isSuccess": true,
                "isCanceled": false,
                "resourcePath": transaction?.resourcePath ?? "",
                "transactionType": "sync",
            ] as [String: Any])
        } else {
            let nsError = error as NSError?
            if let nsError = nsError, isUserCancellation(nsError) {
                pending?(["isSuccess": false, "isCanceled": true] as [String: Any])
                return
            }
            pending?([
                "isSuccess": false,
                "isCanceled": false,
                "errorCode": nsError != nil ? "\(nsError!.code)" : "APPLE_PAY_DYNAMIC_ERROR",
                "errorMessage": errorMessage ?? error?.localizedDescription ?? "Apple Pay failed",
            ] as [String: Any])
        }
    }

    // MARK: - BIN Info

    private func handleRequestBinInfo(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let checkoutId = args["checkoutId"] as? String,
              let bin = args["bin"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "checkoutId and bin are required", details: nil))
            return
        }

        guard let provider = paymentProvider else {
            result(HyperpaySdkPlugin.notInitialized("requesting BIN info"))
            return
        }

        provider.requestBinInfo(withCheckoutID: checkoutId, bin: bin) { binInfo, error in
            if let error = error as NSError? {
                result(FlutterError(
                    code: "BIN_INFO_ERROR",
                    message: error.localizedDescription,
                    details: "domain=\(error.domain), code=\(error.code)"
                ))
                return
            }

            guard let info = binInfo else {
                result([
                    "brands": [String](),
                    "binType": NSNull(),
                    "type": NSNull(),
                ] as [String: Any])
                return
            }

            result([
                "brands": info.brands,
                "binType": info.binType ?? NSNull(),
                "type": info.type ?? NSNull(),
            ] as [String: Any])
        }
    }

    // MARK: - Checkout info / Payment Status

    private static func tokenMap(_ token: OPPToken) -> [String: Any] {
        var map: [String: Any] = [
            "tokenId": token.tokenID,
            "paymentBrand": token.paymentBrand,
        ]
        if let card = token.card {
            map["cardHolder"] = card.holder
            map["cardLast4Digits"] = card.last4Digits
            map["cardExpiryMonth"] = card.expiryMonth
            map["cardExpiryYear"] = card.expiryYear
        }
        if let account = token.bankAccount {
            map["bankAccountHolder"] = account.holder
            map["iban"] = account.iban
        }
        if let virtual = token.virtualAccount {
            map["virtualAccountId"] = virtual.accountId
            if let holder = virtual.holder { map["virtualAccountHolder"] = holder }
        }
        return map
    }

    private static func checkoutInfoMap(_ info: OPPCheckoutInfo) -> [String: Any] {
        return [
            "amount": info.amount.doubleValue,
            "currencyCode": info.currencyCode,
            "resourcePath": info.resourcePath,
            "tokens": (info.tokens ?? []).map { tokenMap($0) },
        ]
    }

    private func handleGetCheckoutInfo(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let checkoutId = args["checkoutId"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "checkoutId is required", details: nil))
            return
        }
        guard let provider = paymentProvider else {
            result(HyperpaySdkPlugin.notInitialized("requesting checkout info"))
            return
        }
        provider.requestCheckoutInfo(withCheckoutID: checkoutId) { info, error in
            DispatchQueue.main.async {
                if let error = error as NSError? {
                    result(FlutterError(
                        code: "CHECKOUT_INFO_ERROR",
                        message: error.localizedDescription,
                        details: "domain=\(error.domain), code=\(error.code)"
                    ))
                    return
                }
                guard let info = info else {
                    result(FlutterError(code: "CHECKOUT_INFO_ERROR", message: "No checkout info returned", details: nil))
                    return
                }
                result(HyperpaySdkPlugin.checkoutInfoMap(info))
            }
        }
    }

    private func handleGetPaymentStatus(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]
        let resourcePath = args?["resourcePath"] as? String

        // Payment status verification should be done server-side.
        let base: [String: Any] = [
            "status": "PENDING_SERVER_VERIFICATION",
            "resourcePath": resourcePath as Any,
        ]

        // Enrich with the checkout details when we can; never fail on it.
        guard let provider = paymentProvider,
              let checkoutId = args?["checkoutId"] as? String,
              !checkoutId.isEmpty else {
            result(base)
            return
        }
        provider.requestCheckoutInfo(withCheckoutID: checkoutId) { info, _ in
            DispatchQueue.main.async {
                guard let info = info else {
                    result(base)
                    return
                }
                var map = HyperpaySdkPlugin.checkoutInfoMap(info)
                map["status"] = "PENDING_SERVER_VERIFICATION"
                if let resourcePath = resourcePath {
                    map["resourcePath"] = resourcePath
                }
                result(map)
            }
        }
    }

    // MARK: - 3DS warnings

    private func handleGetThreeDSWarnings(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let provider = paymentProvider else {
            result(HyperpaySdkPlugin.notInitialized("requesting 3DS warnings"))
            return
        }
        provider.securityWarnings { warnings, error in
            DispatchQueue.main.async {
                if let error = error as NSError? {
                    result(FlutterError(
                        code: "THREE_DS_WARNINGS_ERROR",
                        message: error.localizedDescription,
                        details: "domain=\(error.domain), code=\(error.code)"
                    ))
                    return
                }
                result((warnings ?? []).map { warning -> [String: Any] in
                    [
                        "id": warning.getID(),
                        "message": warning.getMessage(),
                        "severity": HPThreeDS.severityName(warning.getSeverity()),
                    ]
                })
            }
        }
    }

    // MARK: - Safari VC for Async Payments

    private func openSafariVC(url: URL) {
        guard let rootVC = rootViewController() else { return }

        safariVC = SFSafariViewController(url: url)
        safariVC?.delegate = self
        rootVC.present(safariVC!, animated: true, completion: nil)
    }

    // MARK: - URL Scheme Handling

    /// UIScene lifecycle: iOS delivers URLs here instead of `application(_:open:options:)`.
    public func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) -> Bool {
        var handled = false
        for context in URLContexts where handleShopperResultURL(context.url) {
            handled = true
        }
        return handled
    }

    /// Legacy AppDelegate lifecycle (apps not yet migrated to UIScene).
    public func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        return handleShopperResultURL(url)
    }

    private func handleShopperResultURL(_ url: URL) -> Bool {
        guard let shopperUrl = shopperResultUrl,
              url.scheme?.caseInsensitiveCompare(shopperUrl) == .orderedSame else {
            return false
        }

        // Dismiss Safari VC (CustomUI async)
        if let safariVC = safariVC {
            safariVC.dismiss(animated: true, completion: nil)
            self.safariVC = nil
        }

        // Dismiss ReadyUI checkout and resolve pending result
        if let pending = pendingResult {
            let resourcePath = pendingResourcePath ?? ""
            pendingResourcePath = nil

            if let checkoutProvider = checkoutProvider {
                checkoutProvider.dismissCheckout(animated: true) {
                    pending([
                        "isSuccess": true,
                        "isCanceled": false,
                        "resourcePath": resourcePath,
                        "transactionType": "async",
                    ] as [String: Any])
                }
            } else {
                pending([
                    "isSuccess": true,
                    "isCanceled": false,
                    "resourcePath": resourcePath,
                    "transactionType": "async",
                ] as [String: Any])
            }
            pendingResult = nil
        }

        return true
    }

    // MARK: - Helpers

    private func rootViewController() -> UIViewController? {
        if #available(iOS 15.0, *) {
            let scenes = UIApplication.shared.connectedScenes
            let windowScene = scenes.first as? UIWindowScene
            return windowScene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
        } else {
            return UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.rootViewController
        }
    }
}

// MARK: - SFSafariViewControllerDelegate

extension HyperpaySdkPlugin: SFSafariViewControllerDelegate {
    public func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        safariVC = nil
    }
}

// MARK: - PKPaymentAuthorizationViewControllerDelegate

extension HyperpaySdkPlugin: PKPaymentAuthorizationViewControllerDelegate {
    public func paymentAuthorizationViewControllerDidFinish(
        _ controller: PKPaymentAuthorizationViewController
    ) {
        controller.dismiss(animated: true) { [weak self] in
            guard let self = self else { return }
            // The sheet can close while an authorized payment is still being
            // submitted to HyperPay (user dismissed it mid-"Processing", app
            // backgrounded, iOS timed the sheet out). That is not a cancellation
            // — the charge can still land seconds later. Reporting it as one made
            // the host app cancel a booking HyperPay had charged. Leave
            // pendingResult for the submit completion to resolve.
            if self.applePaySubmissionInFlight {
                return
            }
            // If pendingResult is still set, no authorization happened — user canceled
            if self.pendingResult != nil {
                let pending = self.pendingResult
                self.pendingResult = nil
                self.pendingApplePayParams = nil
                self.pendingApplePayProvider = nil
                self.pendingApplePayDynamic = false
                pending?([
                    "isSuccess": false,
                    "isCanceled": true,
                ] as [String: Any])
            }
        }
    }

    public func paymentAuthorizationViewController(
        _ controller: PKPaymentAuthorizationViewController,
        didAuthorizePayment payment: PKPayment,
        handler completion: @escaping (PKPaymentAuthorizationResult) -> Void
    ) {
        // Dynamic flow — checkoutId is resolved by Dart based on detected card network.
        if pendingApplePayDynamic {
            guard let provider = pendingApplePayProvider else {
                completion(PKPaymentAuthorizationResult(status: .failure, errors: nil))
                finishApplePayDynamic(success: false, transaction: nil, error: nil, errorMessage: "Provider unavailable")
                return
            }

            let network = payment.token.paymentMethod.network?.rawValue ?? ""
            NSLog("[HyperPay][ApplePayDynamic] detected network=%@", network)

            guard let channel = self.channel else {
                completion(PKPaymentAuthorizationResult(status: .failure, errors: nil))
                finishApplePayDynamic(success: false, transaction: nil, error: nil, errorMessage: "Method channel unavailable")
                return
            }

            applePaySubmissionInFlight = true
            channel.invokeMethod(
                "resolveApplePayCheckout",
                arguments: ["network": network]
            ) { [weak self] reply in
                guard let self = self else { return }
                guard let payload = reply as? [String: Any],
                      let checkoutId = payload["checkoutId"] as? String,
                      !checkoutId.isEmpty else {
                    let errMsg = (reply as? [String: Any])?["error"] as? String
                        ?? "Failed to resolve Apple Pay checkout ID"
                    completion(PKPaymentAuthorizationResult(status: .failure, errors: nil))
                    self.finishApplePayDynamic(success: false, transaction: nil, error: nil, errorMessage: errMsg)
                    return
                }

                do {
                    let finalParams = try self.applePayParams(checkoutId: checkoutId, payment: payment)
                    let transaction = OPPTransaction(paymentParams: finalParams)
                    provider.submitTransaction(transaction) { [weak self] (transaction, error) in
                        guard let self = self else { return }
                        if let error = error {
                            completion(PKPaymentAuthorizationResult(status: .failure, errors: nil))
                            self.finishApplePayDynamic(success: false, transaction: transaction, error: error)
                            return
                        }
                        completion(PKPaymentAuthorizationResult(status: .success, errors: nil))
                        self.finishApplePayDynamic(success: true, transaction: transaction, error: nil)
                    }
                } catch {
                    completion(PKPaymentAuthorizationResult(status: .failure, errors: nil))
                    self.finishApplePayDynamic(success: false, transaction: nil, error: error)
                }
            }
            return
        }

        guard let params = pendingApplePayParams,
              let provider = pendingApplePayProvider else {
            completion(PKPaymentAuthorizationResult(status: .failure, errors: nil))
            return
        }

        guard let finalParams = try? applePayParams(checkoutId: params.checkoutID, payment: payment) else {
            completion(PKPaymentAuthorizationResult(status: .failure, errors: nil))
            return
        }

        let transaction = OPPTransaction(paymentParams: finalParams)
        applePaySubmissionInFlight = true
        provider.submitTransaction(transaction) { [weak self] (transaction, error) in
            guard let self = self else { return }
            let pending = self.pendingResult
            self.pendingResult = nil
            self.pendingApplePayParams = nil
            self.pendingApplePayProvider = nil
            self.applePaySubmissionInFlight = false

            if let error = error {
                completion(PKPaymentAuthorizationResult(status: .failure, errors: nil))
                pending?(self.transactionErrorResult(error as NSError))
                return
            }

            completion(PKPaymentAuthorizationResult(status: .success, errors: nil))
            pending?([
                "isSuccess": true,
                "isCanceled": false,
                "resourcePath": transaction.resourcePath ?? "",
                "transactionType": "sync",
            ] as [String: Any])
        }
    }
}
