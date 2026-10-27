package cn.privatetodo.app

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.StatFs
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors

class AppUpdates(private val activity: FlutterActivity, messenger: BinaryMessenger) {
    private val executor = Executors.newSingleThreadExecutor()
    private val channel = MethodChannel(messenger, "cn.privatetodo/updates")
    private val directory get() = File(activity.filesDir, "updates").apply { mkdirs() }
    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "identity" -> {
                        val installed = installed()
                        result.success(mapOf("platform" to "android", "versionName" to installed.versionName,
                            "versionCode" to code(installed), "directory" to directory.path,
                            "enabled" to !BuildConfig.DEBUG && BuildConfig.UPDATES_ENABLED))
                    }
                    "freeSpace" -> result.success(StatFs(directory.path).availableBytes)
                    "verify", "install" -> {
                        val args = call.arguments as? Map<*, *> ?: throw UpdateError("identity")
                        executor.execute {
                            try {
                                val file = verify(args)
                                activity.runOnUiThread {
                                    try {
                                        if (call.method == "verify") result.success(null)
                                        else result.success(install(file, (args["versionCode"] as Number).toLong()))
                                    } catch (e: UpdateError) { result.error(e.reason, "Update rejected", null) }
                                    catch (_: Exception) { result.error("installer", "Installer unavailable", null) }
                                }
                            } catch (e: UpdateError) { activity.runOnUiThread { result.error(e.reason, "Update rejected", null) } }
                            catch (_: Exception) { activity.runOnUiThread { result.error("identity", "Update rejected", null) } }
                        }
                    }
                    "openPage" -> {
                        val url = call.argument<String>("url") ?: throw UpdateError("identity")
                        if (!Regex("https://github\\.com/whytree222/nas-todo/releases/tag/v[0-9]+\\.[0-9]+\\.[0-9]+").matches(url)) throw UpdateError("identity")
                        activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: UpdateError) { result.error(e.reason, "Update rejected", null) }
            catch (_: Exception) { result.error("installer", "Update unavailable", null) }
        }
    }
    fun close() { channel.setMethodCallHandler(null); executor.shutdown() }
    private fun flags() = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
    @Suppress("DEPRECATION")
    private fun installed() = activity.packageManager.getPackageInfo(activity.packageName, flags())
    @Suppress("DEPRECATION")
    private fun code(info: PackageInfo): Long = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
    @Suppress("DEPRECATION")
    private fun signer(info: PackageInfo): ByteArray {
        val certs = if (Build.VERSION.SDK_INT >= 28) {
            val signing = info.signingInfo ?: throw UpdateError("signature")
            if (signing.hasMultipleSigners()) throw UpdateError("signature")
            signing.apkContentsSigners
        } else info.signatures
        if (certs == null || certs.size != 1) throw UpdateError("signature")
        return MessageDigest.getInstance("SHA-256").digest(certs[0].toByteArray())
    }
    fun verify(args: Map<*, *>): File {
        val path = args["path"] as? String ?: throw UpdateError("identity")
        val name = args["versionName"] as? String ?: throw UpdateError("identity")
        val version = (args["versionCode"] as? Number)?.toLong() ?: throw UpdateError("identity")
        val size = (args["size"] as? Number)?.toLong() ?: throw UpdateError("identity")
        val hash = args["sha256"] as? String ?: throw UpdateError("hash")
        val file = File(path).canonicalFile
        if (file.parentFile != directory.canonicalFile || file.name != "nas-todo-$name.apk" || !file.isFile || size < 1 || size > 100L * 1024 * 1024 || file.length() != size) throw UpdateError("identity")
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) { val read = input.read(buffer); if (read < 0) break; digest.update(buffer, 0, read) }
        }
        if (digest.digest().joinToString("") { "%02x".format(it) } != hash) throw UpdateError("hash")
        @Suppress("DEPRECATION")
        val archive = activity.packageManager.getPackageArchiveInfo(file.path, flags()) ?: throw UpdateError("identity")
        if (archive.packageName != activity.packageName || archive.versionName != name || code(archive) != version) throw UpdateError("identity")
        if (!MessageDigest.isEqual(signer(archive), signer(installed()))) throw UpdateError("signature")
        return file
    }
    private fun install(file: File, version: Long): String {
        if (BuildConfig.DEBUG || !BuildConfig.UPDATES_ENABLED || version <= code(installed())) throw UpdateError("identity")
        if (Build.VERSION.SDK_INT >= 26 && !activity.packageManager.canRequestPackageInstalls()) {
            activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${activity.packageName}")))
            return "permission"
        }
        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.updates", file)
        try {
            activity.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
        } catch (_: ActivityNotFoundException) { throw UpdateError("installer") }
        return "started"
    }
    class UpdateError(val reason: String): Exception()
}
