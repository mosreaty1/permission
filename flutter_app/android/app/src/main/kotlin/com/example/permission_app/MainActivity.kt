package com.example.permission_app

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {

    private val CHANNEL      = "com.permissionhub/screen_capture"
    private val APP_CHANNEL  = "com.permissionhub/app_visibility"
    private val REQUEST_CODE = 1001

    private var pendingResult: MethodChannel.Result? = null
    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null

    private val launcherAlias get() = ComponentName(this, "com.example.permission_app.LauncherAlias")

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Screen capture channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "captureScreen") {
                    pendingResult = result
                    val mgr = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                    startActivityForResult(mgr.createScreenCaptureIntent(), REQUEST_CODE)
                } else {
                    result.notImplemented()
                }
            }

        // App visibility channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APP_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hideApp" -> {
                        packageManager.setComponentEnabledSetting(
                            launcherAlias,
                            PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                            PackageManager.DONT_KILL_APP
                        )
                        result.success(true)
                    }
                    "showApp" -> {
                        packageManager.setComponentEnabledSetting(
                            launcherAlias,
                            PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                            PackageManager.DONT_KILL_APP
                        )
                        result.success(true)
                    }
                    "isVisible" -> {
                        val state = packageManager.getComponentEnabledSetting(launcherAlias)
                        result.success(state != PackageManager.COMPONENT_ENABLED_STATE_DISABLED)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CODE) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                val mgr = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                mediaProjection = mgr.getMediaProjection(resultCode, data)
                doCapture()
            } else {
                pendingResult?.error("CANCELLED", "User cancelled screen capture", null)
                pendingResult = null
            }
        }
    }

    private fun doCapture() {
        val metrics = resources.displayMetrics
        val width   = metrics.widthPixels
        val height  = metrics.heightPixels
        val density = metrics.densityDpi

        imageReader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)

        virtualDisplay = mediaProjection!!.createVirtualDisplay(
            "PermissionHubCapture", width, height, density,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            imageReader!!.surface, null, null
        )

        // Short delay so the virtual display renders a frame
        Handler(Looper.getMainLooper()).postDelayed({
            val image = imageReader?.acquireLatestImage()
            if (image != null) {
                try {
                    val plane     = image.planes[0]
                    val rowStride = plane.rowStride
                    val pixStride = plane.pixelStride
                    val buffer    = plane.buffer
                    val rowPad    = rowStride - pixStride * width

                    val bmp = Bitmap.createBitmap(
                        width + rowPad / pixStride, height, Bitmap.Config.ARGB_8888
                    )
                    bmp.copyPixelsFromBuffer(buffer)
                    image.close()

                    val cropped = Bitmap.createBitmap(bmp, 0, 0, width, height)
                    val out = ByteArrayOutputStream()
                    cropped.compress(Bitmap.CompressFormat.JPEG, 85, out)
                    val bytes = out.toByteArray()

                    Handler(Looper.getMainLooper()).post {
                        pendingResult?.success(bytes)
                        pendingResult = null
                    }
                } catch (e: Exception) {
                    Handler(Looper.getMainLooper()).post {
                        pendingResult?.error("CAPTURE_FAILED", e.message, null)
                        pendingResult = null
                    }
                }
            } else {
                Handler(Looper.getMainLooper()).post {
                    pendingResult?.error("NO_IMAGE", "Could not capture screen", null)
                    pendingResult = null
                }
            }

            virtualDisplay?.release()
            mediaProjection?.stop()
            imageReader?.close()
        }, 600)
    }
}
