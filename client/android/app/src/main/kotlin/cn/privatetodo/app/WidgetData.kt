package cn.privatetodo.app

import android.content.Context
import android.graphics.Color
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.UUID

object WidgetData {
    const val TODAY = 0
    const val ALL = 1
    const val WEEK = 2
    const val COMPACT = 3
    const val CARDS = 4
    data class Palette(val background: Int, val text: Int, val muted: Int,
        val accent: Int, val completed: Int, val conflict: Int)

    fun today(): String = SimpleDateFormat("yyyy-MM-dd", Locale.ROOT).format(Date())

    fun read(context: Context): JSONObject = try {
        JSONObject(context.getSharedPreferences(TodoWidgetProvider.PREFS, Context.MODE_PRIVATE)
            .getString("snapshot", "{}") ?: "{}")
    } catch (_: Exception) { JSONObject() }

    fun tasks(state: JSONObject, mode: Int, today: String): List<JSONObject> {
        val format = SimpleDateFormat("yyyy-MM-dd", Locale.ROOT)
        val end = Calendar.getInstance().apply {
            time = format.parse(today) ?: Date()
            add(Calendar.DAY_OF_YEAR, 6)
        }
        val last = format.format(end.time)
        val array = state.optJSONArray("tasks")
        return (0 until (array?.length() ?: 0)).mapNotNull { array?.optJSONObject(it) }
            .filter { !it.optBoolean("deleted") && it.optString("id").isNotEmpty() }
            .distinctBy { it.optString("id") }
            .filter {
                val due = it.optString("due_date")
                when (mode) {
                    ALL, CARDS -> true
                    WEEK -> due >= today && due <= last
                    else -> due == today
                }
            }
            .sortedWith(compareBy<JSONObject> { it.optBoolean("completed") }
                .thenBy { if (mode == ALL || mode == WEEK || mode == CARDS) it.optString("due_date").takeIf { d -> d.length == 10 } ?: "9999-12-31" else "" }
                .thenByDescending { it.optInt("priority") }.thenBy { it.optString("title") }
                .thenBy { it.optString("id") })
    }

    fun itemId(id: String): Long = try {
        val uuid = UUID.fromString(id)
        (uuid.mostSignificantBits xor uuid.leastSignificantBits).let { if (it == -1L) 0L else it }
    } catch (_: IllegalArgumentException) {
        id.fold(1125899906842597L) { hash, char -> 31 * hash + char.code }
    }

    fun palette(theme: String): Palette = when (theme) {
        "black" -> Palette(R.drawable.widget_background_black, Color.parseColor("#F2F4F6"),
            Color.parseColor("#B1BCC7"), Color.parseColor("#DDE5ED"), Color.parseColor("#89949F"), Color.parseColor("#FFBE86"))
        "white" -> Palette(R.drawable.widget_background_white, Color.parseColor("#26303B"),
            Color.parseColor("#626F7D"), Color.parseColor("#495B6C"), Color.parseColor("#798490"), Color.parseColor("#A3471B"))
        "blue" -> Palette(R.drawable.widget_background_blue, Color.parseColor("#203E60"),
            Color.parseColor("#52718E"), Color.parseColor("#2568A6"), Color.parseColor("#6A8198"), Color.parseColor("#A3471B"))
        else -> Palette(R.drawable.widget_background, Color.parseColor("#244C3E"),
            Color.parseColor("#547565"), Color.parseColor("#326B58"), Color.parseColor("#71857A"), Color.parseColor("#A3471B"))
    }
}
