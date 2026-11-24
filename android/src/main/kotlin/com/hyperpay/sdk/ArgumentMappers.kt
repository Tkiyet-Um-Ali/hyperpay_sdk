package com.hyperpay.sdk

import android.content.Context
import android.util.Log
import com.nsoftware.ipworks3ds.sdk.customization.ButtonCustomization
import com.nsoftware.ipworks3ds.sdk.customization.Customization
import com.nsoftware.ipworks3ds.sdk.customization.LabelCustomization
import com.nsoftware.ipworks3ds.sdk.customization.TextBoxCustomization
import com.nsoftware.ipworks3ds.sdk.customization.ToolbarCustomization
import com.nsoftware.ipworks3ds.sdk.customization.UiCustomization
import com.oppwa.mobile.connect.checkout.meta.CheckoutBrandDetectionAppearanceStyle
import com.oppwa.mobile.connect.checkout.meta.CheckoutBrandDetectionType
import com.oppwa.mobile.connect.checkout.meta.CheckoutSecurityPolicyMode
import com.oppwa.mobile.connect.checkout.meta.CheckoutSettings
import com.oppwa.mobile.connect.checkout.meta.CheckoutSkipCVVMode
import com.oppwa.mobile.connect.checkout.meta.CheckoutStorePaymentDetailsMode
import com.oppwa.mobile.connect.checkout.meta.GooglePaySubmitType
import com.oppwa.mobile.connect.checkout.meta.WpwlOptions
import com.oppwa.mobile.connect.payment.BillingAddress
import com.oppwa.mobile.connect.payment.CheckoutInfo
import com.oppwa.mobile.connect.payment.token.Token
import com.oppwa.mobile.connect.provider.threeds.v2.model.ChallengeUiType
import com.oppwa.mobile.connect.provider.threeds.v2.model.ThreeDSConfig
import com.oppwa.mobile.connect.utils.googlepay.CardPaymentMethodJsonBuilder
import com.oppwa.mobile.connect.utils.googlepay.PaymentDataRequestJsonBuilder
import com.oppwa.mobile.connect.utils.googlepay.TransactionInfoJsonBuilder
import org.json.JSONArray
import org.json.JSONObject
import java.util.EnumSet

/** Converts the Dart-side argument maps into OPPWA SDK objects. */
internal object ArgumentMappers {
    private const val TAG = "HyperpaySdk"

    // region Generic helpers

    @Suppress("UNCHECKED_CAST")
    fun map(value: Any?): Map<String, Any?>? = value as? Map<String, Any?>

    fun stringList(value: Any?): List<String>? =
        (value as? List<*>)?.mapNotNull { it?.toString() }

    fun stringMap(value: Any?): Map<String, String>? =
        (value as? Map<*, *>)?.entries
            ?.filter { it.key != null && it.value != null }
            ?.associate { it.key.toString() to it.value.toString() }

    private fun bool(value: Any?): Boolean? = value as? Boolean

    private fun int(value: Any?): Int? = (value as? Number)?.toInt()

    /** ARGB int (Int or Long from the codec) → "#RRGGBB" / "#AARRGGBB". */
    private fun hexColor(value: Any?): String? {
        val argb = (value as? Number)?.toLong() ?: return null
        val alpha = (argb shr 24) and 0xFF
        val rgb = argb and 0xFFFFFF
        return if (alpha == 0xFFL) {
            String.format("#%06X", rgb)
        } else {
            String.format("#%02X%06X", alpha, rgb)
        }
    }

    // endregion

    // region CheckoutOptions

