package com.hydrabin.connector.ui

import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import com.google.android.gms.tasks.Task
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.mlkit.vision.barcode.Barcode
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.common.InputImage
import com.hydrabin.connector.databinding.ActivityScannerBinding
import java.util.concurrent.Executors

class ScannerActivity : AppCompatActivity() {

    private lateinit var binding: ActivityScannerBinding
    private val cameraExecutor = Executors.newSingleThreadExecutor()
    private var processingBarcode = false

    private val requestPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { isGranted ->
            if (isGranted) {
                startCamera()
            } else {
                Toast.makeText(this, "Camera permission is required to scan", Toast.LENGTH_SHORT).show()
                finish()
            }
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityScannerBinding.inflate(layoutInflater)
        setContentView(binding.root)

        if (ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.CAMERA
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            startCamera()
        } else {
            requestPermissionLauncher.launch(Manifest.permission.CAMERA)
        }
    }

    private fun startCamera() {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(this)

        cameraProviderFuture.addListener({
            val cameraProvider = cameraProviderFuture.get()

            val previewView: PreviewView = binding.previewView
            val preview = androidx.camera.core.Preview.Builder().build().also {
                it.setSurfaceProvider(previewView.surfaceProvider)
            }

            val analysisUseCase = ImageAnalysis.Builder()
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .build()

            val options = BarcodeScannerOptions.Builder()
                .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
                .build()
            val scanner = BarcodeScanning.getClient(options)

            analysisUseCase.setAnalyzer(cameraExecutor) { imageProxy: ImageProxy ->
                processImageProxy(scanner, imageProxy)
            }

            try {
                cameraProvider.unbindAll()
                cameraProvider.bindToLifecycle(
                    this,
                    CameraSelector.DEFAULT_BACK_CAMERA,
                    preview,
                    analysisUseCase
                )
            } catch (e: Exception) {
                Toast.makeText(this, "Unable to start camera", Toast.LENGTH_SHORT).show()
                finish()
            }
        }, ContextCompat.getMainExecutor(this))
    }

    private fun processImageProxy(
        scanner: com.google.mlkit.vision.barcode.BarcodeScanner,
        imageProxy: ImageProxy
    ) {
        if (processingBarcode) {
            imageProxy.close()
            return
        }

        val mediaImage = imageProxy.image
        if (mediaImage != null) {
            val image = InputImage.fromMediaImage(mediaImage, imageProxy.imageInfo.rotationDegrees)
            processingBarcode = true
            val result: Task<List<Barcode>> = scanner.process(image)
                .addOnSuccessListener { barcodes ->
                    if (barcodes.isNotEmpty()) {
                        val value = barcodes.first().rawValue
                        if (!value.isNullOrEmpty()) {
                            handleScannedValue(value)
                        }
                    }
                }
                .addOnFailureListener {
                    // Ignore for now
                }
                .addOnCompleteListener {
                    processingBarcode = false
                    imageProxy.close()
                }
        } else {
            imageProxy.close()
        }
    }

    private fun handleScannedValue(rawValue: String) {
        // Expecting format like "BIN1_948271"
        val parts = rawValue.split("_")
        if (parts.isEmpty()) {
            runOnUiThread {
                Toast.makeText(this, "Invalid QR code", Toast.LENGTH_SHORT).show()
            }
            return
        }

        val binId = parts[0]
        val user = FirebaseAuth.getInstance().currentUser
        if (user == null) {
            runOnUiThread {
                Toast.makeText(this, "You must be logged in", Toast.LENGTH_SHORT).show()
            }
            return
        }

        val uid = user.uid
        val firestore = FirebaseFirestore.getInstance()
        val userDocRef = firestore.collection("users").document(uid)

        userDocRef.get()
            .addOnSuccessListener { doc ->
                val name = doc.getString("name") ?: "Anonymous"
                val data = hashMapOf(
                    "uid" to uid,
                    "name" to name,
                    "assignedAt" to FieldValue.serverTimestamp()
                )

                firestore.collection("bins")
                    .document(binId)
                    .collection("active_user")
                    .document("current")
                    .set(data)
                    .addOnSuccessListener {
                        Toast.makeText(this, "Bin linked successfully", Toast.LENGTH_SHORT).show()
                        finish()
                    }
                    .addOnFailureListener { e ->
                        Toast.makeText(this, e.localizedMessage ?: "Failed to link bin", Toast.LENGTH_SHORT).show()
                    }
            }
            .addOnFailureListener { e ->
                Toast.makeText(this, e.localizedMessage ?: "Failed to fetch user info", Toast.LENGTH_SHORT).show()
            }
    }
}

