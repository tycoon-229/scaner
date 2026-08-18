package com.fpt.yuyama.scanner.gs1cca

import org.json.JSONArray
import org.json.JSONObject

object Gs1CcaCcbRustDecoder {

    private val libraryLoadError: String? = try {
        System.loadLibrary("gs1_cca_ccb_scanner")
        null
    } catch (error: UnsatisfiedLinkError) {
        error.message ?: "Rust GS1 CC-A/B scanner library is unavailable"
    }

    fun decodeYuvLuminance(
        yArray: ByteArray,
        width: Int,
        height: Int,
        rowStride: Int,
        hintLeft: Int,
        hintTop: Int,
        hintRight: Int,
        hintBottom: Int
    ): Map<String, Any?> {
        val loadError = libraryLoadError
        if (loadError != null) {
            return emptyResult("rust-yuv", 0, loadError)
        }

        val startedAt = System.nanoTime()
        val json = decodeYuvNative(
            yArray,
            width,
            height,
            rowStride,
            hintLeft,
            hintTop,
            hintRight,
            hintBottom
        ).orEmpty()
        if (json.isEmpty()) {
            return emptyResult("rust-yuv", durationSince(startedAt), "Rust decoder returned empty JSON")
        }

        return try {
            val root = JSONObject(json)
            val nativeDurationMs = root.optLong("duration_ms", root.optLong("durationMs", 0L)).toInt()
            mapOf(
                "source" to root.optString("source", "rust-gs1-cca-ccb"),
                "durationMs" to durationSince(startedAt),
                "nativeDurationMs" to nativeDurationMs,
                "codes" to root.optJSONArray("codes").toCodeMaps(),
                "warnings" to root.optJSONArray("warnings").toStringList()
            )
        } catch (error: Exception) {
            emptyResult(
                "rust-yuv",
                durationSince(startedAt),
                "Rust decoder JSON parse failed: ${error.message ?: error.javaClass.simpleName}"
            )
        }
    }

    private external fun decodeYuvNative(
        imageBytes: ByteArray,
        width: Int,
        height: Int,
        rowStride: Int,
        hintLeft: Int,
        hintTop: Int,
        hintRight: Int,
        hintBottom: Int
    ): String?

    private fun durationSince(startedAt: Long): Int {
        return ((System.nanoTime() - startedAt) / 1_000_000L).toInt()
    }

    private fun emptyResult(
        source: String,
        durationMs: Int,
        warning: String
    ): Map<String, Any?> {
        return mapOf(
            "source" to source,
            "durationMs" to durationMs,
            "nativeDurationMs" to 0,
            "codes" to emptyList<Map<String, Any?>>(),
            "warnings" to listOf(warning),
            "warning" to warning
        )
    }

    private fun JSONArray?.toCodeMaps(): List<Map<String, Any?>> {
        if (this == null) return emptyList()
        return buildList {
            for (index in 0 until length()) {
                val code = optJSONObject(index) ?: continue
                add(
                    mapOf(
                        "source" to code.optString("source", "rust"),
                        "text" to code.optString("text", ""),
                        "format" to code.optInt("format", 0),
                        "formatName" to code.optString("formatName", ""),
                        "rawBytes" to code.optJSONArray("rawBytes").toIntList(),
                        "imageWidth" to code.optInt("imageWidth", 0),
                        "imageHeight" to code.optInt("imageHeight", 0),
                        "topLeftX" to code.optInt("topLeftX", 0),
                        "topLeftY" to code.optInt("topLeftY", 0),
                        "topRightX" to code.optInt("topRightX", 0),
                        "topRightY" to code.optInt("topRightY", 0),
                        "bottomLeftX" to code.optInt("bottomLeftX", 0),
                        "bottomLeftY" to code.optInt("bottomLeftY", 0),
                        "bottomRightX" to code.optInt("bottomRightX", 0),
                        "bottomRightY" to code.optInt("bottomRightY", 0)
                    )
                )
            }
        }
    }

    private fun JSONArray?.toIntList(): List<Int> {
        if (this == null) return emptyList()
        return buildList {
            for (index in 0 until length()) {
                add(optInt(index))
            }
        }
    }

    private fun JSONArray?.toStringList(): List<String> {
        if (this == null) return emptyList()
        return buildList {
            for (index in 0 until length()) {
                optString(index).takeIf(String::isNotEmpty)?.let(::add)
            }
        }
    }
}