    fun applyCheckoutOptions(settings: CheckoutSettings, options: Map<String, Any?>?, context: Context) {
        val o = options ?: emptyMap()

        // Store payment details: default PROMPT (matches iOS).
        settings.setStorePaymentDetailsMode(
            when (o["storePaymentDetails"] as? String) {
                "never" -> CheckoutStorePaymentDetailsMode.NEVER
                "always" -> CheckoutStorePaymentDetailsMode.ALWAYS
                else -> CheckoutStorePaymentDetailsMode.PROMPT
            }
        )

        when (o["skipCvv"] as? String) {
            "never" -> settings.setSkipCVVMode(CheckoutSkipCVVMode.NEVER)
            "forStoredCards" -> settings.setSkipCVVMode(CheckoutSkipCVVMode.FOR_STORED_CARDS)
            "always" -> settings.setSkipCVVMode(CheckoutSkipCVVMode.ALWAYS)
        }

        bool(o["cardHolderVisible"])?.let { settings.setCardHolderVisible(it) }
        (o["cardHolderPattern"] as? String)?.takeIf { it.isNotEmpty() }?.let {
            settings.setPaymentFormListener(HyperpayCardHolderFormListener(it))
        }
        bool(o["displayTotalAmount"])?.let { settings.setTotalAmountRequired(it) }
        bool(o["backButtonAvailable"])?.let { settings.setBackButtonAvailable(it) }
        bool(o["installmentEnabled"])?.let { settings.setInstallmentEnabled(it) }
        (o["installmentOptions"] as? List<*>)?.mapNotNull { int(it) }?.let {
            settings.setInstallmentOptions(it.toTypedArray())
        }
        map(o["billingAddress"])?.let { settings.setBillingAddress(billingAddress(it)) }

        when (o["brandDetectionType"] as? String) {
            "regex" -> settings.setBrandDetectionType(CheckoutBrandDetectionType.REGEX)
            "binList" -> settings.setBrandDetectionType(CheckoutBrandDetectionType.BINLIST)
            "binListAndType" -> settings.setBrandDetectionType(CheckoutBrandDetectionType.BINLIST_AND_TYPE)
        }
        stringList(o["brandDetectionPriority"])?.let { settings.setBrandDetectionPriority(it) }
        when (o["brandDetectionAppearanceStyle"] as? String) {
            "active" -> settings.setBrandDetectionAppearanceStyle(CheckoutBrandDetectionAppearanceStyle.ACTIVE)
            "inactive" -> settings.setBrandDetectionAppearanceStyle(CheckoutBrandDetectionAppearanceStyle.INACTIVE)
            "none" -> settings.setBrandDetectionAppearanceStyle(CheckoutBrandDetectionAppearanceStyle.NONE)
        }

        securityPolicy(o["tokensSecurityPolicy"])?.let { settings.setSecurityPolicyModeForTokens(it) }
        (o["brandSecurityPolicies"] as? Map<*, *>)?.forEach { (brand, mode) ->
            val policy = securityPolicy(mode)
            if (brand != null && policy != null) {
                settings.setSecurityPolicyModeForBrand(brand.toString(), policy)
            }
        }

        bool(o["cardScanningEnabled"])?.let { settings.setCardScanningEnabled(it) }

        stringMap(o["androidCustomLogoDrawables"])?.forEach { (brand, name) ->
            val id = resourceId(context, name, "drawable")
            if (id != 0) {
                settings.setCustomLogo(brand, id)
            } else {
                Log.w(TAG, "Custom logo drawable '$name' for $brand not found, skipping")
            }
        }
        (o["androidThemeResource"] as? String)?.takeIf { it.isNotEmpty() }?.let { name ->
            val id = resourceId(context, name, "style")
            if (id != 0) {
                settings.setThemeResId(id)
            } else {
                Log.w(TAG, "Theme style '$name' not found, skipping")
            }
        }

        stringList(o["googlePaySubmitTypes"])?.let { types ->
            val set = EnumSet.noneOf(GooglePaySubmitType::class.java)
            types.forEach {
                when (it) {
                    "billing" -> set.add(GooglePaySubmitType.BILLING)
                    "customer" -> set.add(GooglePaySubmitType.CUSTOMER)
                }
            }
            settings.setGooglePaySubmit(set)
        }

        bool(o["stcPayQrCodeRequired"])?.let { settings.setSTCPayQrCodeRequired(it) }
        bool(o["cardExpiryDateValidationDisabled"])?.let { settings.setCardExpiryDateValidationDisabled(it) }
        bool(o["ibanRequired"])?.let { settings.setIBANRequired(it) }
        bool(o["windowSecurityEnabled"])?.let { settings.setWindowSecurityEnabled(it) }
        bool(o["showBirthDate"])?.let { settings.setShowBirthDate(it) }
        bool(o["paymentBrandsOrderUsedForTokens"])?.let { settings.setPaymentBrandsOrderUsedForTokens(it) }

        (o["wpwlOptions"] as? Map<*, *>)?.let { perBrand ->
            val result = HashMap<String, WpwlOptions>()
            perBrand.forEach { (brand, raw) ->
                val m = map(raw) ?: return@forEach
                if (brand == null) return@forEach
                val wpwl = WpwlOptions()
                (m["configuration"] as? Map<*, *>)?.forEach { (key, value) ->
                    if (key != null && value != null) wpwl.addValue(key.toString(), wpwlValue(value))
                }
                stringMap(m["jsFunctions"])?.forEach { (key, fn) -> wpwl.addJSFunction(key, fn) }
                result[brand.toString()] = wpwl
            }
            if (result.isNotEmpty()) settings.setWpwlOptions(result)
        }
    }

