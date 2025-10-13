package com.example.stickapp

import android.telephony.SmsManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.stickapp/sms"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "sendSMS") {
                val phoneNumbers = call.argument<List<String>>("phoneNumbers")
                val message = call.argument<String>("message")
                
                if (phoneNumbers != null && message != null) {
                    try {
                        val smsManager = SmsManager.getDefault()
                        var successCount = 0
                        
                        for (phoneNumber in phoneNumbers) {
                            try {
                                val parts = smsManager.divideMessage(message)
                                smsManager.sendMultipartTextMessage(phoneNumber, null, parts, null, null)
                                successCount++
                            } catch (e: Exception) {
                                // Continue with other numbers even if one fails
                            }
                        }
                        
                        result.success(successCount)
                    } catch (e: Exception) {
                        result.error("SMS_ERROR", e.message, null)
                    }
                } else {
                    result.error("INVALID_ARGS", "Phone numbers or message is null", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
