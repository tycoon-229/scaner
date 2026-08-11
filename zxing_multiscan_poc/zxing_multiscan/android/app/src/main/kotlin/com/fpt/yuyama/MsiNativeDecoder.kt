package com.fpt.yuyama

import android.graphics.Bitmap
import kotlin.math.max
import kotlin.math.min

object MsiNativeDecoder {

    enum class ChecksumScheme {
        AUTO,
        MOD_10,
        MOD_11,
        MOD_10_10,
        MOD_11_10,
        MOD_43,
        NONE
    }

    private const val ALPHANUMERIC_CHARS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-. $/+%"

    fun decodeBitmap(bitmap: Bitmap, scheme: ChecksumScheme = ChecksumScheme.AUTO): String? {
        val width = bitmap.width
        val height = bitmap.height
        val pixels = IntArray(width * height)
        bitmap.getPixels(pixels, 0, width, 0, 0, width, height)

        val scanRatios = floatArrayOf(0.50f, 0.40f, 0.60f, 0.30f, 0.70f, 0.25f, 0.75f, 0.45f, 0.55f, 0.35f, 0.65f, 0.20f, 0.80f)

        for (ratio in scanRatios) {
            val y = (height * ratio).toInt().coerceIn(0, height - 1)
            val luminanceRow = IntArray(width)

            for (x in 0 until width) {
                val pixel = pixels[y * width + x]
                val r = (pixel shr 16) and 0xFF
                val g = (pixel shr 8) and 0xFF
                val b = pixel and 0xFF
                luminanceRow[x] = (r * 38 + g * 75 + b * 15) shr 7
            }

            val result = decodeLuminanceRow(luminanceRow, scheme)
            if (result != null) return result
        }

        for (ratio in scanRatios) {
            val x = (width * ratio).toInt().coerceIn(0, width - 1)
            val luminanceCol = IntArray(height)

            for (y in 0 until height) {
                val pixel = pixels[y * width + x]
                val r = (pixel shr 16) and 0xFF
                val g = (pixel shr 8) and 0xFF
                val b = pixel and 0xFF
                luminanceCol[y] = (r * 38 + g * 75 + b * 15) shr 7
            }

            val result = decodeLuminanceRow(luminanceCol, scheme)
            if (result != null) return result
        }

        return null
    }

    fun decodeYuvLuminance(
        yArray: ByteArray,
        width: Int,
        height: Int,
        rowStride: Int,
        scheme: ChecksumScheme = ChecksumScheme.AUTO
    ): String? {
        val scanRatios = floatArrayOf(0.50f, 0.40f, 0.60f, 0.30f, 0.70f, 0.25f, 0.75f, 0.45f, 0.55f, 0.35f, 0.65f, 0.20f, 0.80f)

        for (ratio in scanRatios) {
            val y = (height * ratio).toInt().coerceIn(0, height - 1)
            val luminanceRow = IntArray(width)

            val rowOffset = y * rowStride
            for (x in 0 until width) {
                val offset = rowOffset + x
                if (offset < yArray.size) {
                    luminanceRow[x] = yArray[offset].toInt() and 0xFF
                }
            }

            val result = decodeLuminanceRow(luminanceRow, scheme)
            if (result != null) return result
        }

        for (ratio in scanRatios) {
            val x = (width * ratio).toInt().coerceIn(0, width - 1)
            val luminanceCol = IntArray(height)

            for (y in 0 until height) {
                val offset = y * rowStride + x
                if (offset < yArray.size) {
                    luminanceCol[y] = yArray[offset].toInt() and 0xFF
                }
            }

            val result = decodeLuminanceRow(luminanceCol, scheme)
            if (result != null) return result
        }

        return null
    }

    fun decodeMsiPlesseyFromWidths(barWidths: IntArray, scheme: ChecksumScheme = ChecksumScheme.AUTO): String? {
        val runs = ArrayList<Pair<Boolean, Int>>()
        var isBar = true
        for (w in barWidths) {
            if (w > 0) {
                runs.add(Pair(isBar, w))
            }
            isBar = !isBar
        }
        if (runs.size < 10) return null

        val forwardResult = parseRuns(runs, scheme)
        if (forwardResult != null) return forwardResult

        val reversedRuns = ArrayList<Pair<Boolean, Int>>(runs.asReversed())
        return parseRuns(reversedRuns, scheme)
    }

