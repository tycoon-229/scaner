package com.fpt.yuyama

import android.graphics.Bitmap
import android.util.Log
import com.google.zxing.BarcodeFormat
import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.LuminanceSource
import com.google.zxing.NotFoundException
import com.google.zxing.PlanarYUVLuminanceSource
import com.google.zxing.RGBLuminanceSource
import com.google.zxing.Result
import com.google.zxing.ResultMetadataType
import com.google.zxing.common.HybridBinarizer
import com.google.zxing.oned.MultiFormatOneDReader
import com.google.zxing.pdf417.PDF417Reader
import java.util.EnumMap
import java.util.EnumSet

/**
 * Native decoder cho mã vạch GS1 Composite (1D Linear Primary + 2D CC-A/B/C MicroPDF417).
 *
 * Tính năng nâng cao:
 * 1. Tách biệt 100% giữa Giải mã 1D và Giải mã 2D.
 * 2. Lọc bỏ chuỗi rác/ký tự nhị phân bị nhiễu mã hóa (MicroPDF417 binary compaction).
 * 3. Bộ đệm liên kết trượt (Sliding Window Pairing Buffer 600ms) để ghép nối 1D và 2D khi hai mã được quét liên tiếp qua các frame camera.
 * 4. Bảo vệ tính toàn vẹn (Integrity Guard): Nếu 1D có Linkage Flag nhưng thiếu 2D => Báo từ chối.
 */
object Gs1CompositeNativeDecoder {

    private const val TAG = "GS1Composite"
    private const val PAIRING_WINDOW_MS = 600L // Cửa sổ thời gian ghép nối giữa 1D và 2D (600ms)

    data class ComponentResult(
        val text: String,
        val formatName: String,
        val is2D: Boolean,
        val timestamp: Long,
        val hasLinkageFlag: Boolean
    )

    data class Gs1CompositeResult(
        val fullText: String,
        val primary1dText: String?,
        val composite2dText: String?,
        val symbology: String,
        val parsedAiMap: Map<String, String>? = null
    )

    private val oneDHints = EnumMap<DecodeHintType, Any>(DecodeHintType::class.java).apply {
        put(DecodeHintType.TRY_HARDER, true)
        put(
            DecodeHintType.POSSIBLE_FORMATS,
            EnumSet.of(
                BarcodeFormat.EAN_13,
                BarcodeFormat.EAN_8,
                BarcodeFormat.UPC_A,
                BarcodeFormat.UPC_E,
                BarcodeFormat.CODE_128,
                BarcodeFormat.CODE_39,
                BarcodeFormat.CODE_93,
                BarcodeFormat.ITF,
                BarcodeFormat.CODABAR,
                BarcodeFormat.RSS_14,
                BarcodeFormat.RSS_EXPANDED
            )
        )
    }

    private val twoDHints = EnumMap<DecodeHintType, Any>(DecodeHintType::class.java).apply {
        put(DecodeHintType.TRY_HARDER, true)
        put(
            DecodeHintType.POSSIBLE_FORMATS,
            EnumSet.of(
                BarcodeFormat.PDF_417
            )
        )
    }

    private val oneDReader = MultiFormatOneDReader(oneDHints)
    private val pdf417Reader = PDF417Reader()

    // Bộ đệm trượt lưu kết quả 1D và 2D gần nhất để ghép nối liên frame
    @Volatile private var cached1DResult: ComponentResult? = null
    @Volatile private var cached1DTimestamp: Long = 0L

    @Volatile private var cached2DResult: ComponentResult? = null
    @Volatile private var cached2DTimestamp: Long = 0L

    fun decodeYuvLuminance(
        yArray: ByteArray,
        width: Int,
        height: Int,
        rowStride: Int
    ): Gs1CompositeResult? {
        val yuvSource = PlanarYUVLuminanceSource(
            yArray, width, height,
            0, 0, width, height,
            false
        )
        return decodeLuminanceSource(yuvSource)
    }

    fun decodeBitmap(bitmap: Bitmap): Gs1CompositeResult? {
        val width = bitmap.width
        val height = bitmap.height
        val pixels = IntArray(width * height)
        bitmap.getPixels(pixels, 0, width, 0, 0, width, height)
        val rgbSource = RGBLuminanceSource(width, height, pixels)
        return decodeLuminanceSource(rgbSource)
    }

