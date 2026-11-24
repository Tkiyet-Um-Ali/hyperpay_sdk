import Foundation
import Flutter
import PassKit
import OPPWAMobile

/// `OPPCheckoutProviderDelegate` for one Ready-UI checkout.
///
/// Every requirement of the protocol is optional, and the SDK changes
/// behavior just because a method is implemented: with
/// `checkoutProvider(_:continueSubmitting:…)` it waits for the completion
/// before *every* submission, with `validateCardHolder` it drops its own
/// holder validation, and with the Apple Pay shipping callbacks it hands sheet
/// updates to us. So `responds(to:)` only reports a method when the Dart side
/// registered the matching callback / pattern for this checkout.
final class HyperpayCheckoutDelegate: NSObject, OPPCheckoutProviderDelegate {

    private let channel: FlutterMethodChannel?
    private let hasBeforeSubmit: Bool
    private let cardHolderRegex: NSRegularExpression?
    private let hasShippingContactHandler: Bool
    private let hasShippingMethodHandler: Bool

    /// Last known Apple Pay sheet contents, used when Dart returns no update.
    private var summaryItems: [PKPaymentSummaryItem]
    private var shippingMethods: [PKShippingMethod]

    init(
        channel: FlutterMethodChannel?,
        hasBeforeSubmit: Bool,
        cardHolderPattern: String?,
        hasShippingContactHandler: Bool,
        hasShippingMethodHandler: Bool,
        applePayRequest: PKPaymentRequest?
    ) {
        self.channel = channel
        self.hasBeforeSubmit = hasBeforeSubmit
        if let pattern = cardHolderPattern {
            do {
                cardHolderRegex = try NSRegularExpression(pattern: pattern)
            } catch {
                NSLog("[HyperPay] Invalid cardHolderPattern '%@' ignored: %@", pattern, error.localizedDescription)
                cardHolderRegex = nil
            }
        } else {
            cardHolderRegex = nil
        }
        self.hasShippingContactHandler = hasShippingContactHandler
        self.hasShippingMethodHandler = hasShippingMethodHandler
        self.summaryItems = applePayRequest?.paymentSummaryItems ?? []
        self.shippingMethods = applePayRequest?.shippingMethods ?? []
        super.init()
    }

    /// Objective-C selectors of the optional delegate methods (as declared in
    /// OPPCheckoutProvider.h).
    private enum Selectors {
        static let continueSubmitting = NSSelectorFromString("checkoutProvider:continueSubmitting:andAddOnDetails:completion:")
        static let validateCardHolder = NSSelectorFromString("checkoutProvider:validateCardHolder:")
        static let shippingContact = NSSelectorFromString("checkoutProvider:applePayDidSelectShippingContact:handler:")
        static let shippingMethod = NSSelectorFromString("checkoutProvider:applePayDidSelectShippingMethod:handler:")
    }

    override func responds(to aSelector: Selector!) -> Bool {
        switch aSelector {
        case Selectors.continueSubmitting:
            return hasBeforeSubmit
        case Selectors.validateCardHolder:
            return cardHolderRegex != nil
        case Selectors.shippingContact:
            return hasShippingContactHandler
        case Selectors.shippingMethod:
            return hasShippingMethodHandler
        default:
            return super.responds(to: aSelector)
        }
    }

    /// Calls Dart on the main thread and hands back the reply map (nil when
    /// Dart failed or returned something else).
    private func invokeDart(_ method: String, _ arguments: [String: Any], reply: @escaping ([String: Any]?) -> Void) {
        let send = { [channel] in
            guard let channel = channel else {
                reply(nil)
                return
            }
            channel.invokeMethod(method, arguments: arguments) { response in
                reply(response as? [String: Any])
            }
        }
        if Thread.isMainThread {
            send()
        } else {
            DispatchQueue.main.async(execute: send)
        }
    }

    // MARK: Before submit

