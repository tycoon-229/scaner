package com.fpt.yuyama.scanner.gs1

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

object Gs1CompositeNativeDecoder {

    private const val FORMAT_CODE128 = 1 shl 4
    private const val FORMAT_DATABAR = 1 shl 5
    private const val FORMAT_DATABAR_EXPANDED = 1 shl 6
    private const val FORMAT_EAN8 = 1 shl 8
    private const val FORMAT_EAN13 = 1 shl 9
    private const val FORMAT_PDF417 = 1 shl 12
    private const val FORMAT_UPCA = 1 shl 14
    private const val FORMAT_UPCE = 1 shl 15
    private const val FORMAT_DATABAR_LIMITED = 1 shl 19
    private const val FORMAT_MICRO_PDF417 = 1 shl 20

    init {
        System.loadLibrary("gs1_composite_scanner")
    }

    fun decodeYuvLuminance(
        yArray: ByteArray,
        width: Int,
        height: Int,
        rowStride: Int
    ): Map<String, Any?> {
        val startedAt = System.nanoTime()
        val nativeResult = decodeYuvNative(yArray, width, height, rowStride).orEmpty()
        return assembleNativeResult(nativeResult, "yuv", startedAt)
    }

    fun decodeBitmapBytes(imageBytes: ByteArray): Map<String, Any?> {
        val startedAt = System.nanoTime()
        val bitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
            ?: return emptyResult("bitmap", 0, "BitmapFactory could not decode image bytes")
        val luminance = bitmap.toLuminanceBytes()
        val nativeResult = decodeYuvNative(
            luminance,
            bitmap.width,
            bitmap.height,
            bitmap.width
        ).orEmpty()
        return assembleNativeResult(nativeResult, "bitmap", startedAt)
    }

    private external fun decodeYuvNative(
        imageBytes: ByteArray,
        width: Int,
        height: Int,
        rowStride: Int
    ): Map<String, Any?>?

    private fun assembleNativeResult(
        nativeResult: Map<String, Any?>,
        source: String,
        startedAt: Long
    ): Map<String, Any?> {
        val nativeDurationMs = nativeResult["durationMs"] as? Int ?: 0
        val codes = (nativeResult["codes"] as? List<*>)
            .orEmpty()
            .filterIsInstance<Map<String, Any?>>()
            .mapNotNull(::candidateFromMap)

        val assembly = assemble(codes)
        val durationMs = ((System.nanoTime() - startedAt) / 1_000_000L).toInt()
        if (assembly == null) {
            return emptyResult(
                source = source,
                durationMs = durationMs,
                warning = "No GS1 Composite pair found from ${codes.size} native code candidate(s)",
                codes = codes.map(CodeCandidate::toMap),
                nativeDurationMs = nativeDurationMs
            )
        }

        return assembly.toMap(
            source = source,
            durationMs = durationMs,
            nativeDurationMs = nativeDurationMs,
            rawCodes = codes.map(CodeCandidate::toMap)
        )
    }

    private fun assemble(codes: List<CodeCandidate>): CompositeAssembly? {
        val linearCodes = codes.filter { it.isLinear }
        val componentCodes = codes.filter { it.isCompositeComponent }
        if (linearCodes.isEmpty() || componentCodes.isEmpty()) return null

        val best = linearCodes
            .flatMap { linear -> componentCodes.mapNotNull { component -> scorePair(linear, component) } }
            .maxByOrNull { it.score }
            ?: return null

        val warnings = mutableListOf<String>()
        warnings += best.warnings

        val linearElements = Gs1NativeElementParser.parse(best.linear.text, best.linear.format)
        val componentElements = Gs1NativeElementParser.parse(best.component.text, best.component.format)
        if (linearElements.isEmpty()) {
            warnings += "Linear payload could not be parsed as GS1 element strings."
        }
        if (componentElements.isEmpty()) {
            warnings += "2D component payload could not be parsed as GS1 element strings."
        }

        val typeEstimate = when (best.component.format) {
            FORMAT_MICRO_PDF417 -> "CC-A/CC-B candidate"
            FORMAT_PDF417 -> if (best.linear.format == FORMAT_CODE128) {
                "CC-C candidate"
            } else {
                "Composite candidate"
            }
            else -> "Composite candidate"
        }

        return CompositeAssembly(
            linear = best.linear,
            component = best.component,
            confidence = best.score.coerceIn(0.0, 1.0),
            typeEstimate = typeEstimate,
            elements = linearElements + componentElements,
            warnings = warnings
        )
    }