    private fun decodeLuminanceRow(luminance: IntArray, scheme: ChecksumScheme): String? {
        val width = luminance.size
        if (width < 30) return null

        val isBarArray = BooleanArray(width)
        val windowSize = max(8, width / 15)
        var windowSum = 0

        for (i in 0 until min(windowSize, width)) {
            windowSum += luminance[i]
        }

        for (x in 0 until width) {
            val left = max(0, x - windowSize / 2)
            val right = min(width - 1, x + windowSize / 2)
            val count = right - left + 1

            if (x > windowSize / 2 && x + windowSize / 2 < width) {
                windowSum += luminance[right] - luminance[left - 1]
            } else {
                var sum = 0
                for (j in left..right) sum += luminance[j]
                windowSum = sum
            }

            val localAvg = windowSum / count
            isBarArray[x] = luminance[x] < localAvg
        }

        val runs = ArrayList<Pair<Boolean, Int>>()
        var currentIsBar = isBarArray[0]
        var currentLen = 0

        for (x in 0 until width) {
            if (isBarArray[x] == currentIsBar) {
                currentLen++
            } else {
                if (currentLen > 0) {
                    runs.add(Pair(currentIsBar, currentLen))
                }
                currentIsBar = isBarArray[x]
                currentLen = 1
            }
        }
        if (currentLen > 0) {
            runs.add(Pair(currentIsBar, currentLen))
        }

        if (runs.size < 10) return null

        val forwardResult = parseRuns(runs, scheme)
        if (forwardResult != null) return forwardResult

        val reversedRuns = ArrayList<Pair<Boolean, Int>>(runs.asReversed())
        return parseRuns(reversedRuns, scheme)
    }

    private fun parseRuns(runs: List<Pair<Boolean, Int>>, scheme: ChecksumScheme): String? {
        val totalRuns = runs.size
        if (totalRuns < 10) return null

        for (startIdx in 0 until totalRuns - 8) {
            if (!runs[startIdx].first) continue

            val startBar = runs[startIdx].second.toFloat()
            val startSpace = runs[startIdx + 1].second.toFloat()
            val startTotal = startBar + startSpace

            if (startTotal <= 0) continue

            val startRatio = startBar / startTotal
            if (startRatio < 0.50f || startRatio > 0.85f) continue

            var estX = startTotal / 3.0f
            if (estX <= 0) continue

            if (startIdx > 0) {
                val quietBefore = runs[startIdx - 1]
                if (!quietBefore.first && quietBefore.second < estX * 3.0f) {
                    continue
                }
            }

            val rawBits = ArrayList<Int>()
            rawBits.add(1)

            var idx = startIdx + 2

            while (idx < totalRuns - 1) {
                val barRun = runs[idx]
                val spaceRun = runs[idx + 1]

                if (!barRun.first || spaceRun.first) break

                val barW = barRun.second.toFloat()
                val spaceW = spaceRun.second.toFloat()
                val totalW = barW + spaceW

                if (totalW <= 0) break

                val ratio = barW / totalW

                if (ratio >= 0.15f && ratio <= 0.48f && idx + 2 < totalRuns) {
                    val stopBar2 = runs[idx + 2]
                    if (stopBar2.first && stopBar2.second >= estX * 0.4f && stopBar2.second <= estX * 3.0f) {
                        val quietAfter = if (idx + 3 < totalRuns && !runs[idx + 3].first) runs[idx + 3].second else Int.MAX_VALUE
                        if (quietAfter >= estX * 3.0f) {
                            rawBits.add(0)
                            break
                        }
                    }
                }

                if (totalW < estX * 1.2f || totalW > estX * 5.0f) break

                val bit = if (ratio >= 0.50f) 1 else 0
                rawBits.add(bit)

                val currentX = totalW / 3.0f
                estX = (estX * 0.85f) + (currentX * 0.15f)

                idx += 2
            }

            val lastBit = rawBits.lastOrNull() ?: continue
            val candidateDataBits = if (lastBit == 0) {
                rawBits.subList(1, rawBits.size - 1)
            } else {
                rawBits.subList(1, rawBits.size)
            }

            if (candidateDataBits.size < 12 || candidateDataBits.size % 4 != 0) continue

            val lsbResult = parseBcdDigits(candidateDataBits, lsbFirst = true)
            if (lsbResult != null && validateChecksumByScheme(lsbResult, scheme)) {
                return lsbResult
            }

            val msbResult = parseBcdDigits(candidateDataBits, lsbFirst = false)
            if (msbResult != null && validateChecksumByScheme(msbResult, scheme)) {
                return msbResult
            }
        }

        return null
    }

