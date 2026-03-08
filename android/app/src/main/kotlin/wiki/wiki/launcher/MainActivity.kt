package wiki.wiki.launcher

import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "wiki.wiki.launcher/apps"
    private var appUpdateReceiver: android.content.BroadcastReceiver? = null

    override fun onDestroy() {
        super.onDestroy()
        appUpdateReceiver?.let {
            unregisterReceiver(it)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        
        // Listen for app install/uninstall/update events
        if (appUpdateReceiver == null) {
            appUpdateReceiver = object : android.content.BroadcastReceiver() {
                override fun onReceive(context: android.content.Context?, intent: android.content.Intent?) {
                    channel.invokeMethod("onAppListChanged", null)
                }
            }
            val intentFilter = android.content.IntentFilter().apply {
                addAction(android.content.Intent.ACTION_PACKAGE_ADDED)
                addAction(android.content.Intent.ACTION_PACKAGE_REMOVED)
                addAction(android.content.Intent.ACTION_PACKAGE_REPLACED)
                addDataScheme("package")
            }
            registerReceiver(appUpdateReceiver, intentFilter)
        }

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInstalledApps" -> {
                    val apps = getInstalledApps()
                    result.success(apps)
                }
                "getAppIcon" -> {
                    val packageName = call.argument<String>("packageName")
                    if (packageName != null) {
                        val icon = getAppIconBytes(packageName)
                        result.success(icon)
                    } else {
                        result.error("INVALID_ARGUMENT", "Package name is required", null)
                    }
                }
                "openApp" -> {
                    val packageName = call.argument<String>("packageName")
                    if (packageName != null) {
                        val success = openApp(packageName)
                        result.success(success)
                    } else {
                        result.error("INVALID_ARGUMENT", "Package name is required", null)
                    }
                }
                "openAppInfo" -> {
                    val packageName = call.argument<String>("packageName")
                    if (packageName != null) {
                        openAppSettings(packageName)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGUMENT", "Package name is required", null)
                    }
                }
                "uninstallApp" -> {
                    val packageName = call.argument<String>("packageName")
                    if (packageName != null) {
                        uninstallApp(packageName)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGUMENT", "Package name is required", null)
                    }
                }
                "expandStatusBar" -> {
                    expandStatusBar()
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (Intent.ACTION_MAIN == intent.action && intent.hasCategory(Intent.CATEGORY_HOME)) {
            val flutterEngine = flutterEngine ?: return
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
                .invokeMethod("onHomePressed", null)
        }
    }

    private fun getInstalledApps(): List<Map<String, Any?>> {
        val pm = packageManager
        val mainIntent = Intent(Intent.ACTION_MAIN, null).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
        }
        
        val apps = pm.queryIntentActivities(mainIntent, 0)
        
        return apps.map { resolveInfo ->
            mutableMapOf<String, Any?>(
                "name" to (resolveInfo.loadLabel(pm)?.toString() ?: "Unknown"),
                "packageName" to resolveInfo.activityInfo.packageName,
            )
        }.sortedBy { (it["name"] as String).lowercase() }
    }

    private fun getAppIconBytes(packageName: String): ByteArray? {
        return try {
            val drawable = packageManager.getApplicationIcon(packageName)
            val bitmap = drawableToBitmap(drawable)
            val stream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
            stream.toByteArray()
        } catch (e: Exception) {
            null
        }
    }

    private fun drawableToBitmap(drawable: Drawable): Bitmap {
        if (drawable is BitmapDrawable) {
            return drawable.bitmap
        }
        
        val width = if (drawable.intrinsicWidth > 0) drawable.intrinsicWidth else 48
        val height = if (drawable.intrinsicHeight > 0) drawable.intrinsicHeight else 48
        
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, canvas.width, canvas.height)
        drawable.draw(canvas)
        
        return bitmap
    }

    private fun openApp(packageName: String): Boolean {
        return try {
            val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            if (launchIntent != null) {
                launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                launchIntent.addFlags(Intent.FLAG_ACTIVITY_NO_ANIMATION)
                startActivity(launchIntent)
                overridePendingTransition(0, 0)
                true
            } else {
                false
            }
        } catch (e: Exception) {
            false
        }
    }

    private fun openAppSettings(packageName: String) {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:$packageName")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    private fun uninstallApp(packageName: String) {
        try {
            val intent = Intent(Intent.ACTION_DELETE).apply {
                data = Uri.parse("package:$packageName")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            startActivity(intent)
        } catch (e: Exception) {
            try {
                val intent = Intent(Intent.ACTION_UNINSTALL_PACKAGE).apply {
                    data = Uri.parse("package:$packageName")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    putExtra(Intent.EXTRA_RETURN_RESULT, true)
                }
                startActivity(intent)
            } catch (e2: Exception) {
                e2.printStackTrace()
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun expandStatusBar() {
        try {
            val statusBarService = getSystemService("statusbar")
            val statusBarManager = Class.forName("android.app.StatusBarManager")
            val expand = statusBarManager.getMethod("expandNotificationsPanel")
            expand.invoke(statusBarService)
        } catch (e: Exception) {
            try {
                val statusBarService = getSystemService("statusbar")
                val statusBarManager = Class.forName("android.app.StatusBarManager")
                val expand = statusBarManager.getMethod("expand")
                expand.invoke(statusBarService)
            } catch (e2: Exception) {
                e2.printStackTrace()
            }
        }
    }
}
