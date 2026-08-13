import CoreGraphics
import Flutter
import Foundation
import UIKit

enum MsiChecksumScheme: String {
  case auto = "AUTO"
  case mod10 = "MOD_10"
  case mod11 = "MOD_11"
  case mod1010 = "MOD_10_10"
  case mod1110 = "MOD_11_10"
  case mod43 = "MOD_43"
  case none = "NONE"
}

final class MsiNativeDecoder {
  private static let alphanumericChars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-. $/+%")
  private static let scanRatios: [CGFloat] = [
    0.50, 0.40, 0.60, 0.30, 0.70, 0.25, 0.75,
    0.45, 0.55, 0.35, 0.65, 0.20, 0.80,
  ]

  static func decodeImageData(
    _ data: FlutterStandardTypedData,
    scheme: MsiChecksumScheme = .auto
  ) -> String? {
    guard let image = UIImage(data: data.data) else { return nil }
    return decodeImage(image, scheme: scheme)
  }

  static func decodeImage(_ image: UIImage, scheme: MsiChecksumScheme = .auto) -> String? {
    guard let cgImage = image.cgImage else { return nil }

    let width = cgImage.width
    let height = cgImage.height
    guard width > 0, height > 0 else { return nil }

    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else {
      return nil
    }

    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

    for ratio in scanRatios {
      let y = clamp(Int(CGFloat(height) * ratio), min: 0, max: height - 1)
      var luminanceRow = [Int](repeating: 0, count: width)

      for x in 0..<width {
        let offset = y * bytesPerRow + x * bytesPerPixel
        let r = Int(pixels[offset])
        let g = Int(pixels[offset + 1])
        let b = Int(pixels[offset + 2])
        luminanceRow[x] = (r * 38 + g * 75 + b * 15) >> 7
      }

      if let result = decodeLuminanceRow(luminanceRow, scheme: scheme) {
        return result
      }
    }

    for ratio in scanRatios {
      let x = clamp(Int(CGFloat(width) * ratio), min: 0, max: width - 1)
      var luminanceColumn = [Int](repeating: 0, count: height)

      for y in 0..<height {
        let offset = y * bytesPerRow + x * bytesPerPixel
        let r = Int(pixels[offset])
        let g = Int(pixels[offset + 1])
        let b = Int(pixels[offset + 2])
        luminanceColumn[y] = (r * 38 + g * 75 + b * 15) >> 7
      }

      if let result = decodeLuminanceRow(luminanceColumn, scheme: scheme) {
        return result
      }
    }

    return nil
  }

  static func decodeYuvLuminance(
    _ data: FlutterStandardTypedData,
    width: Int,
    height: Int,
    rowStride: Int,
    scheme: MsiChecksumScheme = .auto
  ) -> String? {
    let bytes = [UInt8](data.data)
    guard width > 0, height > 0, rowStride > 0, !bytes.isEmpty else { return nil }

    for ratio in scanRatios {
      let y = clamp(Int(CGFloat(height) * ratio), min: 0, max: height - 1)
      var luminanceRow = [Int](repeating: 0, count: width)
      let rowOffset = y * rowStride

      for x in 0..<width {
        let offset = rowOffset + x
        if offset < bytes.count {
          luminanceRow[x] = Int(bytes[offset])
        }
      }

      if let result = decodeLuminanceRow(luminanceRow, scheme: scheme) {
        return result
      }
    }

    for ratio in scanRatios {
      let x = clamp(Int(CGFloat(width) * ratio), min: 0, max: width - 1)
      var luminanceColumn = [Int](repeating: 0, count: height)

      for y in 0..<height {
        let offset = y * rowStride + x
        if offset < bytes.count {
          luminanceColumn[y] = Int(bytes[offset])
        }
      }

      if let result = decodeLuminanceRow(luminanceColumn, scheme: scheme) {
        return result
      }
    }

    return nil
  }

