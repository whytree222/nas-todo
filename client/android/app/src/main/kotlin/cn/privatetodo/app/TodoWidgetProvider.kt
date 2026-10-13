package cn.privatetodo.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Paint
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.widget.RemoteViews
import java.util.UUID

open class TodoWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { update(context, manager, it) }
    }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager,
        id: Int, options: Bundle) { update(context, manager, id) }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action in listOf(Intent.ACTION_DATE_CHANGED, Intent.ACTION_TIME_CHANGED,
                Intent.ACTION_TIMEZONE_CHANGED, Intent.ACTION_MY_PACKAGE_REPLACED)) {
            val manager = AppWidgetManager.getInstance(context)
            manager.getAppWidgetIds(ComponentName(context, javaClass)).forEach { update(context, manager, it) }
        }
    }

    companion object {
        const val PREFS = "todo_widget"
        const val COMPLETE = "cn.privatetodo.app.WIDGET_COMPLETE"

        private val providers = listOf(TodoWidgetProvider::class.java, TodoAllWidgetProvider::class.java,
            TodoWeekWidgetProvider::class.java, TodoCompactWidgetProvider::class.java, TodoCardsWidgetProvider::class.java)

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            providers.forEach { provider ->
                manager.getAppWidgetIds(ComponentName(context, provider)).forEach { update(context, manager, it) }
            }
        }

        fun modeFor(provider: String?): Int = when (provider) {
            TodoAllWidgetProvider::class.java.name -> WidgetData.ALL
            TodoWeekWidgetProvider::class.java.name -> WidgetData.WEEK
            TodoCompactWidgetProvider::class.java.name -> WidgetData.COMPACT
            TodoCardsWidgetProvider::class.java.name -> WidgetData.CARDS
            else -> WidgetData.TODAY
        }

        private fun launch(context: Context, id: Int, collection: Boolean): PendingIntent {
            val intent = Intent(context, MainActivity::class.java)
                .setData(Uri.parse("privatetodo://widget/${if (collection) "collection" else "open"}/$id"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            if (collection) {
                val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                val auth = prefs.getString("widget_auth", null) ?: UUID.randomUUID().toString().also {
                    prefs.edit().putString("widget_auth", it).commit()
                }
                intent.setAction(COMPLETE).putExtra("widget_auth", auth)
            }
            val mutable = if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0
            return PendingIntent.getActivity(context, id, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or if (collection) mutable else PendingIntent.FLAG_IMMUTABLE)
        }

        @Suppress("DEPRECATION")
        private fun update(context: Context, manager: AppWidgetManager, id: Int) {
            val mode = modeFor(manager.getAppWidgetInfo(id)?.provider?.className)
            manager.updateAppWidget(id, render(context, id, mode))
            manager.notifyAppWidgetViewDataChanged(id, R.id.widget_tasks)
        }

        @Suppress("DEPRECATION")
        fun render(context: Context, id: Int, mode: Int): RemoteViews {
            val state = WidgetData.read(context)
            val today = WidgetData.today()
            val tasks = WidgetData.tasks(state, mode, today)
            val colors = WidgetData.palette(state.optString("theme", "green"))
            val compact = mode == WidgetData.COMPACT
            val views = RemoteViews(context.packageName, when (mode) {
                WidgetData.COMPACT -> R.layout.todo_widget_compact
                WidgetData.CARDS -> R.layout.todo_widget_cards
                else -> R.layout.todo_widget_list
            })
            views.setInt(R.id.widget_root, "setBackgroundResource", colors.background)
            views.setTextColor(R.id.widget_title, colors.text)
            views.setTextColor(R.id.widget_summary, colors.muted)
            views.setTextColor(R.id.widget_empty, colors.muted)
            views.setTextColor(R.id.widget_open, colors.accent)
            views.setTextViewText(R.id.widget_title, when (mode) {
                WidgetData.ALL -> "全部待办"
                WidgetData.WEEK -> "未来七天"
                WidgetData.CARDS -> "待办卡片"
                else -> "今天 · ${today.substring(5).replace('-', '月')}日"
            })
            val remaining = tasks.count { !it.optBoolean("completed") }
            views.setTextViewText(R.id.widget_summary, "$remaining 项未完成 · ${tasks.size} 项 · 上下滑动")
            views.setOnClickPendingIntent(R.id.widget_open, launch(context, id, false))
            val adapter = Intent(context, TodoWidgetService::class.java)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id).putExtra("widget_mode", mode)
                .setData(Uri.parse("privatetodo://widget/list/$id/$mode"))
            views.setRemoteAdapter(R.id.widget_tasks, adapter)
            views.setPendingIntentTemplate(R.id.widget_tasks, launch(context, id, true))
            views.setEmptyView(R.id.widget_tasks, R.id.widget_empty)
            views.setTextViewText(R.id.widget_empty, if (!state.has("tasks")) "先打开应用同步待办" else when (mode) {
                WidgetData.ALL, WidgetData.CARDS -> "没有待办"
                WidgetData.WEEK -> "未来七天没有安排"
                else -> "今天没有安排"
            })
            return views
        }

        fun row(context: Context, task: org.json.JSONObject, theme: String, mode: Int): RemoteViews {
            val colors = WidgetData.palette(theme)
            val compact = mode == WidgetData.COMPACT
            val row = RemoteViews(context.packageName, when (mode) {
                WidgetData.COMPACT -> R.layout.todo_widget_row_compact
                WidgetData.CARDS -> R.layout.todo_widget_card
                else -> R.layout.todo_widget_row
            })
            val done = task.optBoolean("completed")
            val conflict = task.optBoolean("conflict")
            row.setTextViewText(R.id.widget_check, if (conflict) "!" else if (done) "✓" else "○")
            row.setTextViewText(R.id.widget_task_title, task.optString("title"))
            row.setTextColor(R.id.widget_check, if (conflict) colors.conflict else if (done) colors.completed else colors.accent)
            row.setTextColor(R.id.widget_task_title, if (done) colors.completed else colors.text)
            row.setInt(R.id.widget_task_title, "setPaintFlags", Paint.ANTI_ALIAS_FLAG or
                if (done) Paint.STRIKE_THRU_TEXT_FLAG else 0)
            if (!compact) {
                val due = task.optString("due_date")
                row.setTextViewText(R.id.widget_task_date, if (due.length != 10) "未安排" else due.substring(5).replace('-', '/'))
                row.setTextColor(R.id.widget_task_date, colors.muted)
                row.setViewVisibility(R.id.widget_task_date,
                    if (mode == WidgetData.TODAY) android.view.View.GONE else android.view.View.VISIBLE)
            }
            // Only the explicit completion control launches the editor. Browsing
            // and swiping titles does not have an activity PendingIntent.
            row.setOnClickFillInIntent(R.id.widget_check, Intent()
                .putExtra("task_id", task.optString("id"))
                .putExtra("completed", !done).putExtra("widget_open_only", conflict))
            return row
        }
    }
}

class TodoAllWidgetProvider : TodoWidgetProvider()
class TodoWeekWidgetProvider : TodoWidgetProvider()
class TodoCompactWidgetProvider : TodoWidgetProvider()
class TodoCardsWidgetProvider : TodoWidgetProvider()