    private fun securityPolicy(value: Any?): CheckoutSecurityPolicyMode? = when (value as? String) {
        "notRequired" -> CheckoutSecurityPolicyMode.DEVICE_AUTH_NOT_REQUIRED
        "requiredIfAvailable" -> CheckoutSecurityPolicyMode.DEVICE_AUTH_REQUIRED_IF_AVAILABLE
        "required" -> CheckoutSecurityPolicyMode.DEVICE_AUTH_REQUIRED
        else -> null
    }

    // getIdentifier is the only way to resolve a resource the app names at runtime.
    @Suppress("DiscouragedApi")
    private fun resourceId(context: Context, name: String, type: String): Int =
        context.resources.getIdentifier(name, type, context.packageName)

    /**
     * WpwlOptions renders Strings quoted, Object[] as string arrays and anything
     * else via toString(), so nested maps / lists become JSON.
     */
    private fun wpwlValue(value: Any): Any = when (value) {
        is List<*> -> if (value.all { it is String }) {
            value.map { it.toString() }.toTypedArray()
        } else {
            jsonValue(value) ?: value
        }
        is Map<*, *> -> jsonValue(value) ?: value
        else -> value
    }

    private fun jsonValue(value: Any?): Any? = when (value) {
        is Map<*, *> -> JSONObject().also { obj ->
            value.forEach { (k, v) -> if (k != null) obj.put(k.toString(), jsonValue(v)) }
        }
        is List<*> -> JSONArray().also { arr -> value.forEach { arr.put(jsonValue(it)) } }
        null -> JSONObject.NULL
        else -> value
    }

    private fun billingAddress(m: Map<String, Any?>): BillingAddress {
        val builder = BillingAddress.Builder()
        (m["country"] as? String)?.let { builder.setCountry(it) }
        (m["state"] as? String)?.let { builder.setState(it) }
        (m["city"] as? String)?.let { builder.setCity(it) }
        (m["postCode"] as? String)?.let { builder.setPostCode(it) }
        (m["street1"] as? String)?.let { builder.setStreet1(it) }
        (m["street2"] as? String)?.let { builder.setStreet2(it) }
        bool(m["countryRequired"])?.let { builder.setCountryRequired(it) }
        bool(m["stateRequired"])?.let { builder.setStateRequired(it) }
        bool(m["cityRequired"])?.let { builder.setCityRequired(it) }
        bool(m["postCodeRequired"])?.let { builder.setPostCodeRequired(it) }
        bool(m["street1Required"])?.let { builder.setStreet1Required(it) }
        bool(m["street2Required"])?.let { builder.setStreet2Required(it) }
        return builder.build()
    }

    // endregion

    // region Google Pay