  private static func decodeLuminanceRow(
    _ luminance: [Int],
    scheme: MsiChecksumScheme
  ) -> String? {
    let width = luminance.count
    guard width >= 30 else { return nil }

    var isBarArray = [Bool](repeating: false, count: width)
    let windowSize = Swift.max(8, width / 15)
    var windowSum = 0

    for i in 0..<Swift.min(windowSize, width) {
      windowSum += luminance[i]
    }

    for x in 0..<width {
      let left = Swift.max(0, x - windowSize / 2)
      let right = Swift.min(width - 1, x + windowSize / 2)
      let count = right - left + 1

      if x > windowSize / 2 && x + windowSize / 2 < width {
        windowSum += luminance[right] - luminance[left - 1]
      } else {
        var sum = 0
        for j in left...right {
          sum += luminance[j]
        }
        windowSum = sum
      }

      let localAvg = windowSum / count
      isBarArray[x] = luminance[x] < localAvg
    }

    var runs: [(isBar: Bool, width: Int)] = []
    var currentIsBar = isBarArray[0]
    var currentLength = 0

    for x in 0..<width {
      if isBarArray[x] == currentIsBar {
        currentLength += 1
      } else {
        if currentLength > 0 {
          runs.append((currentIsBar, currentLength))
        }
        currentIsBar = isBarArray[x]
        currentLength = 1
      }
    }

    if currentLength > 0 {
      runs.append((currentIsBar, currentLength))
    }

    guard runs.count >= 10 else { return nil }

    if let result = parseRuns(runs, scheme: scheme) {
      return result
    }

    return parseRuns(runs.reversed(), scheme: scheme)
  }

  private static func parseRuns(
    _ runs: any Collection<(isBar: Bool, width: Int)>,
    scheme: MsiChecksumScheme
  ) -> String? {
    let runArray = Array(runs)
    let totalRuns = runArray.count
    guard totalRuns >= 10 else { return nil }

    for startIndex in 0..<Swift.max(0, totalRuns - 8) {
      if !runArray[startIndex].isBar { continue }

      let startBar = Float(runArray[startIndex].width)
      let startSpace = Float(runArray[startIndex + 1].width)
      let startTotal = startBar + startSpace
      if startTotal <= 0 { continue }

      let startRatio = startBar / startTotal
      if startRatio < 0.50 || startRatio > 0.85 { continue }

      var estimatedX = startTotal / 3.0
      if estimatedX <= 0 { continue }

      if startIndex > 0 {
        let quietBefore = runArray[startIndex - 1]
        if !quietBefore.isBar && Float(quietBefore.width) < estimatedX * 3.0 {
          continue
        }
      }

      var rawBits = [1]
      var index = startIndex + 2

      while index < totalRuns - 1 {
        let barRun = runArray[index]
        let spaceRun = runArray[index + 1]
        if !barRun.isBar || spaceRun.isBar { break }

        let barWidth = Float(barRun.width)
        let spaceWidth = Float(spaceRun.width)
        let totalWidth = barWidth + spaceWidth
        if totalWidth <= 0 { break }

        let ratio = barWidth / totalWidth

        if ratio >= 0.15 && ratio <= 0.48 && index + 2 < totalRuns {
          let stopBar2 = runArray[index + 2]
          if stopBar2.isBar &&
            Float(stopBar2.width) >= estimatedX * 0.4 &&
            Float(stopBar2.width) <= estimatedX * 3.0
          {
            let quietAfter: Int
            if index + 3 < totalRuns && !runArray[index + 3].isBar {
              quietAfter = runArray[index + 3].width
            } else {
              quietAfter = Int.max
            }

            if Float(quietAfter) >= estimatedX * 3.0 {
              rawBits.append(0)
              break
            }
          }
        }

        if totalWidth < estimatedX * 1.2 || totalWidth > estimatedX * 5.0 {
          break
        }

        rawBits.append(ratio >= 0.50 ? 1 : 0)
        let currentX = totalWidth / 3.0
        estimatedX = (estimatedX * 0.85) + (currentX * 0.15)
        index += 2
      }

      guard let lastBit = rawBits.last else { continue }
      let candidateDataBits: ArraySlice<Int>
      if lastBit == 0 {
        candidateDataBits = rawBits.dropFirst().dropLast()
      } else {
        candidateDataBits = rawBits.dropFirst()
      }

      if candidateDataBits.count < 12 || candidateDataBits.count % 4 != 0 {
        continue
      }

      if let lsbResult = parseBcdDigits(Array(candidateDataBits), lsbFirst: true),
        validateChecksum(lsbResult, scheme: scheme)
      {
        return lsbResult
      }

      if let msbResult = parseBcdDigits(Array(candidateDataBits), lsbFirst: false),
        validateChecksum(msbResult, scheme: scheme)
      {
        return msbResult
      }
    }

    return nil
  }