    private fun scorePair(linear: CodeCandidate, component: CodeCandidate): PairCandidate? {
        val overlap = max(0, min(linear.right, component.right) - max(linear.left, component.left))
        val overlapRatio = overlap.toDouble() / min(linear.width, component.width).coerceAtLeast(1)
        val componentAbove = component.centerY < linear.centerY && component.bottom <= linear.bottom
        val gap = linear.top - component.bottom
        val maxReasonableGap = max(linear.height * 1.8, component.height * 1.2)
        val closeEnough = gap <= maxReasonableGap && gap >= -component.height * 0.6

        if (overlapRatio < 0.35 || !componentAbove || !closeEnough) return null

        val gapScore = 1 - (abs(gap) / maxReasonableGap).coerceIn(0.0, 1.0)
        val score = overlapRatio * 0.55 + gapScore * 0.25 + 0.20
        return PairCandidate(linear, component, score, emptyList())
    }

    private fun candidateFromMap(value: Map<String, Any?>): CodeCandidate? {
        val text = value["text"] as? String ?: return null
        val format = value["format"] as? Int ?: return null
        if (text.isEmpty()) return null

        return CodeCandidate(
            text = text,
            format = format,
            imageWidth = value["imageWidth"] as? Int ?: 0,
            imageHeight = value["imageHeight"] as? Int ?: 0,
            topLeftX = value["topLeftX"] as? Int ?: 0,
            topLeftY = value["topLeftY"] as? Int ?: 0,
            topRightX = value["topRightX"] as? Int ?: 0,
            topRightY = value["topRightY"] as? Int ?: 0,
            bottomLeftX = value["bottomLeftX"] as? Int ?: 0,
            bottomLeftY = value["bottomLeftY"] as? Int ?: 0,
            bottomRightX = value["bottomRightX"] as? Int ?: 0,
            bottomRightY = value["bottomRightY"] as? Int ?: 0,
            isInverted = value["isInverted"] as? Boolean ?: false,
            isMirrored = value["isMirrored"] as? Boolean ?: false,
            pass = value["pass"] as? String ?: "unknown"
        )
    }

    private fun emptyResult(
        source: String,
        durationMs: Int,
        warning: String,
        codes: List<Map<String, Any?>> = emptyList(),
        nativeDurationMs: Int = 0
    ): Map<String, Any?> {
        return mapOf(
            "hasResult" to false,
            "source" to source,
            "durationMs" to durationMs,
            "nativeDurationMs" to nativeDurationMs,
            "warning" to warning,
            "codes" to codes
        )
    }

    private fun Bitmap.toLuminanceBytes(): ByteArray {
        val width = width
        val height = height
        val pixels = IntArray(width * height)
        getPixels(pixels, 0, width, 0, 0, width, height)

        val luminance = ByteArray(width * height)
        for (i in pixels.indices) {
            val pixel = pixels[i]
            val r = (pixel shr 16) and 0xFF
            val g = (pixel shr 8) and 0xFF
            val b = pixel and 0xFF
            luminance[i] = ((r * 38 + g * 75 + b * 15) shr 7).toByte()
        }
        return luminance
    }

    private data class PairCandidate(
        val linear: CodeCandidate,
        val component: CodeCandidate,
        val score: Double,
        val warnings: List<String>
    )

