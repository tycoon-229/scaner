package com.fpt.yuyama.scanner.mlkit

import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.barcode.BarcodeScanner
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import java.util.concurrent.TimeUnit

class MlKitBarcodeNativeDecoder {
    private val scanner: BarcodeScanner = BarcodeScanning.getClient(
        BarcodeScannerOptions.Builder()
            .setBarcodeFormats(
                Barcode.FORMAT_CODE_128,
                Barcode.FORMAT_PDF417
            )
            .build()
    )

    fun decodeYuv420(
        yBytes: ByteArray,
        uBytes: ByteArray,
        vBytes: ByteArray,
        width: Int,
        height: Int,
        yRowStride: Int,
        yPixelStride: Int,
        uRowStride: Int,
        uPixelStride: Int,
        vRowStride: Int,
        vPixelStride: Int,
        rotationDegrees: Int
    ): Map<String, Any?> {
        val startedAt = System.nanoTime()
        val nv21 = yuv420ToNv21(
            yBytes = yBytes,
            uBytes = uBytes,
            vBytes = vBytes,
            width = width,
            height = height,
            yRowStride = yRowStride,
            yPixelStride = yPixelStride,
            uRowStride = uRowStride,
            uPixelStride = uPixelStride,
            vRowStride = vRowStride,
            vPixelStride = vPixelStride
        )
        val image = InputImage.fromByteArray(
            nv21,
            width,
            height,
            rotationDegrees,
            InputImage.IMAGE_FORMAT_NV21
        )
        val barcodes = Tasks.await(scanner.process(image), 1500, TimeUnit.MILLISECONDS)
        val durationMs = ((System.nanoTime() - startedAt) / 1_000_000L).toInt()
        return mapOf(
            "source" to "mlkit-yuv",
            "durationMs" to durationMs,
            "codes" to barcodes.map { it.toMap(width, height) }
        )
    }

    fun close() {
        scanner.close()
    }

    private fun yuv420ToNv21(
        yBytes: ByteArray,
        uBytes: ByteArray,
        vBytes: ByteArray,
        width: Int,
        height: Int,
        yRowStride: Int,
        yPixelStride: Int,
        uRowStride: Int,
        uPixelStride: Int,
        vRowStride: Int,
        vPixelStride: Int
    ): ByteArray {
        val ySize = width * height
        val nv21 = ByteArray(ySize + ySize / 2)
        var out = 0

        for (row in 0 until height) {
            var yIndex = row * yRowStride
            for (col in 0 until width) {
                nv21[out++] = if (yIndex < yBytes.size) yBytes[yIndex] else 0
                yIndex += yPixelStride
            }
        }

        val chromaHeight = height / 2
        val chromaWidth = width / 2
        for (row in 0 until chromaHeight) {
            for (col in 0 until chromaWidth) {
                val vIndex = row * vRowStride + col * vPixelStride
                val uIndex = row * uRowStride + col * uPixelStride
                nv21[out++] = if (vIndex < vBytes.size) vBytes[vIndex] else 0
                nv21[out++] = if (uIndex < uBytes.size) uBytes[uIndex] else 0
            }
        }

        return nv21
    }

    private fun Barcode.toMap(imageWidth: Int, imageHeight: Int): Map<String, Any?> {
        val bounds = boundingBox
        val corners = cornerPoints?.map { point ->
            mapOf("x" to point.x, "y" to point.y)
        }

        return mapOf(
            "format" to formatName(format),
            "rawValue" to rawValue,
            "displayValue" to displayValue,
            "rawBytes" to rawBytes,
            "valueType" to valueType,
            "imageWidth" to imageWidth,
            "imageHeight" to imageHeight,
            "boundingBox" to if (bounds == null) null else mapOf(
                "left" to bounds.left,
                "top" to bounds.top,
                "right" to bounds.right,
                "bottom" to bounds.bottom
            ),
            "cornerPoints" to corners
        )
    }

    private fun formatName(format: Int): String {
        return when (format) {
            Barcode.FORMAT_CODE_128 -> "Code128"
            Barcode.FORMAT_PDF417 -> "PDF417"
            else -> "Unknown"
        }
    }
}
