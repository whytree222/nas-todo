package cn.privatetodo.app

import android.app.Activity
import android.os.Bundle
import android.widget.FrameLayout

// Internal test fixture: no launcher entry and never opens the Flutter editor.
class WidgetTestActivity : Activity() {
    lateinit var root: FrameLayout
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        root = FrameLayout(this)
        setContentView(root)
    }
}