    private data class CompositeAssembly(
        val linear: CodeCandidate,
        val component: CodeCandidate,
        val confidence: Double,
        val typeEstimate: String,
        val elements: List<Gs1NativeElement>,
        val warnings: List<String>
    ) {
        fun toMap(
            source: String,
            durationMs: Int,
            nativeDurationMs: Int,
            rawCodes: List<Map<String, Any?>>
        ): Map<String, Any?> {
            return mapOf(
                "hasResult" to true,
                "source" to source,
                "durationMs" to durationMs,
                "nativeDurationMs" to nativeDurationMs,
                "formatName" to "GS1 Composite Native POC",
                "typeEstimate" to typeEstimate,
                "confidence" to confidence,
                "linear" to linear.toMap(),
                "component" to component.toMap(),
                "elements" to elements.map(Gs1NativeElement::toMap),
                "warnings" to warnings,
                "codes" to rawCodes,
                "text" to displayText()
            )
        }

        private fun displayText(): String {
            val sb = StringBuilder()
                .appendLine("Confidence: ${(confidence * 100).toInt()}%")
                .appendLine("Linear: ${linear.formatName}")
                .appendLine(linear.text.visibleSeparators())
                .appendLine()
                .appendLine("2D component: ${component.formatName}")
                .appendLine(component.text.visibleSeparators())

            if (elements.isNotEmpty()) {
                sb.appendLine()
                    .appendLine("Parsed GS1 fields:")
                elements.forEach {
                    sb.appendLine("(${it.ai}) ${it.title}: ${it.value.visibleSeparators()}")
                }
            }

            if (warnings.isNotEmpty()) {
                sb.appendLine()
                    .appendLine("Native POC warnings:")
                warnings.forEach { sb.appendLine("- $it") }
            }

            return sb.toString().trim()
        }
    }

    private data class CodeCandidate(
        val text: String,
        val format: Int,
        val imageWidth: Int,
        val imageHeight: Int,
        val topLeftX: Int,
        val topLeftY: Int,
        val topRightX: Int,
        val topRightY: Int,
        val bottomLeftX: Int,
        val bottomLeftY: Int,
        val bottomRightX: Int,
        val bottomRightY: Int,
        val isInverted: Boolean,
        val isMirrored: Boolean,
        val pass: String
    ) {
        val left: Int get() = min(min(topLeftX, topRightX), min(bottomLeftX, bottomRightX))
        val right: Int get() = max(max(topLeftX, topRightX), max(bottomLeftX, bottomRightX))
        val top: Int get() = min(min(topLeftY, topRightY), min(bottomLeftY, bottomRightY))
        val bottom: Int get() = max(max(topLeftY, topRightY), max(bottomLeftY, bottomRightY))
        val width: Int get() = right - left
        val height: Int get() = bottom - top
        val centerY: Double get() = (top + bottom) / 2.0
        val isLinear: Boolean
            get() = format == FORMAT_CODE128 ||
                format == FORMAT_DATABAR ||
                format == FORMAT_DATABAR_EXPANDED ||
                format == FORMAT_DATABAR_LIMITED ||
                format == FORMAT_EAN8 ||
                format == FORMAT_EAN13 ||
                format == FORMAT_UPCA ||
                format == FORMAT_UPCE
        val isCompositeComponent: Boolean
            get() = format == FORMAT_PDF417 || format == FORMAT_MICRO_PDF417
        val formatName: String
            get() = when (format) {
                FORMAT_CODE128 -> "Code128"
                FORMAT_DATABAR -> "DataBar"
                FORMAT_DATABAR_EXPANDED -> "DataBarExpanded"
                FORMAT_DATABAR_LIMITED -> "DataBarLimited"
                FORMAT_EAN8 -> "EAN8"
                FORMAT_EAN13 -> "EAN13"
                FORMAT_PDF417 -> "PDF417"
                FORMAT_MICRO_PDF417 -> "MicroPDF417"
                FORMAT_UPCA -> "UPCA"
                FORMAT_UPCE -> "UPCE"
                else -> "Unknown"
            }

        fun toMap(): Map<String, Any?> {
            return mapOf(
                "text" to text,
                "format" to format,
                "formatName" to formatName,
                "imageWidth" to imageWidth,
                "imageHeight" to imageHeight,
                "topLeftX" to topLeftX,
                "topLeftY" to topLeftY,
                "topRightX" to topRightX,
                "topRightY" to topRightY,
                "bottomLeftX" to bottomLeftX,
                "bottomLeftY" to bottomLeftY,
                "bottomRightX" to bottomRightX,
                "bottomRightY" to bottomRightY,
                "isInverted" to isInverted,
                "isMirrored" to isMirrored,
                "pass" to pass
            )
        }
    }
}

