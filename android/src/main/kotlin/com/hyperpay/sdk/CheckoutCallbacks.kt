package com.hyperpay.sdk

import android.os.Handler
import android.os.Looper
import android.os.Parcel
import android.os.Parcelable
import android.util.Log
import com.oppwa.mobile.connect.checkout.dialog.IPaymentFormListener
import com.oppwa.mobile.connect.checkout.meta.CheckoutValidationResult
import com.oppwa.mobile.connect.checkout.meta.OnBeforeSubmitCallback
import com.oppwa.mobile.connect.checkout.meta.PaymentDetails
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean
import java.util.regex.Pattern
import java.util.regex.PatternSyntaxException

/**
 * Process-wide link between the Parcelable Ready-UI callbacks (which the OPPWA
 * SDK parcels into the CheckoutActivity intent, so they cannot hold references)
 * and the plugin's method channel.
 */
internal object HyperpayCallbackBridge {
    private const val TAG = "HyperpaySdk"

    @Volatile
    var channel: MethodChannel? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    fun runOnMain(block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) block() else mainHandler.post(block)
    }

    /**
     * Asks Dart whether to continue submitting. [listener] is completed exactly
     * once; any failure on the Dart side aborts the payment.
     */
    fun dispatchBeforeSubmit(paymentDetails: PaymentDetails, listener: OnBeforeSubmitCallback.Listener) {
        val completed = AtomicBoolean(false)
        fun complete(checkoutId: String?, abort: Boolean) {
            if (!completed.compareAndSet(false, true)) return
            if (abort) {
                paymentDetails.setCanceled(true)
            } else if (!checkoutId.isNullOrEmpty()) {
                paymentDetails.setCheckoutId(checkoutId)
            }
            listener.onComplete(paymentDetails)
        }

        runOnMain {
            val ch = channel
            if (ch == null) {
                Log.w(TAG, "onBeforeSubmit: plugin is not attached to an engine, aborting payment")
                complete(null, true)
                return@runOnMain
            }
            val args = hashMapOf<String, Any?>(
                "checkoutId" to paymentDetails.checkoutId,
                "paymentBrand" to paymentDetails.paymentBrand,
            )
            paymentDetails.selectedVisaInstallmentPlan?.let { args["selectedInstallmentPlan"] = it }
            try {
                ch.invokeMethod("onBeforeSubmit", args, object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        val map = result as? Map<*, *>
                        if (map == null) {
                            Log.w(TAG, "onBeforeSubmit: unexpected reply $result, aborting payment")
                            complete(null, true)
                            return
                        }
                        val abort = map["abort"] as? Boolean ?: true
                        complete(map["checkoutId"] as? String, abort)
                    }

                    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                        Log.w(TAG, "onBeforeSubmit failed ($errorCode: $errorMessage), aborting payment")
                        complete(null, true)
                    }

                    override fun notImplemented() {
                        Log.w(TAG, "onBeforeSubmit has no Dart handler, aborting payment")
                        complete(null, true)
                    }
                })
            } catch (e: Exception) {
                Log.w(TAG, "onBeforeSubmit could not be dispatched, aborting payment", e)
                complete(null, true)
            }
        }
    }
}

/** Field-less Parcelable before-submit callback; forwards to [HyperpayCallbackBridge]. */
internal class HyperpayBeforeSubmitCallback : OnBeforeSubmitCallback {
    override fun onBeforeSubmit(paymentDetails: PaymentDetails, listener: OnBeforeSubmitCallback.Listener) {
        HyperpayCallbackBridge.dispatchBeforeSubmit(paymentDetails, listener)
    }

    override fun describeContents(): Int = 0

    override fun writeToParcel(dest: Parcel, flags: Int) {}

    companion object {
        @JvmField
        val CREATOR: Parcelable.Creator<HyperpayBeforeSubmitCallback> =
            object : Parcelable.Creator<HyperpayBeforeSubmitCallback> {
                override fun createFromParcel(source: Parcel): HyperpayBeforeSubmitCallback =
                    HyperpayBeforeSubmitCallback()

                override fun newArray(size: Int): Array<HyperpayBeforeSubmitCallback?> = arrayOfNulls(size)
            }
    }
}

/** Parcelable payment form listener validating the card holder against a full-match regex. */
internal class HyperpayCardHolderFormListener(private val pattern: String) : IPaymentFormListener {
    private var compiled: Pattern? = null

    override fun onCardHolderValidate(holder: String?): CheckoutValidationResult {
        val regex = compiled ?: try {
            Pattern.compile(pattern).also { compiled = it }
        } catch (e: PatternSyntaxException) {
            Log.w("HyperpaySdk", "Invalid cardHolderPattern, using SDK validation", e)
            return CheckoutValidationResult.DEFAULT
        }
        return if (regex.matcher(holder ?: "").matches()) {
            CheckoutValidationResult.VALID
        } else {
            CheckoutValidationResult.NOT_VALID
        }
    }

    override fun describeContents(): Int = 0

    override fun writeToParcel(dest: Parcel, flags: Int) {
        dest.writeString(pattern)
    }

    companion object {
        @JvmField
        val CREATOR: Parcelable.Creator<HyperpayCardHolderFormListener> =
            object : Parcelable.Creator<HyperpayCardHolderFormListener> {
                override fun createFromParcel(source: Parcel): HyperpayCardHolderFormListener =
                    HyperpayCardHolderFormListener(source.readString() ?: "")

                override fun newArray(size: Int): Array<HyperpayCardHolderFormListener?> = arrayOfNulls(size)
            }
    }
}
