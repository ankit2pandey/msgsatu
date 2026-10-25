package com.khaledhossameldin.telephony_sms

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.content.pm.PackageManager.PERMISSION_GRANTED
import android.os.Build
import android.telephony.SmsManager
import androidx.core.app.ActivityCompat
import androidx.core.app.ActivityCompat.shouldShowRequestPermissionRationale
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry

/** TelephonySmsPlugin */
class TelephonySmsPlugin: FlutterPlugin, MethodCallHandler, PluginRegistry.RequestPermissionsResultListener, ActivityAware {

  private lateinit var channel : MethodChannel

  private val permissionCode : Int = 39

  private var currentActivity : Activity? = null
  private var context: Context? = null

  private var smsManager : SmsManager? = null

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    context = flutterPluginBinding.applicationContext
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "telephony_sms")
    channel.setMethodCallHandler(this)
    // Background service engines have no Activity, so initialize SmsManager here.
    initSMSManager()
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    if (call.method == "requestPermission") {
      requestPermission(result)
    } else if (call.method == "sendSMS") {
      try {
        val appContext = context
        if (appContext == null || ContextCompat.checkSelfPermission(
            appContext,
            Manifest.permission.SEND_SMS
          ) != PERMISSION_GRANTED
        ) {
          result.error("PERMISSION_DENIED", "SEND_SMS permission is not granted", null)
          return
        }
        val manager = smsManager ?: run {
          initSMSManager()
          smsManager
        }
        if (manager == null) {
          result.error("SMS_MANAGER_UNAVAILABLE", "Android could not initialize SmsManager", null)
          return
        }
        val arguments = call.arguments as? Map<*, *>
          ?: throw IllegalArgumentException("SMS arguments are missing")
        val phone = arguments["phone"] as? String
          ?: throw IllegalArgumentException("Recipient phone number is missing")
        val message = arguments["message"] as? String
          ?: throw IllegalArgumentException("SMS message is missing")
        manager.sendTextMessage(phone, null, message, null, null)
        result.success(null)
      } catch (e: Exception) {
        result.error("SMS_SEND_FAILED", e.message ?: e.javaClass.simpleName, null)
      }
    } else {
      result.notImplemented()
    }
  }

  private fun initSMSManager() {
    smsManager = try {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
        context!!.getSystemService(SmsManager::class.java)
      } else {
        SmsManager.getDefault();
      }
    } catch (_: Exception) {
      SmsManager.getDefault();
    }
  }

  private fun requestPermission(result: Result) {
    when {
        ContextCompat.checkSelfPermission(
          context!!,
          Manifest.permission.SEND_SMS
        ) == PackageManager.PERMISSION_GRANTED -> {
          result.success(true)
        }
        shouldShowRequestPermissionRationale(currentActivity!!, Manifest.permission.SEND_SMS) -> {
          result.error("Permission Denied", "This plugin requires Sending SMS permission in order to work", Exception("This plugin requires Sending SMS permission in order to work"))
        } else -> {
        ActivityCompat.requestPermissions(currentActivity!!, arrayOf(Manifest.permission.SEND_SMS), permissionCode)
      }
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }

  override fun onRequestPermissionsResult(
    requestCode: Int,
    permissions: Array<out String>,
    grantResults: IntArray
  ): Boolean {
    when (requestCode) {
      permissionCode -> {
        if (grantResults.isNotEmpty() && grantResults[0] == PERMISSION_GRANTED) {
          initSMSManager()
        }
        return true
      }
    }
    return false
  }

  override fun onDetachedFromActivity() {
    currentActivity = null
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    currentActivity = binding.activity
    if (ContextCompat.checkSelfPermission(binding.activity, Manifest.permission.SEND_SMS) == PackageManager.PERMISSION_GRANTED) {
      initSMSManager()
    }
    binding.addRequestPermissionsResultListener(this)
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    currentActivity = binding.activity
    if (ContextCompat.checkSelfPermission(binding.activity, Manifest.permission.SEND_SMS) == PackageManager.PERMISSION_GRANTED) {
      initSMSManager()
    }
    binding.addRequestPermissionsResultListener(this)
  }

  override fun onDetachedFromActivityForConfigChanges() {
    currentActivity = null
  }

}