    fun googlePayPaymentDataRequest(config: Map<String, Any?>): String {
        val merchantId = config["gatewayMerchantId"] as? String ?: ""
        val merchantName = config["merchantName"] as? String ?: ""
        val countryCode = config["countryCode"] as? String ?: ""
        val totalPrice = (config["totalPrice"] as? Number)?.toDouble() ?: 0.0
        val currencyCode = config["currencyCode"] as? String ?: ""

        val networks = stringList(config["allowedCardNetworks"])?.takeIf { it.isNotEmpty() }
            ?: listOf("VISA", "MASTERCARD")
        val authMethods = stringList(config["allowedAuthMethods"])?.takeIf { it.isNotEmpty() }
            ?: listOf("PAN_ONLY", "CRYPTOGRAM_3DS")

        val cardMethod = CardPaymentMethodJsonBuilder()
            .setAllowedAuthMethods(JSONArray(authMethods))
            .setAllowedCardNetworks(JSONArray(networks))
            .setGatewayMerchantId(merchantId)
        (config["gateway"] as? String)?.takeIf { it.isNotEmpty() }?.let { cardMethod.setGateway(it) }
        if (bool(config["billingAddressRequired"]) == true) {
            cardMethod.setBillingAddressRequired(true)
            cardMethod.setBillingAddressParameters(
                (config["billingAddressFormat"] as? String) ?: "FULL",
                bool(config["phoneNumberRequired"]) ?: false,
            )
        }

        val transactionInfo = TransactionInfoJsonBuilder()
            .setCurrencyCode(currencyCode)
            .setTotalPriceStatus((config["totalPriceStatus"] as? String) ?: "FINAL")
            .setTotalPrice(totalPrice.toString())
            .setCountryCode(countryCode)
            .toJson()

        val request = PaymentDataRequestJsonBuilder()
            .setAllowedPaymentMethods(JSONArray().put(cardMethod.toJson()))
            .setTransactionInfo(transactionInfo)
        if (merchantName.isNotEmpty()) request.setMerchantInfo(merchantName)
        if (bool(config["emailRequired"]) == true) request.setEmailRequired(true)
        if (bool(config["shippingAddressRequired"]) == true) request.setShippingAddressRequired(true)

        return request.toJson().toString()
    }

    // endregion

    // region 3-D Secure 2

    fun threeDSConfig(m: Map<String, Any?>): ThreeDSConfig {
        val builder = ThreeDSConfig.Builder()

        stringList(m["challengeUiTypes"])?.let { names ->
            val set = EnumSet.noneOf(ChallengeUiType::class.java)
            names.forEach { name ->
                when (name) {
                    "text" -> set.add(ChallengeUiType.TEXT)
                    "singleSelect" -> set.add(ChallengeUiType.SINGLE_SELECT)
                    "multiSelect" -> set.add(ChallengeUiType.MULTI_SELECT)
                    "oob" -> set.add(ChallengeUiType.OOB)
                    "html" -> set.add(ChallengeUiType.HTML)
                    "htmlOob" -> set.add(ChallengeUiType.HTML_OOB)
                    "information" -> set.add(ChallengeUiType.INFORMATION)
                }
            }
            if (set.isNotEmpty()) builder.setChallengeUiTypes(set)
        }
        int(m["sdkMaxTimeout"])?.let { builder.setSdkMaxTimeout(it) }
        (m["locale"] as? String)?.let { builder.setLocale(it) }
        stringList(m["deviceParameterBlacklist"])?.let { builder.setDeviceParameterBlacklist(it.toTypedArray()) }
        stringMap(m["clientConfigParams"])?.forEach { (k, v) -> builder.addClientConfigParam(k, v) }
        (m["requestorAppUrl"] as? String)?.takeIf { it.isNotEmpty() }?.let {
            builder.setThreeDSRequestorAppUrlUsed(true)
        }
        bool(m["browserDataRequired"])?.let { builder.setBrowserDataRequired(it) }
        (m["appSignature"] as? String)?.let { builder.setAppSignature(it) }
        stringList(m["trustedAppStores"])?.let { builder.setTrustedAppStores(it.toTypedArray()) }
        stringList(m["maliciousApps"])?.let { builder.setMaliciousApps(it.toTypedArray()) }

        map(m["uiCustomization"])?.let { raw ->
            try {
                builder.setUiCustomization(uiCustomization(raw))
            } catch (e: Exception) {
                Log.w(TAG, "Invalid 3DS uiCustomization, ignoring it", e)
            }
        }
        return builder.build()
    }

