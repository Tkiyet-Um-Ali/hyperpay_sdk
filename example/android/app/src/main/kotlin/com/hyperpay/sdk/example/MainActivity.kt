package com.hyperpay.sdk.example

import io.flutter.embedding.android.FlutterFragmentActivity

// hyperpay_sdk launches the checkout through the Activity Result API, which
// needs a ComponentActivity: use FlutterFragmentActivity, not FlutterActivity.
class MainActivity : FlutterFragmentActivity()
