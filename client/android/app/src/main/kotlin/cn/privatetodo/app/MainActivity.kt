package cn.privatetodo.app

import io.flutter.embedding.android.FlutterActivity
import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

class MainActivity : FlutterActivity() {
    private var widgetChannel: MethodChannel? = null
    private var appUpdates: AppUpdates? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        appUpdates = AppUpdates(this, flutterEngine.dartExecutor.binaryMessenger)
        widgetChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cn.privatetodo/widgets")
        widgetChannel!!.setMethodCallHandler { call, result ->
            val prefs = getSharedPreferences(TodoWidgetProvider.PREFS, MODE_PRIVATE)
            when (call.method) {
                "updateWidget" -> {
                    val snapshot = call.arguments as? String
                    if (snapshot == null) {
                        result.error("invalid_snapshot", "Snapshot missing", null)
                    } else if (!prefs.edit().putString("snapshot", snapshot).commit()) {
                        result.error("storage", "Widget snapshot could not be saved", null)
                    } else {
                        TodoWidgetProvider.updateAll(this)
                        result.success(null)
                    }
                }
                "getWidgetActions" -> {
                    val actions = JSONArray(prefs.getString("actions", "[]"))
                    result.success((0 until actions.length()).map { index ->
                        val action = actions.getJSONObject(index)
                        mapOf("action_id" to action.getString("action_id"),
                            "task_id" to action.getString("task_id"),
                            "completed" to action.getBoolean("completed"))
                    })
                }
                "ackWidgetActions" -> {
                    val ids = (call.arguments as? List<*>)?.filterIsInstance<String>()?.toSet() ?: emptySet()
                    val actions = JSONArray(prefs.getString("actions", "[]"))
                    val remaining = JSONArray()
                    for (i in 0 until actions.length()) {
                        val action = actions.getJSONObject(i)
                        if (!ids.contains(action.getString("action_id"))) remaining.put(action)
                    }
                    if (prefs.edit().putString("actions", remaining.toString()).commit()) result.success(null)
                    else result.error("storage", "Widget action acknowledgement failed", null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        acceptWidgetAction(intent)
    }

    override fun onDestroy() {
        appUpdates?.close()
        appUpdates = null
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        acceptWidgetAction(intent)
    }

    private fun acceptWidgetAction(intent: Intent) {
        if (intent.action != TodoWidgetProvider.COMPLETE) return
        if (intent.getBooleanExtra("widget_open_only", false)) return
        val taskId = intent.getStringExtra("task_id") ?: return
        val prefs = getSharedPreferences(TodoWidgetProvider.PREFS, MODE_PRIVATE)
        val auth = prefs.getString("widget_auth", null) ?: return
        if (intent.getStringExtra("widget_auth") != auth) return
        val actions = JSONArray(prefs.getString("actions", "[]"))
        actions.put(JSONObject().put("action_id", UUID.randomUUID().toString())
            .put("task_id", taskId).put("completed", intent.getBooleanExtra("completed", true)))
        if (prefs.edit().putString("actions", actions.toString()).commit()) {
            // Avoid repeating the same launch action on activity recreation.
            intent.action = Intent.ACTION_MAIN
            intent.removeExtra("task_id")
            intent.data = null
            widgetChannel?.invokeMethod("widgetActionsChanged", null)
        }
    }
}