    private fun applyTextStyle(target: Customization, m: Map<String, Any?>) {
        hexColor(m["textColor"])?.let { target.setTextColor(it) }
        (m["fontName"] as? String)?.let { target.setTextFontName(it) }
        int(m["fontSize"])?.let { target.setTextFontSize(it) }
    }

    private fun uiCustomization(m: Map<String, Any?>): UiCustomization {
        val ui = UiCustomization()

        map(m["toolbar"])?.let { t ->
            val toolbar = ToolbarCustomization()
            applyTextStyle(toolbar, t)
            hexColor(t["backgroundColor"])?.let { toolbar.setBackgroundColor(it) }
            (t["headerText"] as? String)?.let { toolbar.setHeaderText(it) }
            (t["buttonText"] as? String)?.let { toolbar.setButtonText(it) }
            ui.setToolbarCustomization(toolbar)
        }

        map(m["label"])?.let { l ->
            val label = LabelCustomization()
            applyTextStyle(label, l)
            map(l["heading"])?.let { h ->
                hexColor(h["textColor"])?.let { label.setHeadingTextColor(it) }
                (h["fontName"] as? String)?.let { label.setHeadingTextFontName(it) }
                int(h["fontSize"])?.let { label.setHeadingTextFontSize(it) }
            }
            ui.setLabelCustomization(label)
        }

        map(m["textBox"])?.let { t ->
            val textBox = TextBoxCustomization()
            applyTextStyle(textBox, t)
            int(t["borderWidth"])?.let { textBox.setBorderWidth(it) }
            hexColor(t["borderColor"])?.let { textBox.setBorderColor(it) }
            int(t["cornerRadius"])?.let { textBox.setCornerRadius(it) }
            ui.setTextBoxCustomization(textBox)
        }

        (m["buttons"] as? Map<*, *>)?.forEach { (name, raw) ->
            val type = when (name) {
                "submit" -> UiCustomization.ButtonType.SUBMIT
                "continueButton" -> UiCustomization.ButtonType.CONTINUE
                "next" -> UiCustomization.ButtonType.NEXT
                "cancel" -> UiCustomization.ButtonType.CANCEL
                "resend" -> UiCustomization.ButtonType.RESEND
                else -> null
            } ?: return@forEach
            val b = map(raw) ?: return@forEach
            val button = ButtonCustomization()
            applyTextStyle(button, b)
            hexColor(b["backgroundColor"])?.let { button.setBackgroundColor(it) }
            int(b["cornerRadius"])?.let { button.setCornerRadius(it) }
            ui.setButtonCustomization(button, type)
        }

        return ui
    }

    // endregion

    // region Checkout info

    fun checkoutInfoMap(info: CheckoutInfo): Map<String, Any?> = mapOf(
        "amount" to info.amount,
        "currencyCode" to info.currencyCode,
        "resourcePath" to info.resourcePath,
        "tokens" to (info.tokens?.map { tokenMap(it) } ?: emptyList<Map<String, Any?>>()),
        "brands" to (info.brands?.toList() ?: emptyList<String>()),
    )

    private fun tokenMap(token: Token): Map<String, Any?> {
        val card = token.card
        val bank = token.bankAccount
        val virtual = token.virtualAccount
        return mapOf(
            "tokenId" to token.tokenId,
            "paymentBrand" to token.paymentBrand,
            "cardHolder" to card?.holder,
            "cardLast4Digits" to card?.last4Digits,
            "cardExpiryMonth" to card?.expiryMonth,
            "cardExpiryYear" to card?.expiryYear,
            "bankAccountHolder" to bank?.holder,
            "iban" to bank?.iban,
            "virtualAccountId" to virtual?.accountId,
            "virtualAccountHolder" to virtual?.holder,
        )
    }

    // endregion
}