    private fun decodeLuminanceSource(source: LuminanceSource): Gs1CompositeResult? {
        val binaryBitmap = BinaryBitmap(HybridBinarizer(source))
        val now = System.currentTimeMillis()

        // ---------------------------------------------------------------------
        // BƯỚC 1 & BƯỚC 2: Giải mã ĐỘC LẬP thành phần 1D
        // ---------------------------------------------------------------------
        val current1D = decode1D(binaryBitmap, now)
        if (current1D != null) {
            cached1DResult = current1D
            cached1DTimestamp = now
        }

        // ---------------------------------------------------------------------
        // BƯỚC 4: Giải mã ĐỘC LẬP thành phần 2D (MicroPDF417 / PDF417)
        // ---------------------------------------------------------------------
        val current2D = decode2D(binaryBitmap, now)
        if (current2D != null) {
            cached2DResult = current2D
            cached2DTimestamp = now
        }

        // Lấy kết quả còn hiệu lực từ bộ đệm trượt (Sliding Window Buffer 600ms)
        val effective1D = if (now - cached1DTimestamp <= PAIRING_WINDOW_MS) cached1DResult else null
        val effective2D = if (now - cached2DTimestamp <= PAIRING_WINDOW_MS) cached2DResult else null

        if (effective1D == null && effective2D == null) {
            return null
        }

        // ---------------------------------------------------------------------
        // BƯỚC 3: Kiểm tra cờ liên kết (Check Linkage Flag)
        // ---------------------------------------------------------------------
        val hasLinkageFlag = effective1D?.hasLinkageFlag == true ||
                (effective1D != null && (effective1D.text.startsWith("01") || effective1D.text.startsWith("(01)")))

        Log.d(
            TAG,
            "=== FRAME DECODE === 1D: [${effective1D?.formatName ?: "None"}] '${effective1D?.text ?: ""}' | " +
                    "2D: [${effective2D?.formatName ?: "None"}] '${effective2D?.text ?: ""}' | " +
                    "LinkageFlag: $hasLinkageFlag"
        )

        // LƯU Ý BẢO VỆ TÍNH TOÀN VẸN (Integrity Guard):
        // Nếu phát hiện cờ liên kết 1D (Linkage Flag) nhưng KHÔNG giải mã được 2D (do rách, xước, nhòe)
        // -> Trả về null để không nhả kết quả đọc thiếu dữ liệu GS1 Composite!
        if (hasLinkageFlag && effective2D == null) {
            Log.w(
                TAG,
                "[INTEGRITY GUARD REJECT] 1D Linkage Flag is active (${effective1D?.text}), but 2D composite component is missing or damaged!"
            )
            return null
        }

        // ---------------------------------------------------------------------
        // BƯỚC 5: Ghép nối dữ liệu (Concatenation)
        // ---------------------------------------------------------------------
        val text1D = effective1D?.text
        val text2D = effective2D?.text

        val fullText = when {
            text1D != null && text2D != null -> "$text1D | $text2D"
            text1D != null -> text1D
            text2D != null -> text2D
            else -> return null
        }

        val symbologyName = when {
            text1D != null && text2D != null -> "GS1 Composite (${effective2D.formatName})"
            text1D != null -> effective1D.formatName
            text2D != null -> effective2D.formatName
            else -> "Unknown"
        }

        Log.i(TAG, "[GS1 COMPOSITE SUCCESS] Symbology: $symbologyName | Result: $fullText")

        // Reset bộ đệm sau khi ghép thành công
        if (text1D != null && text2D != null) {
            cached1DResult = null
            cached2DResult = null
        }

        // ---------------------------------------------------------------------
        // BƯỚC 6 & BƯỚC 7: Trả kết quả về App & Phân rã AI (Application Identifier Parsing)
        // ---------------------------------------------------------------------
        val aiMap = parseGs1ApplicationIdentifiers(fullText)
        if (aiMap.isNotEmpty()) {
            Log.i(TAG, "[PARSED AI MAP] $aiMap")
        }

        return Gs1CompositeResult(
            fullText = fullText,
            primary1dText = text1D,
            composite2dText = text2D,
            symbology = symbologyName,
            parsedAiMap = if (aiMap.isNotEmpty()) aiMap else null
        )
    }

    /**
     * BƯỚC 1 & 2: Hàm giải mã 1D ĐỘC LẬP
     */
    private fun decode1D(bitmap: BinaryBitmap, timestamp: Long): ComponentResult? {
        return try {
            val res: Result = oneDReader.decode(bitmap, oneDHints)
            val formatName = res.barcodeFormat?.name ?: "1D Barcode"
            val text = res.text ?: return null

            if (!isReadableText(text)) return null

            val hasLinkage = res.resultMetadata?.containsKey(ResultMetadataType.SYMBOLOGY_IDENTIFIER) == true ||
                    res.barcodeFormat == BarcodeFormat.RSS_14 ||
                    res.barcodeFormat == BarcodeFormat.RSS_EXPANDED

            Log.d(TAG, "[1D SUCCESS] Format: $formatName | Text: $text | HasLinkage: $hasLinkage")

            ComponentResult(
                text = text,
                formatName = formatName,
                is2D = false,
                timestamp = timestamp,
                hasLinkageFlag = hasLinkage
            )
        } catch (ignored: NotFoundException) {
            null
        } catch (e: Exception) {
            null
        }
    }

