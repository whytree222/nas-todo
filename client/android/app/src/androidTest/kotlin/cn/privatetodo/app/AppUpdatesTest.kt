package cn.privatetodo.app

import android.content.pm.PackageManager
import androidx.core.content.FileProvider
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import io.flutter.plugin.common.BinaryMessenger
import java.io.File
import java.nio.ByteBuffer
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AppUpdatesTest {
    private val messenger = object: BinaryMessenger {
        override fun send(channel: String, message: ByteBuffer?) {}
        override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) {}
        override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) {}
    }
    private fun check(action: (MainActivity, AppUpdates) -> Unit) {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                val updates = AppUpdates(activity, messenger)
                try { action(activity, updates) } finally { updates.close() }
            }
        }
    }
    private fun rejected(reason: String, action: () -> Unit) {
        try { action(); fail("Package must be rejected") }
        catch (error: AppUpdates.UpdateError) { assertEquals(reason, error.reason) }
    }
    @Test fun installedIdentityAndSingleSigningCertificateMatch() = check { activity, updates ->
        @Suppress("DEPRECATION")
        val info = activity.packageManager.getPackageInfo(activity.packageName, PackageManager.GET_SIGNING_CERTIFICATES)
        updates.verifyIdentity(info, info.versionName!!, info.longVersionCode)
        rejected("identity") { updates.verifyIdentity(info, "99.99.99", info.longVersionCode) }
        rejected("identity") { updates.verifyIdentity(info, info.versionName!!, info.longVersionCode + 1) }
    }
    @Test fun differentCertificateCannotMasqueradeAsThisApplication() = check { activity, updates ->
        @Suppress("DEPRECATION")
        val installed = activity.packageManager.getPackageInfo(activity.packageName, PackageManager.GET_SIGNING_CERTIFICATES)
        @Suppress("DEPRECATION")
        val other = activity.packageManager.getPackageInfo("android", PackageManager.GET_SIGNING_CERTIFICATES)
        other.packageName = activity.packageName
        other.versionName = installed.versionName
        other.longVersionCode = installed.longVersionCode
        rejected("signature") { updates.verifyIdentity(other, installed.versionName!!, installed.longVersionCode) }
    }
    @Test fun privateFileScopeSizeHashAndApkFormatAreEnforced() = check { activity, updates ->
        val file = File(activity.filesDir, "updates/nas-todo-0.13.0.apk")
        file.parentFile!!.mkdirs(); file.writeBytes(byteArrayOf(1, 2, 3))
        val args = mutableMapOf<String, Any>("path" to file.path, "versionName" to "0.13.0", "versionCode" to 17, "size" to 3,
            "sha256" to "0".repeat(64))
        rejected("hash") { updates.verify(args) }
        args["sha256"] = "039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81"
        rejected("identity") { updates.verify(args) }
        args["size"] = 4; rejected("identity") { updates.verify(args) }
        args["path"] = File(activity.cacheDir, file.name).path; rejected("identity") { updates.verify(args) }
        file.delete()
    }
    @Test fun fileProviderIsNotExportedAndOnlySharesTheUpdateDirectory() = check { activity, _ ->
        val authority = "${activity.packageName}.updates"
        val provider = activity.packageManager.resolveContentProvider(authority, PackageManager.GET_META_DATA)!!
        assertFalse(provider.exported); assertTrue(provider.grantUriPermissions)
        val file = File(activity.filesDir, "updates/nas-todo-0.13.0.apk")
        assertEquals("content", FileProvider.getUriForFile(activity, authority, file).scheme)
        try { FileProvider.getUriForFile(activity, authority, File(activity.filesDir, "config.json")); fail("Private configuration must never be shared") }
        catch (_: IllegalArgumentException) { /* expected */ }
    }
}
