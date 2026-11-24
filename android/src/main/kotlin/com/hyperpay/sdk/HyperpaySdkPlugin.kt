package com.hyperpay.sdk

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.activity.ComponentActivity
import androidx.activity.result.ActivityResultLauncher
import com.oppwa.mobile.connect.checkout.meta.CheckoutActivityResult
import com.oppwa.mobile.connect.checkout.meta.CheckoutActivityResultContract
import com.oppwa.mobile.connect.checkout.meta.CheckoutSettings
import com.oppwa.mobile.connect.exception.ErrorCode
import com.oppwa.mobile.connect.exception.PaymentError
import com.oppwa.mobile.connect.exception.PaymentException
import com.oppwa.mobile.connect.payment.CheckoutInfo
import com.oppwa.mobile.connect.payment.PaymentParams
import com.oppwa.mobile.connect.payment.card.BaseCardPaymentParams
import com.oppwa.mobile.connect.payment.card.CardPaymentParams
import com.oppwa.mobile.connect.payment.googlepay.GooglePayPaymentParams
import com.oppwa.mobile.connect.payment.klarna.KlarnaInlinePaymentParams
import com.oppwa.mobile.connect.payment.samsungpay.SamsungPayPaymentParams
import com.oppwa.mobile.connect.payment.stcpay.STCPayPaymentParams
import com.oppwa.mobile.connect.payment.stcpay.STCPayVerificationOption
import com.oppwa.mobile.connect.payment.token.TokenPaymentParams
import com.oppwa.mobile.connect.provider.Connect
import com.oppwa.mobile.connect.provider.ITransactionListener
import com.oppwa.mobile.connect.provider.OppPaymentProvider
import com.oppwa.mobile.connect.provider.ThreeDSWorkflowListener
import com.oppwa.mobile.connect.provider.Transaction
import com.oppwa.mobile.connect.provider.TransactionType
import com.oppwa.mobile.connect.provider.listener.BinInfoListener
import com.oppwa.mobile.connect.provider.model.BinInfo
import com.oppwa.mobile.connect.provider.threeds.v2.model.ThreeDSConfig

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class HyperpaySdkPlugin : FlutterPlugin, MethodCallHandler, ActivityAware, ITransactionListener {

    private lateinit var channel: MethodChannel
    private var context: Context? = null
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null

    private var paymentProvider: OppPaymentProvider? = null
    private var providerMode: Connect.ProviderMode = Connect.ProviderMode.TEST

    /** 3DS2 config for your-own-UI payments, set in `setup`. */
    private var customUiThreeDSConfig: ThreeDSConfig? = null

    private var pendingResult: Result? = null
    private var checkoutLauncher: ActivityResultLauncher<CheckoutSettings>? = null

    companion object {
        private const val CHANNEL_NAME = "com.hyperpay.sdk/channel"
    }

    // region FlutterPlugin

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
        context = binding.applicationContext
        HyperpayCallbackBridge.channel = channel
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        context = null
        if (HyperpayCallbackBridge.channel === channel) {
            HyperpayCallbackBridge.channel = null
        }
    }

    // endregion

    // region ActivityAware

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        registerCheckoutLauncher()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        registerCheckoutLauncher()
    }

    override fun onDetachedFromActivity() {
        activity = null
        activityBinding = null
        checkoutLauncher = null
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
        activityBinding = null
        checkoutLauncher = null
    }

    // endregion

    // region CheckoutActivityResultContract

    private fun registerCheckoutLauncher() {
        val componentActivity = activity as? ComponentActivity ?: return
        checkoutLauncher = componentActivity.registerForActivityResult(
            CheckoutActivityResultContract()
        ) { result: CheckoutActivityResult ->
            handleCheckoutResult(result)
        }
    }

    private fun handleCheckoutResult(result: CheckoutActivityResult) {
        val pending = pendingResult ?: return
        pendingResult = null

        when {
            result.isCanceled -> {
                pending.success(mapOf(
                    "isSuccess" to false,
                    "isCanceled" to true,
                ))
            }
            result.resourcePath != null -> {
                pending.success(mapOf(
                    "isSuccess" to true,
                    "isCanceled" to false,
                    "resourcePath" to result.resourcePath,
                    "transactionType" to "sync",
                ))
            }
            else -> {
                pending.success(mapOf(
                    "isSuccess" to false,
                    "isCanceled" to false,
                    "errorCode" to "UNKNOWN",
                    "errorMessage" to "Unknown checkout result",
                ))
            }
        }
    }

    // endregion

    // region MethodCallHandler

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "setup" -> handleSetup(call, result)
            "checkoutReadyUI" -> handleCheckoutReadyUI(call, result)
            "payCustomUI" -> handlePayCustomUI(call, result, register = false)
            "registerCard" -> handlePayCustomUI(call, result, register = true)
            "payWithToken" -> handlePayWithToken(call, result)
            "payStcPay" -> handlePayStcPay(call, result)
            "payWithBrand" -> handlePayWithBrand(call, result)
            "payGooglePay" -> handlePayGooglePay(call, result)
            "paySamsungPay" -> handlePaySamsungPay(call, result)
            "klarnaCreateSession" -> handleKlarna(call, result, submitPayment = false)
            "klarnaSubmitPayment" -> handleKlarna(call, result, submitPayment = true)
            "validateCard" -> handleValidateCard(call, result)
            "payApplePay", "payApplePayDynamic" -> handlePayApplePay(result)
            "isApplePayAvailable" -> result.success(false)
            "requestBinInfo" -> handleRequestBinInfo(call, result)
            "getCheckoutInfo" -> handleGetCheckoutInfo(call, result)
            "getPaymentStatus" -> handleGetPaymentStatus(call, result)
            "getThreeDSWarnings" -> handleGetThreeDSWarnings(result)
            else -> result.notImplemented()
        }
    }

    private fun handleSetup(call: MethodCall, result: Result) {
        val mode = call.argument<String>("mode")
        providerMode = if (mode == "live") {
            Connect.ProviderMode.LIVE
        } else {
            Connect.ProviderMode.TEST
        }
        customUiThreeDSConfig = ArgumentMappers.map(call.argument<Any>("threeDSConfig"))?.let {
            ArgumentMappers.threeDSConfig(it)
        }
        paymentProvider = OppPaymentProvider(context!!, providerMode)
        paymentProvider?.setThreeDSWorkflowListener(object : ThreeDSWorkflowListener {
            override fun onThreeDSChallengeRequired(): Activity = activity!!

            override fun onThreeDSConfigRequired(): ThreeDSConfig =
                customUiThreeDSConfig ?: ThreeDSConfig.Builder().build()
        })
        result.success(null)
    }

    private fun handleCheckoutReadyUI(call: MethodCall, result: Result) {
        val currentActivity = activity ?: run {
            result.error("NO_ACTIVITY", "Plugin is not attached to an Activity", null)
            return
        }
        val launcher = checkoutLauncher ?: run {
            result.error("NO_LAUNCHER", "Checkout launcher not registered. Ensure your Activity extends ComponentActivity.", null)
            return
        }

        val checkoutId = call.argument<String>("checkoutId") ?: run {
            result.error("INVALID_ARGS", "checkoutId is required", null)
            return
        }
        val brands = call.argument<List<String>>("brands") ?: run {
            result.error("INVALID_ARGS", "brands is required", null)
            return
        }
        val googlePayConfig = ArgumentMappers.map(call.argument<Any>("googlePayConfig"))
        val lang = call.argument<String>("lang")
        val paymentBrand = call.argument<String>("paymentBrand")
        val options = ArgumentMappers.map(call.argument<Any>("options"))
        val threeDSConfig = ArgumentMappers.map(call.argument<Any>("threeDSConfig"))
        val hasBeforeSubmit = call.argument<Boolean>("hasBeforeSubmit") ?: false

        try {
            // LinkedHashSet keeps the brand order the app passed in.
            val paymentBrands = LinkedHashSet(brands)
            val checkoutSettings = CheckoutSettings(checkoutId, paymentBrands, providerMode)
            // NOTE: Do NOT skip CVV for stored cards by default. The SAIB MPGS
            // connector rejects stored-card preauth/debit transactions submitted
            // without a CVV as 800.100.156 (INVALID_REQUEST / "did not conform to
            // API protocol"). iOS always collects CVV and succeeds, so we match
            // that behaviour unless the app explicitly opts in via skipCvv.

            if (lang != null) {
                checkoutSettings.locale = lang
            }

            ArgumentMappers.applyCheckoutOptions(checkoutSettings, options, currentActivity)

            if (!paymentBrand.isNullOrEmpty()) {
                checkoutSettings.setPaymentButtonBrand(paymentBrand)
            }

            if (threeDSConfig != null) {
                checkoutSettings.setThreeDS2Config(ArgumentMappers.threeDSConfig(threeDSConfig))
            }

            if (hasBeforeSubmit) {
                checkoutSettings.setOnBeforeSubmitCallback(HyperpayBeforeSubmitCallback())
            }

            if (googlePayConfig != null) {
                checkoutSettings.setGooglePayPaymentDataRequestJson(
                    ArgumentMappers.googlePayPaymentDataRequest(googlePayConfig)
                )
            }

            pendingResult = result
            launcher.launch(checkoutSettings)
        } catch (e: Exception) {
            if (pendingResult === result) pendingResult = null
            result.error("CHECKOUT_ERROR", e.message, null)
        }
    }

    // region Your-own-UI payments

    private fun requireProvider(result: Result): OppPaymentProvider? {
        val provider = paymentProvider
        if (provider == null) {
            result.error("NOT_INITIALIZED", "Call setup() before making payments", null)
        }
        return provider
    }

    private fun requireArg(call: MethodCall, result: Result, name: String): String? {
        val value = call.argument<String>(name)
        if (value == null) {
            result.error("INVALID_ARGS", "$name is required", null)
        }
        return value
    }

    private fun shopperResultUrl(call: MethodCall): String? =
        call.argument<String>("shopperResultUrl")?.let { "${it}://callback" }

    /**
     * Builds the payment params and submits (or registers) them through the
     * shared listener / result path. Exceptions thrown while building params
     * or submitting become a PAYMENT_ERROR.
     */
    private fun submit(
        call: MethodCall,
        result: Result,
        register: Boolean = false,
        buildParams: () -> PaymentParams,
    ) {
        val provider = requireProvider(result) ?: return
        try {
            val paymentParams = buildParams()
            shopperResultUrl(call)?.let { paymentParams.shopperResultUrl = it }

            pendingResult = result

            val transaction = Transaction(paymentParams)
            if (register) {
                provider.registerTransaction(transaction, this)
            } else {
                provider.submitTransaction(transaction, this)
            }
        } catch (e: PaymentException) {
            if (pendingResult === result) pendingResult = null
            result.error(
                "PAYMENT_ERROR",
                e.error?.errorMessage ?: e.message ?: "Unknown payment error",
                null
            )
        } catch (e: Exception) {
            if (pendingResult === result) pendingResult = null
            result.error("PAYMENT_ERROR", e.message, null)
        }
    }

    private fun handlePayCustomUI(call: MethodCall, result: Result, register: Boolean) {
        if (paymentProvider == null) {
            result.error("NOT_INITIALIZED", "Call setup() before making payments", null)
            return
        }

        val checkoutId = requireArg(call, result, "checkoutId") ?: return
        val brand = call.argument<String>("brand")?.takeIf { it.isNotEmpty() }
        val cardNumber = requireArg(call, result, "cardNumber") ?: return
        val holder = requireArg(call, result, "holder") ?: return
        val expiryMonth = requireArg(call, result, "expiryMonth") ?: return
        val expiryYear = requireArg(call, result, "expiryYear") ?: return
        val cvv = requireArg(call, result, "cvv") ?: return
        val tokenize = !register && (call.argument<Boolean>("tokenize") ?: false)

        submit(call, result, register) {
            val paymentParams = if (brand != null) {
                CardPaymentParams(checkoutId, brand, cardNumber, holder, expiryMonth, expiryYear, cvv)
            } else {
                CardPaymentParams(checkoutId, cardNumber, holder, expiryMonth, expiryYear, cvv)
            }
            if (tokenize) {
                paymentParams.isTokenizationEnabled = true
            }
            paymentParams
        }
    }

    private fun handlePayWithToken(call: MethodCall, result: Result) {
        if (requireProvider(result) == null) return
        val checkoutId = requireArg(call, result, "checkoutId") ?: return
        val tokenId = requireArg(call, result, "tokenId") ?: return
        val brand = requireArg(call, result, "brand") ?: return
        val cvv = call.argument<String>("cvv")?.takeIf { it.isNotEmpty() }

        submit(call, result) {
            if (cvv != null) {
                TokenPaymentParams(checkoutId, tokenId, brand, cvv)
            } else {
                TokenPaymentParams(checkoutId, tokenId, brand)
            }
        }
    }

    private fun handlePayStcPay(call: MethodCall, result: Result) {
        if (requireProvider(result) == null) return
        val checkoutId = requireArg(call, result, "checkoutId") ?: return
        val option = when (call.argument<String>("verificationOption")) {
            "qrCode" -> STCPayVerificationOption.QR_CODE
            "mobilePhone", null -> STCPayVerificationOption.MOBILE_PHONE
            else -> {
                result.error("INVALID_ARGS", "verificationOption must be mobilePhone or qrCode", null)
                return
            }
        }
        val mobilePhone = call.argument<String>("mobilePhone")?.takeIf { it.isNotEmpty() }

        submit(call, result) {
            STCPayPaymentParams(checkoutId, option).also { params ->
                mobilePhone?.let { params.setMobilePhoneNumber(it) }
            }
        }
    }

    private fun handlePayWithBrand(call: MethodCall, result: Result) {
        if (requireProvider(result) == null) return
        val checkoutId = requireArg(call, result, "checkoutId") ?: return
        val brand = requireArg(call, result, "brand") ?: return
        val parameters = ArgumentMappers.stringMap(call.argument<Any>("parameters"))

        submit(call, result) {
            PaymentParams(checkoutId, brand).also { params ->
                parameters?.forEach { (name, value) ->
                    if (!params.addParam(name, value)) {
                        android.util.Log.w("HyperpaySdk", "payWithBrand: SDK rejected parameter '$name'")
                    }
                }
            }
        }
    }

    private fun handlePayGooglePay(call: MethodCall, result: Result) {
        if (requireProvider(result) == null) return
        val checkoutId = requireArg(call, result, "checkoutId") ?: return
        val paymentToken = requireArg(call, result, "paymentToken") ?: return
        val rawCardBrand = requireArg(call, result, "cardBrand") ?: return
        val brand = call.argument<String>("brand")?.takeIf { it.isNotEmpty() }
        // Google Pay reports MASTERCARD; OPPWA's brand is MASTER.
        val cardBrand = if (rawCardBrand.equals("MASTERCARD", ignoreCase = true)) "MASTER" else rawCardBrand

        submit(call, result) {
            if (brand != null) {
                GooglePayPaymentParams(checkoutId, paymentToken, cardBrand, brand)
            } else {
                GooglePayPaymentParams(checkoutId, paymentToken, cardBrand)
            }
        }
    }

    private fun handlePaySamsungPay(call: MethodCall, result: Result) {
        if (requireProvider(result) == null) return
        val checkoutId = requireArg(call, result, "checkoutId") ?: return
        val credential = requireArg(call, result, "paymentCredential") ?: return
        val brand = call.argument<String>("brand")?.takeIf { it.isNotEmpty() }

        submit(call, result) {
            if (brand != null) {
                SamsungPayPaymentParams(checkoutId, credential, brand)
            } else {
                SamsungPayPaymentParams(checkoutId, credential)
            }
        }
    }

    // endregion

    // region Klarna Inline

    private fun handleKlarna(call: MethodCall, result: Result, submitPayment: Boolean) {
        val provider = requireProvider(result) ?: return
        val checkoutId = requireArg(call, result, "checkoutId") ?: return
        val brand = requireArg(call, result, "brand") ?: return
        val initialTransactionId = if (submitPayment) {
            requireArg(call, result, "initialTransactionId") ?: return
        } else {
            null
        }

        try {
            val params = KlarnaInlinePaymentParams(checkoutId, brand)
            initialTransactionId?.let { params.setInitialTransactionId(it) }
            shopperResultUrl(call)?.let { params.shopperResultUrl = it }

            provider.submitTransaction(Transaction(params), object : ITransactionListener {
                override fun transactionCompleted(transaction: Transaction) {
                    val info = transaction.brandSpecificInfo ?: emptyMap()
                    val session = mapOf(
                        "clientToken" to info[Transaction.KLARNA_INLINE_CLIENT_TOKEN_KEY],
                        "initialTransactionId" to (info[Transaction.KLARNA_INLINE_INITIAL_TRANSACTION_ID]
                            ?: initialTransactionId),
                        "callbackUrl" to info[Transaction.KLARNA_INLINE_CALLBACK_URL_KEY],
                        "failureCallbackUrl" to info[Transaction.KLARNA_INLINE_FAILURE_CALLBACK_URL_KEY],
                        "paymentCategory" to klarnaPaymentCategory(brand),
                    )
                    HyperpayCallbackBridge.runOnMain { result.success(session) }
                }

                override fun transactionFailed(transaction: Transaction, paymentError: PaymentError) {
                    HyperpayCallbackBridge.runOnMain {
                        result.error(
                            "KLARNA_ERROR",
                            paymentError.errorMessage ?: "Klarna request failed",
                            paymentError.errorCode.toString()
                        )
                    }
                }
            })
        } catch (e: PaymentException) {
            result.error("KLARNA_ERROR", e.error?.errorMessage ?: e.message ?: "Klarna request failed", null)
        } catch (e: Exception) {
            result.error("KLARNA_ERROR", e.message, null)
        }
    }

    private fun klarnaPaymentCategory(brand: String): String? = when {
        brand.endsWith("PAYLATER") -> "pay_later"
        brand.endsWith("SLICEIT") -> "pay_over_time"
        brand.endsWith("PAYNOW") -> "pay_now"
        brand.endsWith("_ONE") -> "klarna"
        else -> null
    }

    // endregion

    // region Card validation

    private fun handleValidateCard(call: MethodCall, result: Result) {
        val number = call.argument<String>("number")
        val holder = call.argument<String>("holder")
        val expiryMonth = call.argument<String>("expiryMonth")
        val expiryYear = call.argument<String>("expiryYear")
        val cvv = call.argument<String>("cvv")
        val brand = call.argument<String>("brand")?.takeIf { it.isNotEmpty() }
        val luhnCheck = call.argument<Boolean>("luhnCheck") ?: true

        val out = HashMap<String, Any?>()
        try {
            number?.let { out["numberValid"] = CardPaymentParams.isNumberValid(it, luhnCheck) }
            holder?.let { out["holderValid"] = CardPaymentParams.isHolderValid(it) }
            expiryMonth?.let { out["expiryMonthValid"] = CardPaymentParams.isExpiryMonthValid(it) }
            expiryYear?.let { out["expiryYearValid"] = CardPaymentParams.isExpiryYearValid(it) }
            // Like iOS: only judge expiry for a well-formed month and year.
            if (expiryMonth != null && expiryYear != null &&
                CardPaymentParams.isExpiryMonthValid(expiryMonth) &&
                CardPaymentParams.isExpiryYearValid(expiryYear)
            ) {
                out["expired"] = CardPaymentParams.isCardExpired(expiryMonth, expiryYear)
            }
            cvv?.let {
                // SDK check is 3–4 digits; tighten to the brand's length when known.
                val sdkValid = BaseCardPaymentParams.isCvvValid(it)
                val lengthValid = when {
                    brand == null -> true
                    brand.equals("AMEX", ignoreCase = true) -> it.length == 4
                    else -> it.length == 3
                }
                out["cvvValid"] = sdkValid && lengthValid
            }
            result.success(out)
        } catch (e: Exception) {
            result.error("VALIDATION_ERROR", e.message, null)
        }
    }

    // endregion

    private fun handlePayApplePay(result: Result) {
        result.error("UNSUPPORTED", "Apple Pay is not available on Android", null)
    }

    private fun handleRequestBinInfo(call: MethodCall, result: Result) {
        val provider = paymentProvider ?: run {
            result.error("NOT_INITIALIZED", "Call setup() before requesting BIN info", null)
            return
        }
        val checkoutId = call.argument<String>("checkoutId") ?: run {
            result.error("INVALID_ARGS", "checkoutId is required", null)
            return
        }
        val bin = call.argument<String>("bin") ?: run {
            result.error("INVALID_ARGS", "bin is required", null)
            return
        }

        // The SDK only allows a BIN lookup right after the checkout info was
        // requested ("Malformed server response" otherwise), and a payment can
        // reset that state, so fetch the info before every lookup.
        requestCheckoutInfo(
            provider,
            checkoutId,
            onSuccess = { requestBinInfo(provider, checkoutId, bin, result) },
            onFailure = { message, code ->
                result.error(
                    "BIN_INFO_ERROR",
                    "Checkout info request failed: ${message ?: "unknown error"}",
                    code
                )
            },
        )
    }

    private fun requestBinInfo(provider: OppPaymentProvider, checkoutId: String, bin: String, result: Result) {
        provider.requestBinInfo(checkoutId, bin, object : BinInfoListener {
            override fun onResult(binInfo: BinInfo?, paymentError: PaymentError?) {
                HyperpayCallbackBridge.runOnMain {
                    if (paymentError != null) {
                        result.error(
                            "BIN_INFO_ERROR",
                            "BIN info request failed: ${paymentError.errorMessage ?: "unknown error"}",
                            paymentError.errorCode.toString()
                        )
                        return@runOnMain
                    }
                    result.success(mapOf(
                        "brands" to (binInfo?.brands?.toList() ?: emptyList<String>()),
                        "binType" to binInfo?.binType,
                        "type" to binInfo?.type,
                    ))
                }
            }
        })
    }

    // region Checkout info / status

    /** Requests the checkout info; exactly one of the callbacks runs, on the main thread. */
    private fun requestCheckoutInfo(
        provider: OppPaymentProvider,
        checkoutId: String,
        onSuccess: (CheckoutInfo) -> Unit,
        onFailure: (String?, String?) -> Unit,
    ) {
        try {
            provider.requestCheckoutInfo(checkoutId, object : ITransactionListener {
                override fun transactionCompleted(transaction: Transaction) {}

                override fun transactionFailed(transaction: Transaction, paymentError: PaymentError) {}

                override fun paymentConfigRequestSucceeded(checkoutInfo: CheckoutInfo) {
                    HyperpayCallbackBridge.runOnMain { onSuccess(checkoutInfo) }
                }

                override fun paymentConfigRequestFailed(paymentError: PaymentError) {
                    HyperpayCallbackBridge.runOnMain {
                        onFailure(paymentError.errorMessage, paymentError.errorCode.toString())
                    }
                }
            })
        } catch (e: PaymentException) {
            onFailure(e.error?.errorMessage ?: e.message, e.error?.errorCode?.toString())
        } catch (e: Exception) {
            onFailure(e.message, null)
        }
    }

    private fun handleGetCheckoutInfo(call: MethodCall, result: Result) {
        val provider = requireProvider(result) ?: return
        val checkoutId = requireArg(call, result, "checkoutId") ?: return
        requestCheckoutInfo(
            provider,
            checkoutId,
            onSuccess = { info -> result.success(ArgumentMappers.checkoutInfoMap(info)) },
            onFailure = { message, code ->
                result.error("CHECKOUT_INFO_ERROR", message ?: "Checkout info request failed", code)
            },
        )
    }

    private fun handleGetPaymentStatus(call: MethodCall, result: Result) {
        val checkoutId = call.argument<String>("checkoutId")
        val resourcePath = call.argument<String>("resourcePath")

        // Payment status verification should be done server-side.
        // This method provides the resource path to the Dart layer so
        // the app can call its backend to verify.
        val base = mapOf(
            "status" to "PENDING_SERVER_VERIFICATION",
            "resourcePath" to resourcePath,
        )

        // Enrich with the checkout info (amount, currency, tokens) when possible;
        // fall back to the plain map on any failure.
        val provider = paymentProvider
        if (provider == null || checkoutId.isNullOrEmpty()) {
            result.success(base)
            return
        }
        requestCheckoutInfo(
            provider,
            checkoutId,
            onSuccess = { info ->
                val merged = HashMap<String, Any?>(ArgumentMappers.checkoutInfoMap(info))
                merged["status"] = "PENDING_SERVER_VERIFICATION"
                merged["resourcePath"] = resourcePath ?: info.resourcePath
                result.success(merged)
            },
            onFailure = { _, _ -> result.success(base) },
        )
    }

    private fun handleGetThreeDSWarnings(result: Result) {
        val provider = requireProvider(result) ?: return
        try {
            val warnings = provider.threeDS2Warnings ?: emptyList()
            result.success(warnings.map { warning ->
                mapOf(
                    "id" to warning.id,
                    "message" to warning.message,
                    "severity" to warning.severity?.name,
                )
            })
        } catch (e: PaymentException) {
            result.error("THREE_DS_WARNINGS_ERROR", e.error?.errorMessage ?: e.message, null)
        } catch (e: Exception) {
            result.error("THREE_DS_WARNINGS_ERROR", e.message, null)
        }
    }

    // endregion

    // endregion

    // region ITransactionListener

    override fun transactionCompleted(transaction: Transaction) {
        HyperpayCallbackBridge.runOnMain { onTransactionCompleted(transaction) }
    }

    override fun transactionFailed(transaction: Transaction, paymentError: PaymentError) {
        HyperpayCallbackBridge.runOnMain { onTransactionFailed(paymentError) }
    }

    private fun onTransactionCompleted(transaction: Transaction) {
        val pending = pendingResult ?: return
        pendingResult = null

        if (transaction.transactionType == TransactionType.SYNC) {
            pending.success(mapOf(
                "isSuccess" to true,
                "isCanceled" to false,
                "transactionType" to "sync",
            ))
        } else {
            // Async transaction — need to redirect
            val redirectUrl = transaction.redirectUrl
            if (redirectUrl != null && activity != null) {
                try {
                    val browserIntent = Intent(Intent.ACTION_VIEW, Uri.parse(redirectUrl))
                    activity!!.startActivity(browserIntent)
                } catch (_: Exception) {
                    // Browser open failed, still return the result
                }
            }
            pending.success(mapOf(
                "isSuccess" to true,
                "isCanceled" to false,
                "transactionType" to "async",
            ))
        }
    }

    private fun onTransactionFailed(paymentError: PaymentError) {
        val pending = pendingResult ?: return
        pendingResult = null

        // Shopper-initiated aborts (closing the payment page or dismissing the
        // 3-D Secure challenge) are cancellations, not failures — report them as
        // such so the app silently aborts instead of showing a raw error.
        if (isUserCancellation(paymentError.errorCode)) {
            pending.success(mapOf(
                "isSuccess" to false,
                "isCanceled" to true,
            ))
            return
        }

        pending.success(mapOf(
            "isSuccess" to false,
            "isCanceled" to false,
            "errorCode" to paymentError.errorCode.toString(),
            // Like iOS, append the SDK's error details: for server rejections
            // they hold HyperPay's result code and parameterErrors, while
            // errorMessage alone is a generic "Malformed server response".
            "errorMessage" to listOfNotNull(
                paymentError.errorMessage,
                paymentError.errorInfo?.takeIf { it.isNotBlank() }?.let { "[$it]" },
            ).joinToString(" "),
        ))
    }

    // ERROR_CODE_GENERAL_CANCEL was added in OPPWA 7.11.0 and is raised when the
    // shopper dismisses a processor-owned sheet (e.g. Paze, Braintree/PayPal).
    private fun isUserCancellation(errorCode: ErrorCode): Boolean {
        return errorCode == ErrorCode.ERROR_CODE_TRANSACTION_ABORTED ||
            errorCode == ErrorCode.ERROR_CODE_THREEDS2_CANCELED ||
            errorCode == ErrorCode.ERROR_CODE_GENERAL_CANCEL
    }

    // endregion
}