    // The SDK checks this variant first and only falls back to
    // checkoutProvider(_:continueSubmitting:completion:) when it's missing,
    // so implementing just this one is enough (and carries the installment plan).
    func checkoutProvider(
        _ checkoutProvider: OPPCheckoutProvider,
        continueSubmitting transaction: OPPTransaction,
        andAddOnDetails additionalDetails: OPPPaymentAddOnDetails?,
        completion: @escaping (String?, Bool) -> Void
    ) {
        let currentCheckoutId = transaction.paymentParams.checkoutID
        var args: [String: Any] = [
            "checkoutId": currentCheckoutId,
            "paymentBrand": transaction.paymentParams.paymentBrand,
        ]
        if let plan = additionalDetails?.selectedInstallmentPlan {
            args["selectedInstallmentPlan"] = plan
        }
        invokeDart("onBeforeSubmit", args) { reply in
            // No usable answer from Dart → don't submit a payment the app
            // didn't approve. The SDK then closes with
            // OPPErrorCodeTransactionAborted, reported as a cancellation.
            guard let reply = reply else {
                completion(nil, true)
                return
            }
            let abort = HPArgs.bool(reply["abort"]) ?? false
            if abort {
                completion(nil, true)
                return
            }
            let newCheckoutId = HPArgs.string(reply["checkoutId"])
            completion((newCheckoutId?.isEmpty == false) ? newCheckoutId : currentCheckoutId, false)
        }
    }

    // MARK: Card holder validation

    func checkoutProvider(_ checkoutProvider: OPPCheckoutProvider, validateCardHolder cardHolder: String?) -> Bool {
        guard let regex = cardHolderRegex else { return true }
        let holder = cardHolder ?? ""
        let fullRange = NSRange(holder.startIndex..<holder.endIndex, in: holder)
        guard let match = regex.firstMatch(in: holder, options: [.anchored], range: fullRange) else {
            return false
        }
        return match.range == fullRange
    }

    // MARK: Apple Pay shipping

    private struct SheetUpdate {
        let summaryItems: [PKPaymentSummaryItem]
        let shippingMethods: [PKShippingMethod]?
        let shippingAddressError: String?
    }

    private func parseUpdate(_ reply: [String: Any]?) -> SheetUpdate? {
        guard let reply = reply,
              let items = HPApplePay.summaryItems(reply["summaryItems"]) else {
            return nil
        }
        return SheetUpdate(
            summaryItems: items,
            shippingMethods: HPApplePay.shippingMethods(reply["shippingMethods"]),
            shippingAddressError: HPArgs.string(reply["shippingAddressError"])
        )
    }

    func checkoutProvider(
        _ checkoutProvider: OPPCheckoutProvider,
        applePayDidSelectShippingContact contact: PKContact,
        handler completion: @escaping (OPPApplePayRequestShippingContactUpdate) -> Void
    ) {
        invokeDart("applePayShippingContactSelected", ["contact": HPApplePay.contactMap(contact)]) { [weak self] reply in
            guard let self = self else { return }
            let update = self.parseUpdate(reply)
            if update == nil {
                NSLog("[HyperPay] applePayShippingContactSelected returned no update; keeping the current sheet")
            }
            if let update = update {
                self.summaryItems = update.summaryItems
                if let methods = update.shippingMethods { self.shippingMethods = methods }
            }
            var errors: [Error]?
            if let message = update?.shippingAddressError {
                errors = [PKPaymentRequest.paymentShippingAddressUnserviceableError(withLocalizedDescription: message)]
            }
            let result = OPPApplePayRequestShippingContactUpdate(
                errors: errors,
                paymentSummaryItems: self.summaryItems,
                shippingMethods: self.shippingMethods
            )
            if errors != nil {
                result.status = .failure
            }
            completion(result)
        }
    }

    func checkoutProvider(
        _ checkoutProvider: OPPCheckoutProvider,
        applePayDidSelect shippingMethod: PKShippingMethod,
        handler completion: @escaping (OPPApplePayRequestShippingMethodUpdate) -> Void
    ) {
        invokeDart("applePayShippingMethodSelected", ["method": HPApplePay.shippingMethodMap(shippingMethod)]) { [weak self] reply in
            guard let self = self else { return }
            if let update = self.parseUpdate(reply) {
                self.summaryItems = update.summaryItems
            } else {
                NSLog("[HyperPay] applePayShippingMethodSelected returned no update; keeping the current sheet")
            }
            completion(OPPApplePayRequestShippingMethodUpdate(paymentSummaryItems: self.summaryItems))
        }
    }
}

/// Supplies the `setup(threeDSConfig:)` configuration to the SDK's own-UI
/// 3-D Secure flow. Only installed when a config was given.
final class HyperpayThreeDSListener: NSObject, OPPThreeDSEventListener {
    private let config: OPPThreeDSConfig

    init(config: OPPThreeDSConfig) {
        self.config = config
        super.init()
    }

    func onThreeDSConfigRequired(completion: @escaping (OPPThreeDSConfig) -> Void) {
        completion(config)
    }
}