    private fun parseBcdDigits(dataBits: List<Int>, lsbFirst: Boolean): String? {
        val digitsSb = StringBuilder()
        for (group in 0 until dataBits.size / 4) {
            val bit0 = dataBits[group * 4]
            val bit1 = dataBits[group * 4 + 1]
            val bit2 = dataBits[group * 4 + 2]
            val bit3 = dataBits[group * 4 + 3]

            val digit = if (lsbFirst) {
                bit0 or (bit1 shl 1) or (bit2 shl 2) or (bit3 shl 3)
            } else {
                (bit0 shl 3) or (bit1 shl 2) or (bit2 shl 1) or bit3
            }

            if (digit > 9) return null
            digitsSb.append(digit)
        }
        return digitsSb.toString()
    }

    private fun validateChecksumByScheme(digits: String, scheme: ChecksumScheme): Boolean {
        if (digits.length < 2) return false

        return when (scheme) {
            ChecksumScheme.AUTO -> validateMod10(digits)
            ChecksumScheme.MOD_10 -> validateMod10(digits)
            ChecksumScheme.MOD_11 -> validateMod11(digits)
            ChecksumScheme.MOD_10_10 -> validateDoubleMod10(digits)
            ChecksumScheme.MOD_11_10 -> validateMod1110(digits)
            ChecksumScheme.MOD_43 -> validateMod43(digits)
            ChecksumScheme.NONE -> digits.length >= 3
        }
    }

    fun validateMod10(digits: String): Boolean {
        if (digits.length < 2) return false
        val payload = digits.substring(0, digits.length - 1)
        val checksumDigit = digits.last().digitToIntOrNull() ?: return false

        var sum = 0
        var oddPosition = true
        for (i in payload.length - 1 downTo 0) {
            val d = payload[i].digitToIntOrNull() ?: return false
            if (oddPosition) {
                val doubled = d * 2
                sum += (doubled / 10) + (doubled % 10)
            } else {
                sum += d
            }
            oddPosition = !oddPosition
        }

        val expectedChecksum = (10 - (sum % 10)) % 10
        return checksumDigit == expectedChecksum
    }

    fun validateMod11(digits: String): Boolean {
        if (digits.length < 2) return false
        val payload = digits.substring(0, digits.length - 1)
        val checksumDigit = digits.last().digitToIntOrNull() ?: return false

        var sum = 0
        var weight = 2
        for (i in payload.length - 1 downTo 0) {
            val d = payload[i].digitToIntOrNull() ?: return false
            sum += d * weight
            weight++
            if (weight > 7) weight = 2
        }

        val remainder = sum % 11
        val expectedChecksum = (11 - remainder) % 11
        return expectedChecksum != 10 && checksumDigit == expectedChecksum
    }

    fun validateDoubleMod10(digits: String): Boolean {
        if (digits.length < 3) return false
        val firstPassPayload = digits.substring(0, digits.length - 1)
        if (!validateMod10(firstPassPayload)) return false
        return validateMod10(digits)
    }

    fun validateMod1110(digits: String): Boolean {
        if (digits.length < 3) return false
        val firstPassPayload = digits.substring(0, digits.length - 1)
        if (!validateMod11(firstPassPayload)) return false
        return validateMod10(digits)
    }

    fun validateMod43(text: String): Boolean {
        if (text.length < 2) return false
        val payload = text.substring(0, text.length - 1)
        val checkChar = text.last()

        var sum = 0
        for (ch in payload) {
            val valIdx = ALPHANUMERIC_CHARS.indexOf(ch)
            if (valIdx < 0) return false
            sum += valIdx
        }
        val expectedIdx = sum % 43
        return ALPHANUMERIC_CHARS[expectedIdx] == checkChar
    }
}
