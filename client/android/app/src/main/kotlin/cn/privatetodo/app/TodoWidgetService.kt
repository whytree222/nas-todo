package cn.privatetodo.app

import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import org.json.JSONObject

class TodoWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        TodoWidgetFactory(applicationContext, intent.getIntExtra("widget_mode", WidgetData.TODAY))
}

class TodoWidgetFactory(private val context: Context, private val mode: Int) : RemoteViewsService.RemoteViewsFactory {
    private var entries: List<JSONObject> = emptyList()
    private var theme = "green"
    override fun onCreate() = onDataSetChanged()
    override fun onDataSetChanged() {
        val state = WidgetData.read(context)
        entries = WidgetData.tasks(state, mode, WidgetData.today())
        theme = state.optString("theme", "green")
    }
    override fun onDestroy() { entries = emptyList() }
    override fun getCount(): Int = entries.size
    override fun getViewAt(position: Int): RemoteViews? = entries.getOrNull(position)?.let {
        TodoWidgetProvider.row(context, it, theme, mode)
    }
    override fun getLoadingView(): RemoteViews? = null
    override fun getViewTypeCount(): Int = 1
    override fun getItemId(position: Int): Long = entries.getOrNull(position)?.let { WidgetData.itemId(it.optString("id")) } ?: -1L
    override fun hasStableIds(): Boolean = true
}