private data class Gs1NativeElement(
    val ai: String,
    val value: String,
    val title: String
) {
    fun toMap(): Map<String, String> {
        return mapOf("ai" to ai, "value" to value, "title" to title)
    }
}

private object Gs1NativeElementParser {

    fun parse(raw: String, fallbackFormat: Int): List<Gs1NativeElement> {
        val normalized = normalize(raw, fallbackFormat)
        if (normalized.isEmpty()) return emptyList()
        if (normalized.contains("(")) return parseBracketed(normalized)
        return parseRaw(normalized)
    }

    private fun normalize(raw: String, fallbackFormat: Int): String {
        val withoutAim = raw.trim().replace(Regex("^\\][A-Za-z0-9]{2}"), "")
        if (withoutAim.all(Char::isDigit)) {
            return when {
                fallbackFormat == (1 shl 9) && withoutAim.length == 13 ->
                    "01${withoutAim.padStart(14, '0')}"
                fallbackFormat == (1 shl 14) && withoutAim.length == 12 ->
                    "01${withoutAim.padStart(14, '0')}"
                fallbackFormat == (1 shl 8) && withoutAim.length == 8 ->
                    "01${withoutAim.padStart(14, '0')}"
                else -> withoutAim
            }
        }
        return withoutAim
    }

    private fun parseBracketed(input: String): List<Gs1NativeElement> {
        return Regex("\\((\\d{2,4})\\)([^\\(]*)")
            .findAll(input)
            .map {
                val ai = it.groupValues[1]
                val value = it.groupValues[2].replace("\u001d", "").trim()
                Gs1NativeElement(ai, value, titleFor(ai))
            }
            .toList()
    }

    private fun parseRaw(input: String): List<Gs1NativeElement> {
        val elements = mutableListOf<Gs1NativeElement>()
        var index = 0
        while (index < input.length) {
            if (input[index].code == 29) {
                index++
                continue
            }

            val definition = matchAi(input, index) ?: break
            index += definition.ai.length
            if (index >= input.length) break

            val value: String
            if (definition.fixedLength != null) {
                val end = min(input.length, index + definition.fixedLength)
                value = input.substring(index, end)
                index = end
            } else {
                val separator = input.indexOf('\u001d', index)
                val maxEnd = min(input.length, index + definition.maxLength)
                val end = if (separator == -1) maxEnd else min(separator, maxEnd)
                value = input.substring(index, end)
                index = end
            }

            elements += Gs1NativeElement(definition.ai, value, definition.title)
        }
        return elements
    }

    private fun matchAi(input: String, index: Int): AiDefinition? {
        fixedDefinitions.firstOrNull { input.startsWith(it.ai, index) }?.let { return it }
        variableDefinitions.firstOrNull { input.startsWith(it.ai, index) }?.let { return it }

        if (index + 4 <= input.length) {
            val ai4 = input.substring(index, index + 4)
            val prefix = ai4.substring(0, 3).toIntOrNull()
            if (prefix != null && prefix in 310..369) {
                return AiDefinition.fixed(ai4, 6, "Measurement")
            }
            if (Regex("^39[23]\\d$").matches(ai4)) {
                return AiDefinition.variable(ai4, 18, "Amount payable")
            }
        }

        if (index + 2 <= input.length) {
            val ai2 = input.substring(index, index + 2)
            if (ai2.startsWith("9")) return AiDefinition.variable(ai2, 90, "Company internal")
        }

        return null
    }

