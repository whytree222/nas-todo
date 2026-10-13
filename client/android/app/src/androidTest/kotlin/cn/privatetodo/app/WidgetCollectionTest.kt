package cn.privatetodo.app

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
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
import kotlin.math.pow

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
                for (mode in listOf(WidgetData.TODAY, WidgetData.ALL, WidgetData.WEEK, WidgetData.COMPACT, WidgetData.CARDS)) {
                    val views = TodoWidgetProvider.row(context, completed, theme, mode)
                    assertEquals(when (mode) {
                        WidgetData.COMPACT -> R.layout.todo_widget_priority_row_compact
                        WidgetData.CARDS -> R.layout.todo_widget_priority_card
                        else -> R.layout.todo_widget_priority_row
                    }, views.layoutId)
                    val root = views.apply(context, FrameLayout(context))
                    val title = root.findViewById<TextView>(R.id.widget_task_title)
                    assertEquals("Task 29", title.text.toString())
                    assertEquals(WidgetData.palette(theme).completed, title.currentTextColor)
                    assertTrue(title.paintFlags and Paint.STRIKE_THRU_TEXT_FLAG != 0)
                    assertFalse(title.hasOnClickListeners())
                }
            }
        }
    }

    @Test fun urgencyBadgesRemainDistinctAndReadableInEveryModeThemeAndCompletionState() {
        val labels = listOf("普通", "较高", "紧急")
        val lightText = listOf("#1E5EA8", "#855300", "#B32634")
        val lightBackground = listOf("#E8F1FF", "#FFF2CC", "#FFE8EC")
        val darkText = listOf("#ABD0FF", "#FFD889", "#FFB5BB")
        val darkBackground = listOf("#1C385B", "#58461F", "#57252D")
        fun luminance(color: Int): Double {
            fun channel(value: Int): Double = (value / 255.0).let {
                if (it <= 0.04045) it / 12.92 else ((it + 0.055) / 1.055).pow(2.4)
            }
            return 0.2126 * channel(Color.red(color)) + 0.7152 * channel(Color.green(color)) + 0.0722 * channel(Color.blue(color))
        }
        instrumentation.runOnMainSync {
            for (theme in listOf("black", "white", "green", "blue")) {
                val backgrounds = mutableSetOf<Int>()
                for (priority in 0..2) {
                    val foreground = Color.parseColor((if (theme == "black") darkText else lightText)[priority])
                    val background = Color.parseColor((if (theme == "black") darkBackground else lightBackground)[priority])
                    backgrounds.add(background)
                    val contrast = (maxOf(luminance(foreground), luminance(background)) + 0.05) /
                        (minOf(luminance(foreground), luminance(background)) + 0.05)
                    assertTrue("Small badge text needs readable contrast in $theme", contrast >= 4.5)
                    for (mode in listOf(WidgetData.TODAY, WidgetData.ALL, WidgetData.WEEK, WidgetData.COMPACT, WidgetData.CARDS)) {
                        for (done in listOf(false, true)) {
                            val entry = task(priority, WidgetData.today(), done).put("priority", priority).put("conflict", priority == 2)
                            val root = TodoWidgetProvider.row(context, entry, theme, mode).apply(context, FrameLayout(context))
                            val badge = root.findViewById<TextView>(R.id.widget_task_priority)
                            assertEquals("● ${labels[priority]}", badge.text.toString())
                            assertEquals("紧急程度：${labels[priority]}", badge.contentDescription.toString())
                            assertEquals(foreground, badge.currentTextColor)
                            val bitmap = Bitmap.createBitmap(80, 40, Bitmap.Config.ARGB_8888)
                            badge.background.setBounds(0, 0, bitmap.width, bitmap.height)
                            badge.background.draw(Canvas(bitmap))
                            assertEquals(background, bitmap.getPixel(40, 20))
                            bitmap.recycle()
                            assertFalse(badge.hasOnClickListeners())
                            val title = root.findViewById<TextView>(R.id.widget_task_title)
                            assertFalse(title.hasOnClickListeners())
                            assertEquals(done, title.paintFlags and Paint.STRIKE_THRU_TEXT_FLAG != 0)
                            val check = root.findViewById<TextView>(R.id.widget_check)
                            assertEquals(if (priority == 2) "!" else if (done) "✓" else "○", check.text.toString())
                            assertEquals(if (priority == 2) "待办存在冲突，打开应用处理" else if (done) "取消完成，打开应用保存"
                                else "标记完成，打开应用保存", check.contentDescription.toString())
                        }
                    }
                }
                assertEquals(3, backgrounds.size)
                for (invalid in listOf(-1, 3, 99)) assertEquals("普通", WidgetData.priority(invalid, theme).label)
            }
        }
    }

    @Test fun urgencyBadgeStaysVisibleBesideLongTitlesInNarrowWidgets() {
        val density = context.resources.displayMetrics.density
        instrumentation.runOnMainSync {
            for (mode in listOf(WidgetData.TODAY, WidgetData.COMPACT, WidgetData.CARDS)) {
                val entry = task(1, WidgetData.today()).put("priority", 2)
                    .put("title", "这是一个很长很长的待办标题，用于确认缩窄小组件时仍然能够看见紧急程度")
                val root = TodoWidgetProvider.row(context, entry, "black", mode).apply(context, FrameLayout(context)) as ViewGroup
                val width = (160 * density).toInt()
                val height = if (mode == WidgetData.CARDS) View.MeasureSpec.makeMeasureSpec((132 * density).toInt(), View.MeasureSpec.EXACTLY)
                    else View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
                root.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY), height)
                root.layout(0, 0, root.measuredWidth, root.measuredHeight)
                val badge = root.findViewById<TextView>(R.id.widget_task_priority)
                val bounds = Rect(0, 0, badge.width, badge.height)
                root.offsetDescendantRectToMyCoords(badge, bounds)
                assertTrue(badge.width > 0 && badge.height > 0)
                assertEquals(1, badge.lineCount)
                assertTrue("Urgency must stay within the narrow widget", bounds.left >= 0 && bounds.top >= 0 &&
                    bounds.right <= root.width && bounds.bottom <= root.height)
                assertEquals("● 紧急", badge.text.toString())
                assertFalse(root.findViewById<TextView>(R.id.widget_task_title).hasOnClickListeners())
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
            for (layout in listOf(R.layout.todo_widget_list, R.layout.todo_widget_compact)) {
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
            val view = RemoteViews(context.packageName, R.layout.todo_widget_list).apply(context, activity.root)
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
