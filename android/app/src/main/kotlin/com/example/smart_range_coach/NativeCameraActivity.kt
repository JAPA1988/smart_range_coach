package com.example.smart_range_coach

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.widget.Button
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.camera.camera2.interop.Camera2CameraControl
import androidx.camera.camera2.interop.Camera2CameraInfo
import androidx.camera.camera2.interop.CaptureRequestOptions
import androidx.camera.core.CameraSelector
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.video.FileOutputOptions
import androidx.camera.video.Quality
import androidx.camera.video.QualitySelector
import androidx.camera.video.Recorder
import androidx.camera.video.VideoCapture
import androidx.camera.video.VideoRecordEvent
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import java.io.File

class NativeCameraActivity : AppCompatActivity() {

    private lateinit var previewView: PreviewView
    private lateinit var recordButton: Button

    private var videoCapture: VideoCapture<Recorder>? = null
    private var isRecording = false
    private var activeRecording: androidx.camera.video.Recording? = null

    private val permissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            if (granted) {
                startCamera()
            } else {
                setResult(Activity.RESULT_CANCELED)
                finish()
            }
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_native_camera)

        previewView = findViewById(R.id.previewView)
        recordButton = findViewById(R.id.recordButton)
        applyBottomInsetsToRecordButton()

        recordButton.setOnClickListener {
            if (!isRecording) {
                startRecording()
            } else {
                stopRecording()
            }
        }

        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA)
            == PackageManager.PERMISSION_GRANTED
        ) {
            startCamera()
        } else {
            permissionLauncher.launch(Manifest.permission.CAMERA)
        }
    }

    private fun applyBottomInsetsToRecordButton() {
        val baseMarginDp = 24
        ViewCompat.setOnApplyWindowInsetsListener(recordButton) { view, insets ->
            val systemBars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            val params = view.layoutParams as androidx.constraintlayout.widget.ConstraintLayout.LayoutParams
            params.bottomMargin = systemBars.bottom + dpToPx(baseMarginDp)
            view.layoutParams = params
            insets
        }
        ViewCompat.requestApplyInsets(recordButton)
    }

    private fun dpToPx(dp: Int): Int {
        return (dp * resources.displayMetrics.density).toInt()
    }

    private fun startCamera() {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(this)
        cameraProviderFuture.addListener({
            val cameraProvider = cameraProviderFuture.get()

            val preview = Preview.Builder().build().also {
                it.setSurfaceProvider(previewView.surfaceProvider)
            }

            val recorder = Recorder.Builder()
                .setQualitySelector(QualitySelector.from(Quality.HD))
                .build()

            val videoCapture = VideoCapture.withOutput(recorder)
            this.videoCapture = videoCapture

            val cameraSelector = CameraSelector.DEFAULT_BACK_CAMERA

            cameraProvider.unbindAll()
            val camera = cameraProvider.bindToLifecycle(
                this,
                cameraSelector,
                preview,
                videoCapture
            )

            val camera2Info = Camera2CameraInfo.from(camera.cameraInfo)
            val ranges = camera2Info.getCameraCharacteristic(
                android.hardware.camera2.CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES
            ) ?: emptyArray()

            val desired = ranges.firstOrNull { it.lower == 60 && it.upper == 60 }
            val fallback = ranges.firstOrNull { it.lower <= 30 && it.upper >= 30 }

            val targetRange = desired ?: fallback

            if (targetRange != null) {
                val options = CaptureRequestOptions.Builder()
                    .setCaptureRequestOption(
                        android.hardware.camera2.CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE,
                        targetRange
                    )
                    .build()
                Camera2CameraControl.from(camera.cameraControl).setCaptureRequestOptions(options)
            }
        }, ContextCompat.getMainExecutor(this))
    }

    private fun startRecording() {
        val capture = videoCapture ?: return

        val outputDir = externalMediaDirs.firstOrNull() ?: filesDir
        val outFile = File(outputDir, "swing_${System.currentTimeMillis()}.mp4")
        val outputOptions = FileOutputOptions.Builder(outFile).build()

        isRecording = true
        recordButton.text = "STOP"

        activeRecording = capture.output
            .prepareRecording(this, outputOptions)
            .start(ContextCompat.getMainExecutor(this)) { event ->
                if (event is VideoRecordEvent.Finalize) {
                    if (event.hasError()) {
                        setResult(Activity.RESULT_CANCELED)
                    } else {
                        val data = Intent().putExtra("video_path", outFile.absolutePath)
                        setResult(Activity.RESULT_OK, data)
                    }
                    finish()
                }
            }
    }

    private fun stopRecording() {
        isRecording = false
        recordButton.text = "REC"
        activeRecording?.stop()
        activeRecording = null
    }
}
