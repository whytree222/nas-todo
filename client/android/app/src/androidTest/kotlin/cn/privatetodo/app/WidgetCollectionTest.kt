package cn.privatetodo.app

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Paint
import android.graphics.Rect
import android.os.SystemClock
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.widget.BaseAdapter
import android.widget.FrameLayout
import android.widget.ListView
import android.widget.RemoteViews
import android.widget.StackView
import android.widget.TextView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class WidgetCollectionTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private var original: String? = null
    private var host: WidgetTestActivity? = null

    @Before fun saveOriginal() {
        original = context.getSharedPreferences(TodoWidgetProvider.PREFS, Context.MODE_PRIVATE).getString("snapshot", null)
    }
    @After fun restoreOriginal() {
        host?.let { instrumentation.runOnMainSync { it.finish() } }
        val edit = context.getSharedPreferences(TodoWidgetProvider.PREFS, Context.MODE_PRIVATE).edit()
        if (original == null) edit.remove("snapshot") else edit.putString("snapshot", original)
        assertTrue(edit.commit())
    }

    private fun task(index: Int, due: String?, done: Boolean = false): JSONObject = JSONObject()
        .put("id", UUID.nameUUIDFromBytes("widget-test-$index".toByteArray()).toString())
        .put("title", "Task ${index.toString().padStart(2, '0')}")
        .put("due_date", due ?: JSONObject.NULL).put("completed", done).put("priority", 0).put("conflict", false)

    private fun dateOffset(offset: Int): String = SimpleDateFormat("yyyy-MM-dd", Locale.ROOT).format(
        Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, offset) }.time)

    private fun save(theme: String = "green"): JSONObject {
        val tasks = JSONArray()
        for (index in 0 until 30) tasks.put(task(index, WidgetData.today(), index == 29))
        tasks.put(task(30, dateOffset(1))).put(task(31, dateOffset(8)))
            .put(task(32, dateOffset(-1))).put(task(33, null))
        val result = JSONObject().put("theme", theme).put("tasks", tasks)
        assertTrue(context.getSharedPreferences(TodoWidgetProvider.PREFS, Context.MODE_PRIVATE)
            .edit().putString("snapshot", result.toString()).commit())
        return result
    }

    @Test fun listsHaveEveryTaskAndDifferentModesStayIndependent() {
        save()
        val expected = mapOf(WidgetData.TODAY to 30, WidgetData.ALL to 34, WidgetData.WEEK to 31,
            WidgetData.COMPACT to 30, WidgetData.CARDS to 34)
        for ((mode, count) in expected) {
            val first = TodoWidgetFactory(context, mode).also { it.onCreate() }
            assertEquals(count, first.getCount())
            assertNotNull(first.getViewAt(count - 1))
            assertNull(first.getViewAt(count))
            val restarted = TodoWidgetFactory(context, mode).also { it.onCreate() }
            assertEquals(first.getItemId(count - 1), restarted.getItemId(count - 1))
            assertTrue(first.hasStableIds())
            assertEquals(count, (0 until count).map { first.getItemId(it) }.toSet().size)
        }
    }

    @Test fun sevenDaysCrossTheYearAndExcludeUndatedAndDeletedTasks() {
        val entries = JSONArray().put(task(1, "2024-12-29")).put(task(2, "2025-01-04"))
            .put(task(3, "2025-01-05")).put(task(4, null)).put(task(5, "2024-12-30").put("deleted", true))
        val selected = WidgetData.tasks(JSONObject().put("tasks", entries), WidgetData.WEEK, "2024-12-29")
        assertEquals(2, selected.size)
    }

    @Test fun cachedRowsFollowEveryThemeAndKeepCompletedStrikeThrough() {
        val completed = task(29, WidgetData.today(), true)
        instrumentation.runOnMainSync {
            for (theme in listOf("black", "white", "green", "blue")) {
                for (mode in listOf(WidgetData.TODAY, WidgetData.COMPACT, WidgetData.CARDS)) {
                    val root = TodoWidgetProvider.row(context, completed, theme, mode).apply(context, FrameLayout(context))
                    val title = root.findViewById<TextView>(R.id.widget_task_title)
                    assertEquals("Task 29", title.text.toString())
                    assertEquals(WidgetData.palette(theme).completed, title.currentTextColor)
                    assertTrue(title.paintFlags and Paint.STRIKE_THRU_TEXT_FLAG != 0)
                    assertFalse(title.hasOnClickListeners())
                }
            }
        }
    }

    @Test fun factoryReloadsFromDiskAndBrokenSnapshotsDoNotCrash() {
        save()
        val factory = TodoWidgetFactory(context, WidgetData.TODAY).also { it.onCreate() }
        assertEquals(30, factory.getCount())
        context.getSharedPreferences(TodoWidgetProvider.PREFS, Context.MODE_PRIVATE).edit().putString("snapshot", "invalid").commit()
        factory.onDataSetChanged()
        assertEquals(0, factory.getCount())
        save("black")
        factory.onDataSetChanged()
        assertEquals(30, factory.getCount())
    }

    @Test fun allProvidersAndProtectedServiceAreRegisteredAndLayoutsAreNativeCollections() {
        val manager = context.packageManager
        for (provider in listOf(TodoWidgetProvider::class.java, TodoAllWidgetProvider::class.java,
                TodoWeekWidgetProvider::class.java, TodoCompactWidgetProvider::class.java, TodoCardsWidgetProvider::class.java)) {
            assertFalse(manager.getReceiverInfo(ComponentName(context, provider), 0).exported)
        }
        val service = manager.getServiceInfo(ComponentName(context, TodoWidgetService::class.java), 0)
        assertEquals("android.permission.BIND_REMOTEVIEWS", service.permission)
        assertFalse(service.exported)
        instrumentation.runOnMainSync {
            for (layout in listOf(R.layout.todo_widget, R.layout.todo_widget_compact)) {
                val view = RemoteViews(context.packageName, layout).apply(context, FrameLayout(context))
                assertTrue(view.findViewById<View>(R.id.widget_tasks) is ListView)
            }
            val card = RemoteViews(context.packageName, R.layout.todo_widget_cards).apply(context, FrameLayout(context))
            assertTrue(card.findViewById<View>(R.id.widget_tasks) is StackView)
        }
    }

    @Test fun nativeListSwipesToLaterTasksWithoutOpeningTheFlutterActivity() {
        save()
        val activity = instrumentation.startActivitySync(Intent(context, WidgetTestActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as WidgetTestActivity
        host = activity
        val factory = TodoWidgetFactory(context, WidgetData.TODAY).also { it.onCreate() }
        lateinit var list: ListView
        instrumentation.runOnMainSync {
            val view = RemoteViews(context.packageName, R.layout.todo_widget).apply(context, activity.root)
            activity.root.addView(view, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
                (220 * context.resources.displayMetrics.density).toInt()))
            list = view.findViewById(R.id.widget_tasks)
            list.emptyView = view.findViewById(R.id.widget_empty)
            list.adapter = object : BaseAdapter() {
                override fun getCount() = factory.getCount()
                override fun getItem(position: Int): Any = position
                override fun getItemId(position: Int) = factory.getItemId(position)
                override fun hasStableIds() = true
                override fun getView(position: Int, convertView: View?, parent: ViewGroup): View =
                    factory.getViewAt(position)!!.apply(activity, parent)
            }
        }
        instrumentation.waitForIdleSync()
        val rect = Rect()
        instrumentation.runOnMainSync { assertTrue(list.getGlobalVisibleRect(rect)) }
        val started = SystemClock.uptimeMillis()
        fun event(action: Int, y: Float) {
            val touch = MotionEvent.obtain(started, SystemClock.uptimeMillis(), action, rect.centerX().toFloat(), y, 0)
            instrumentation.sendPointerSync(touch)
            touch.recycle()
            SystemClock.sleep(35)
        }
        event(MotionEvent.ACTION_DOWN, rect.bottom - 12f)
        for (step in 1..5) event(MotionEvent.ACTION_MOVE, rect.bottom - 12f - rect.height() * 0.85f * step / 5)
        event(MotionEvent.ACTION_UP, rect.top + 12f)
        instrumentation.waitForIdleSync()
        instrumentation.runOnMainSync { assertTrue("The native list must move beyond its first item", list.firstVisiblePosition > 0) }
        instrumentation.runOnMainSync { list.setSelection(29) }
        instrumentation.waitForIdleSync()
        instrumentation.runOnMainSync {
            assertEquals(29, list.lastVisiblePosition)
            assertFalse(activity.isFinishing)
            assertTrue(activity.hasWindowFocus())
        }
    }
}