    /**
     * BƯỚC 4: Hàm giải mã 2D ĐỘC LẬP (MicroPDF417 / PDF417)
     * Thêm bộ lọc chống mã hóa byte bị rác (Garbled binary compaction text filter).
     */
    private fun decode2D(bitmap: BinaryBitmap, timestamp: Long): ComponentResult? {
        return try {
            val res: Result = pdf417Reader.decode(bitmap, twoDHints)
            val text = parsePdf417Text(res) ?: return null

            Log.d(TAG, "[2D SUCCESS] Format: MicroPDF417 / PDF417 | Text: $text")

            ComponentResult(
                text = text,
                formatName = "MicroPDF417 / PDF417",
                is2D = true,
                timestamp = timestamp,
                hasLinkageFlag = true
            )
        } catch (ignored: NotFoundException) {
            null
        } catch (e: Exception) {
            null
        }
    }

    /**
     * Lọc và xử lý mã hóa ký tự MicroPDF417/PDF417 chống ký tự rác nhị phân.
     */
    private fun parsePdf417Text(res: Result): String? {
        val rawText = res.text ?: return null

        // 1. Kiểm tra mảng Byte Segments
        @Suppress("UNCHECKED_CAST")
        val byteSegments = res.resultMetadata?.get(ResultMetadataType.BYTE_SEGMENTS) as? List<ByteArray>
        if (!byteSegments.isNullOrEmpty()) {
            val combinedBytes = byteSegments.reduce { acc, bytes -> acc + bytes }
            val decodedUtf8 = String(combinedBytes, Charsets.UTF-8)
            if (decodedUtf8.isNotBlank() && isReadableText(decodedUtf8)) {
                return cleanGs1ControlChars(decodedUtf8)
            }
        }

        // 2. Kiểm tra rawBytes
        if (res.rawBytes != null && res.rawBytes.isNotEmpty()) {
            val decodedLatin1 = String(res.rawBytes, Charsets.ISO_8859_1)
            val decodedUtf8 = String(res.rawBytes, Charsets.UTF-8)
            val candidate = if (isReadableText(decodedUtf8)) decodedUtf8 else decodedLatin1
            if (candidate.isNotBlank() && isReadableText(candidate)) {
                return cleanGs1ControlChars(candidate)
            }
        }

        // 3. Fallback rawText nếu đọc được
        if (isReadableText(rawText)) {
            return cleanGs1ControlChars(rawText)
        }

        return null
    }

    /**
     * Kiểm tra chuỗi có chứa các ký tự có thể đọc được (ASCII/Printable), loại bỏ ký tự nhị phân rác.
     */
    private fun isReadableText(str: String): Boolean {
        if (str.isBlank()) return false
        val printableCount = str.count { it in ' '..'~' || it == '\n' || it == '\r' || it == '\t' }
        return (printableCount.toFloat() / str.length) >= 0.70f
    }

    /**
     * Làm sạch ký tự điều khiển GS1 (FNC1 / 0x1D / Group Separator).
     */
    private fun cleanGs1ControlChars(str: String): String {
        return str.replace("\u001D", "")
            .replace("\u001E", "")
            .replace("\u0004", "")
            .filter { it in ' '..'~' }
            .trim()
    }

    /**
     * BƯỚC 7: Phân rã AI (Application Identifier Parsing)
     */
    fun parseGs1ApplicationIdentifiers(rawText: String): Map<String, String> {
        val aiMap = mutableMapOf<String, String>()
        var text = rawText.replace("(", "").replace(")", "")

        // AI 01: GTIN (14 chữ số)
        if (text.length >= 16 && (text.startsWith("01") || rawText.contains("(01)"))) {
            val gtinIdx = text.indexOf("01")
            if (gtinIdx != -1 && text.length >= gtinIdx + 16) {
                aiMap["01_GTIN"] = text.substring(gtinIdx + 2, gtinIdx + 16)
                text = text.substring(gtinIdx + 16)
            }
        }

        // AI 10: Lot Number (Số lô)
        val lotIdx = text.indexOf("10")
        if (lotIdx != -1) {
            val lotValue = text.substring(lotIdx + 2).takeWhile { it != '|' && it != ' ' && it != '(' }
            if (lotValue.isNotEmpty()) {
                aiMap["10_LOT"] = lotValue
            }
        }

        // AI 17: Expiration Date (Hạn sử dụng - YYMMDD)
        val expIdx = text.indexOf("17")
        if (expIdx != -1 && text.length >= expIdx + 8) {
            aiMap["17_EXPIRY"] = text.substring(expIdx + 2, expIdx + 8)
        }

        // AI 21: Serial Number (Số sê-ri)
        val snIdx = text.indexOf("21")
        if (snIdx != -1) {
            val snValue = text.substring(snIdx + 2).takeWhile { it != '|' && it != ' ' && it != '(' }
            if (snValue.isNotEmpty()) {
                aiMap["21_SERIAL"] = snValue
            }
        }

        return aiMap
    }
}