  private static func parseBcdDigits(_ dataBits: [Int], lsbFirst: Bool) -> String? {
    var digits = ""

    for group in 0..<(dataBits.count / 4) {
      let bit0 = dataBits[group * 4]
      let bit1 = dataBits[group * 4 + 1]
      let bit2 = dataBits[group * 4 + 2]
      let bit3 = dataBits[group * 4 + 3]

      let digit: Int
      if lsbFirst {
        digit = bit0 | (bit1 << 1) | (bit2 << 2) | (bit3 << 3)
      } else {
        digit = (bit0 << 3) | (bit1 << 2) | (bit2 << 1) | bit3
      }

      if digit > 9 { return nil }
      digits.append(String(digit))
    }

    return digits
  }

  private static func validateChecksum(_ digits: String, scheme: MsiChecksumScheme) -> Bool {
    if digits.count < 2 { return false }

    switch scheme {
    case .auto, .mod10:
      return validateMod10(digits)
    case .mod11:
      return validateMod11(digits)
    case .mod1010:
      return validateDoubleMod10(digits)
    case .mod1110:
      return validateMod1110(digits)
    case .mod43:
      return validateMod43(digits)
    case .none:
      return digits.count >= 3
    }
  }

  private static func validateMod10(_ digits: String) -> Bool {
    if digits.count < 2 { return false }

    let payload = String(digits.dropLast())
    guard let checksumDigit = digits.last?.wholeNumberValue else { return false }

    var sum = 0
    var oddPosition = true
    for character in payload.reversed() {
      guard let digit = character.wholeNumberValue else { return false }
      if oddPosition {
        let doubled = digit * 2
        sum += (doubled / 10) + (doubled % 10)
      } else {
        sum += digit
      }
      oddPosition.toggle()
    }

    let expectedChecksum = (10 - (sum % 10)) % 10
    return checksumDigit == expectedChecksum
  }

  private static func validateMod11(_ digits: String) -> Bool {
    if digits.count < 2 { return false }

    let payload = String(digits.dropLast())
    guard let checksumDigit = digits.last?.wholeNumberValue else { return false }

    var sum = 0
    var weight = 2
    for character in payload.reversed() {
      guard let digit = character.wholeNumberValue else { return false }
      sum += digit * weight
      weight += 1
      if weight > 7 { weight = 2 }
    }

    let remainder = sum % 11
    let expectedChecksum = (11 - remainder) % 11
    return expectedChecksum != 10 && checksumDigit == expectedChecksum
  }

  private static func validateDoubleMod10(_ digits: String) -> Bool {
    if digits.count < 3 { return false }
    return validateMod10(String(digits.dropLast())) && validateMod10(digits)
  }

  private static func validateMod1110(_ digits: String) -> Bool {
    if digits.count < 3 { return false }
    return validateMod11(String(digits.dropLast())) && validateMod10(digits)
  }

  private static func validateMod43(_ text: String) -> Bool {
    if text.count < 2 { return false }

    let payload = text.dropLast()
    guard let checkChar = text.last else { return false }

    var sum = 0
    for character in payload {
      guard let index = alphanumericChars.firstIndex(of: character) else {
        return false
      }
      sum += index
    }

    return alphanumericChars[sum % 43] == checkChar
  }

  private static func clamp(_ value: Int, min minValue: Int, max maxValue: Int) -> Int {
    return Swift.max(minValue, Swift.min(maxValue, value))
  }
}
