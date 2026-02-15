package com.example.smart_range_coach

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

	private val channelName = "com.smart_range_coach/native_camera"
	private val nativeCameraRequestCode = 12001
	private var pendingResult: MethodChannel.Result? = null

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
			.setMethodCallHandler { call, result ->
				when (call.method) {
					"startNativeCamera" -> {
						if (pendingResult != null) {
							result.error("BUSY", "Native camera already active", null)
							return@setMethodCallHandler
						}

						pendingResult = result
						startActivityForResult(
							Intent(this, NativeCameraActivity::class.java),
							nativeCameraRequestCode
						)
					}

					else -> result.notImplemented()
				}
			}
	}

	override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
		super.onActivityResult(requestCode, resultCode, data)

		if (requestCode != nativeCameraRequestCode) return

		val callback = pendingResult
		pendingResult = null

		if (callback == null) return

		if (resultCode == Activity.RESULT_OK) {
			callback.success(data?.getStringExtra("video_path"))
		} else {
			callback.success(null)
		}
	}
}