    private fun titleFor(ai: String): String {
        (fixedDefinitions + variableDefinitions).firstOrNull { it.ai == ai }?.let { return it.title }
        if (Regex("^3[1-6]\\d\\d$").matches(ai)) return "Measurement"
        if (Regex("^39[23]\\d$").matches(ai)) return "Amount payable"
        if (ai.startsWith("9")) return "Company internal"
        return "AI $ai"
    }

    private val fixedDefinitions = listOf(
        AiDefinition.fixed("8017", 18, "GSRN provider"),
        AiDefinition.fixed("8018", 18, "GSRN recipient"),
        AiDefinition.fixed("8005", 6, "Price per unit of measure"),
        AiDefinition.fixed("8006", 18, "ITIP"),
        AiDefinition.fixed("8026", 18, "ITIP contained"),
        AiDefinition.fixed("415", 13, "Pay to GLN"),
        AiDefinition.fixed("414", 13, "Physical location GLN"),
        AiDefinition.fixed("422", 3, "Country of origin"),
        AiDefinition.fixed("424", 3, "Country of processing"),
        AiDefinition.fixed("425", 3, "Country of disassembly"),
        AiDefinition.fixed("426", 3, "Country covering full process"),
        AiDefinition.fixed("00", 18, "SSCC"),
        AiDefinition.fixed("01", 14, "GTIN"),
        AiDefinition.fixed("02", 14, "Content GTIN"),
        AiDefinition.fixed("11", 6, "Production date"),
        AiDefinition.fixed("12", 6, "Due date"),
        AiDefinition.fixed("13", 6, "Packaging date"),
        AiDefinition.fixed("15", 6, "Best before date"),
        AiDefinition.fixed("16", 6, "Sell by date"),
        AiDefinition.fixed("17", 6, "Expiration date"),
        AiDefinition.fixed("20", 2, "Product variant")
    )

    private val variableDefinitions = listOf(
        AiDefinition.variable("8110", 70, "Coupon code"),
        AiDefinition.variable("8112", 70, "Paperless coupon code"),
        AiDefinition.variable("8004", 30, "GIAI"),
        AiDefinition.variable("8008", 12, "Production date/time"),
        AiDefinition.variable("8010", 30, "CPID"),
        AiDefinition.variable("8011", 12, "CPID serial"),
        AiDefinition.variable("8012", 20, "Software version"),
        AiDefinition.variable("8200", 70, "Extended packaging URL"),
        AiDefinition.variable("240", 30, "Additional product identification"),
        AiDefinition.variable("241", 30, "Customer part number"),
        AiDefinition.variable("242", 6, "Made-to-order variation"),
        AiDefinition.variable("243", 20, "Packaging component number"),
        AiDefinition.variable("250", 30, "Secondary serial number"),
        AiDefinition.variable("251", 30, "Reference to source entity"),
        AiDefinition.variable("253", 30, "GDTI"),
        AiDefinition.variable("254", 20, "GLN extension component"),
        AiDefinition.variable("255", 25, "GCN"),
        AiDefinition.variable("400", 30, "Customer purchase order number"),
        AiDefinition.variable("401", 30, "GINC"),
        AiDefinition.variable("403", 30, "Routing code"),
        AiDefinition.variable("420", 20, "Ship to postal code"),
        AiDefinition.variable("421", 15, "Ship to postal code with country"),
        AiDefinition.variable("10", 20, "Batch or lot number"),
        AiDefinition.variable("21", 20, "Serial number"),
        AiDefinition.variable("22", 20, "Consumer product variant"),
        AiDefinition.variable("30", 8, "Variable count"),
        AiDefinition.variable("37", 8, "Count of trade items")
    )

    private data class AiDefinition(
        val ai: String,
        val fixedLength: Int?,
        val maxLength: Int,
        val title: String
    ) {
        companion object {
            fun fixed(ai: String, length: Int, title: String) =
                AiDefinition(ai, length, length, title)

            fun variable(ai: String, maxLength: Int, title: String) =
                AiDefinition(ai, null, maxLength, title)
        }
    }
}

private fun String.visibleSeparators(): String = replace("\u001d", "<GS>")
