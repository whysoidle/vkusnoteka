package ru.recipevault.recipe_vault

import io.flutter.embedding.android.FlutterActivity
import android.content.Intent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var shareChannel: MethodChannel? = null
    private var pendingText: String? = null
    private var localAi: LocalRecipeAi? = null
    private var documents: DocumentTools? = null
    private var timerAlarm: TimerAlarm? = null
    private fun sharedText(intent: Intent?): String? =
        if (intent?.action == Intent.ACTION_SEND && intent.type == "text/plain")
            intent.getStringExtra(Intent.EXTRA_TEXT) else null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        timerAlarm = TimerAlarm(applicationContext, MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "recipe_vault/timer_alarm"))
        documents = DocumentTools(applicationContext, MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "recipe_vault/documents"))
        localAi = LocalRecipeAi(applicationContext,
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "recipe_vault/local_ai"))
        pendingText = sharedText(intent)
        shareChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "recipe_vault/share")
        shareChannel?.setMethodCallHandler { call, result ->
            if (call.method == "initialText") {
                result.success(pendingText)
                pendingText = null
            } else result.notImplemented()
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val text = sharedText(intent) ?: return
        shareChannel?.invokeMethod("sharedText", text)
    }

    override fun onDestroy() {
        localAi?.close()
        documents?.close()
        timerAlarm?.close()
        timerAlarm = null
        localAi = null
        documents = null
        shareChannel?.setMethodCallHandler(null)
        shareChannel = null
        pendingText = null
        super.onDestroy()
    }
}
