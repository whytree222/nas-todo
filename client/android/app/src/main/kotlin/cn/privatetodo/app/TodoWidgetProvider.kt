package cn.privatetodo.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Paint
import android.net.Uri
import android.os.Bundle
import android.widget.RemoteViews
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID

class TodoWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { update(context, manager, it) }
    }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager,
        id: Int, options: Bundle) { update(context, manager, id) }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action in listOf(Intent.ACTION_DATE_CHANGED, Intent.ACTION_TIME_CHANGED,
                Intent.ACTION_TIMEZONE_CHANGED, Intent.ACTION_MY_PACKAGE_REPLACED)) updateAll(context)
    }

    companion object {
        const val PREFS = "todo_widget"
        const val COMPLETE = "cn.privatetodo.app.WIDGET_COMPLETE"

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            manager.getAppWidgetIds(ComponentName(context, TodoWidgetProvider::class.java))
                .forEach { update(context, manager, it) }
        }

        private fun launch(context: Context, uri: String, id: String? = null,
            completed: Boolean = false): PendingIntent {
            val intent = Intent(context, MainActivity::class.java)
                .setData(Uri.parse(uri))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            if (id != null) {
                val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                val auth = prefs.getString("widget_auth", null) ?: UUID.randomUUID().toString().also {
                    prefs.edit().putString("widget_auth", it).commit()
                }
                intent.setAction(COMPLETE).putExtra("task_id", id).putExtra("completed", completed)
                    .putExtra("widget_auth", auth)
            }
            return PendingIntent.getActivity(context, 0, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }

        private fun update(context: Context, manager: AppWidgetManager, id: Int) {
            val today = SimpleDateFormat("yyyy-MM-dd", Locale.ROOT).format(Date())
            val snapshot = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("snapshot", null)
            val array = try { JSONObject(snapshot ?: "{\"tasks\":[]}").optJSONArray("tasks") }
                catch (_: Exception) { null }
            val tasks = (0 until (array?.length() ?: 0)).mapNotNull { array?.optJSONObject(it) }
                .filter { it.optString("due_date") == today }
                .sortedWith(compareBy<JSONObject> { it.optBoolean("completed") }
                    .thenByDescending { it.optInt("priority") }.thenBy { it.optString("title") })
            val views = RemoteViews(context.packageName, R.layout.todo_widget)
            views.setTextViewText(R.id.widget_title, "今天 · ${today.substring(5).replace('-', '月')}日")
            val remaining = tasks.count { !it.optBoolean("completed") }
            views.setTextViewText(R.id.widget_summary, "$remaining 项未完成 / ${tasks.size} 项 · 点勾选打开应用保存")
            views.setOnClickPendingIntent(R.id.widget_title, launch(context, "privatetodo://widget/open"))
            views.setOnClickPendingIntent(R.id.widget_open, launch(context, "privatetodo://widget/open"))
            views.removeAllViews(R.id.widget_tasks)
            val height = manager.getAppWidgetOptions(id).getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 250)
            val visibleCount = ((height - 140) / 44).coerceIn(1, 8)
            for (task in tasks.take(visibleCount)) {
                val row = RemoteViews(context.packageName, R.layout.todo_widget_row)
                val done = task.optBoolean("completed")
                val conflict = task.optBoolean("conflict")
                val taskId = task.getString("id")
                row.setTextViewText(R.id.widget_check, if (conflict) "!" else if (done) "☑" else "☐")
                row.setTextViewText(R.id.widget_task_title, task.getString("title"))
                row.setInt(R.id.widget_task_title, "setPaintFlags", Paint.ANTI_ALIAS_FLAG or
                    if (done) Paint.STRIKE_THRU_TEXT_FLAG else 0)
                row.setOnClickPendingIntent(R.id.widget_task_title, launch(context, "privatetodo://widget/open/$taskId"))
                row.setOnClickPendingIntent(R.id.widget_check, if (conflict)
                    launch(context, "privatetodo://widget/conflict/$taskId") else
                    launch(context, "privatetodo://widget/complete/$taskId/${!done}", taskId, !done))
                views.addView(R.id.widget_tasks, row)
            }
            views.setTextViewText(R.id.widget_empty, when {
                snapshot == null -> "先打开应用，设置待办日期后会显示在这里"
                tasks.isEmpty() -> "今天没有安排待办"
                tasks.size > visibleCount -> "还有 ${tasks.size - visibleCount} 项，打开应用查看"
                else -> ""
            })
            manager.updateAppWidget(id, views)
        }
    }
}
