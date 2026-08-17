import CoreGraphics
import Flutter
import Foundation
import UIKit
import Vision

final class Gs1CompositeNativeDecoder {
  private static let formatCode128 = 1 << 4
  private static let formatDataBar = 1 << 5
  private static let formatDataBarExpanded = 1 << 6
  private static let formatEAN8 = 1 << 8
  private static let formatEAN13 = 1 << 9
  private static let formatPDF417 = 1 << 12
  private static let formatUPCE = 1 << 15
  private static let formatDataBarLimited = 1 << 19

  static func decodeCameraBytes(
    _ data: FlutterStandardTypedData,
    width: Int,
    height: Int,
    rowStride: Int,
    imageFormatGroup: String?
  ) -> [String: Any?] {
    let startedAt = DispatchTime.now().uptimeNanoseconds
    guard let cgImage = makeCameraCGImage(
      data: data.data,
      width: width,
      height: height,
      rowStride: rowStride,
      imageFormatGroup: imageFormatGroup
    ) else {
      return emptyResult(
        source: "camera",
        durationMs: elapsedMs(since: startedAt),
        warning: "Could not create CGImage from camera frame"
      )
    }

    return detect(in: cgImage, source: "camera", startedAt: startedAt)
  }

  static func decodeBitmapBytes(_ data: FlutterStandardTypedData) -> [String: Any?] {
    let startedAt = DispatchTime.now().uptimeNanoseconds
    guard let image = UIImage(data: data.data), let cgImage = image.cgImage else {
      return emptyResult(
        source: "bitmap",
        durationMs: elapsedMs(since: startedAt),
        warning: "UIImage could not decode image bytes"
      )
    }

    return detect(in: cgImage, source: "bitmap", startedAt: startedAt)
  }

  private static func detect(
    in cgImage: CGImage,
    source: String,
    startedAt: UInt64
  ) -> [String: Any?] {
    let request = VNDetectBarcodesRequest()
    configure(request: request)

    let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
    do {
      try handler.perform([request])
    } catch {
      return emptyResult(
        source: source,
        durationMs: elapsedMs(since: startedAt),
        warning: "Vision barcode request failed: \(error.localizedDescription)"
      )
    }

    let observations = request.results ?? []
    if let composite = coalescedComposite(
      from: observations,
      imageWidth: cgImage.width,
      imageHeight: cgImage.height
    ) {
      return composite.toMap(
        source: source,
        durationMs: elapsedMs(since: startedAt),
        rawCodes: observations.map {
          codeCandidate(from: $0, imageWidth: cgImage.width, imageHeight: cgImage.height).toMap()
        }
      )
    }

    if let paired = pairedComposite(
      from: observations,
      imageWidth: cgImage.width,
      imageHeight: cgImage.height
    ) {
      return paired.toMap(
        source: source,
        durationMs: elapsedMs(since: startedAt),
        rawCodes: observations.map {
          codeCandidate(from: $0, imageWidth: cgImage.width, imageHeight: cgImage.height).toMap()
        }
      )
    }

    return emptyResult(
      source: source,
      durationMs: elapsedMs(since: startedAt),
      warning: "No GS1 Composite result found from \(observations.count) Vision observation(s)",
      codes: observations.map {
        codeCandidate(from: $0, imageWidth: cgImage.width, imageHeight: cgImage.height).toMap()
      }
    )
  }

  private static func configure(request: VNDetectBarcodesRequest) {
    let wanted = [
      "Code128",
      "EAN8",
      "EAN13",
      "UPCE",
      "GS1DataBar",
      "PDF417",
      "MicroPDF417",
    ]
    request.symbologies = VNDetectBarcodesRequest.supportedSymbologies.filter { symbology in
      wanted.contains { symbology.rawValue.localizedCaseInsensitiveContains($0) }
    }

    if #available(iOS 17.0, *) {
      request.coalesceCompositeSymbologies = true
    }
  }

  private static func coalescedComposite(
    from observations: [VNBarcodeObservation],
    imageWidth: Int,
    imageHeight: Int
  ) -> CompositeAssembly? {
    for observation in observations {
      if #available(iOS 17.0, *),
        observation.supplementalCompositeType != .none,
        let linearText = observation.payloadStringValue,
        let componentText = observation.supplementalPayloadString,
        !linearText.isEmpty,
        !componentText.isEmpty
      {
        let linear = codeCandidate(
          from: observation,
          imageWidth: imageWidth,
          imageHeight: imageHeight,
          overrideText: linearText
        )
        let component = codeCandidate(
          from: observation,
          imageWidth: imageWidth,
          imageHeight: imageHeight,
          overrideText: componentText,
          overrideFormat: formatPDF417,
          overrideFormatName: "Supplemental PDF417/MicroPDF417"
        )

        return makeAssembly(
          linear: linear,
          component: component,
          confidence: Double(observation.confidence),
          typeEstimate: compositeTypeName(observation.supplementalCompositeType),
          warnings: [
            "Apple Vision coalesced this GS1 Composite symbol and returned supplemental payload data.",
          ]
        )
      }
    }

    return nil
  }

  private static func pairedComposite(
    from observations: [VNBarcodeObservation],
    imageWidth: Int,
    imageHeight: Int
  ) -> CompositeAssembly? {
    let candidates = observations.map {
      codeCandidate(from: $0, imageWidth: imageWidth, imageHeight: imageHeight)
    }
    let linearCodes = candidates.filter(\.isLinear)
    let components = candidates.filter(\.isCompositeComponent)

    var best: PairCandidate?
    for linear in linearCodes {
      for component in components {
        guard let candidate = scorePair(linear: linear, component: component) else { continue }
        if best == nil || candidate.score > best!.score {
          best = candidate
        }
      }
    }

    guard let best = best else { return nil }

    return makeAssembly(
      linear: best.linear,
      component: best.component,
      confidence: best.score,
      typeEstimate: best.linear.format == formatCode128 ? "CC-C candidate" : "CC-A/CC-B candidate",
      warnings: [
        "Vision did not return a coalesced composite result; this result was paired by geometry.",
      ]
    )
  }

  private static func makeAssembly(
    linear: CodeCandidate,
    component: CodeCandidate,
    confidence: Double,
    typeEstimate: String,
    warnings: [String]
  ) -> CompositeAssembly {
    var warnings = warnings
    let linearElements = Gs1VisionElementParser.parse(linear.text, fallbackFormat: linear.format)
    let componentElements = Gs1VisionElementParser.parse(component.text, fallbackFormat: component.format)
    if linearElements.isEmpty {
      warnings.append("Linear payload could not be parsed as GS1 element strings.")
    }
    if componentElements.isEmpty {
      warnings.append("2D component payload could not be parsed as GS1 element strings.")
    }

    return CompositeAssembly(
      linear: linear,
      component: component,
      confidence: confidence,
      typeEstimate: typeEstimate,
      elements: linearElements + componentElements,
      warnings: warnings
    )
  }

  private static func scorePair(linear: CodeCandidate, component: CodeCandidate) -> PairCandidate? {
    let overlap = max(0, min(linear.right, component.right) - max(linear.left, component.left))
    let overlapRatio = Double(overlap) / Double(max(1, min(linear.width, component.width)))
    let componentAbove = component.centerY < linear.centerY && component.bottom <= linear.bottom
    let gap = linear.top - component.bottom
    let maxReasonableGap = max(Double(linear.height) * 1.8, Double(component.height) * 1.2)
    let closeEnough = Double(gap) <= maxReasonableGap && Double(gap) >= -Double(component.height) * 0.6

    guard overlapRatio >= 0.35, componentAbove, closeEnough else { return nil }

    let gapScore = 1 - min(1, abs(Double(gap)) / maxReasonableGap)
    let score = overlapRatio * 0.55 + gapScore * 0.25 + 0.20
    return PairCandidate(linear: linear, component: component, score: score)
  }

  private static func codeCandidate(
    from observation: VNBarcodeObservation,
    imageWidth: Int,
    imageHeight: Int,
    overrideText: String? = nil,
    overrideFormat: Int? = nil,
    overrideFormatName: String? = nil
  ) -> CodeCandidate {
    let rect = pixelRect(from: observation.boundingBox, imageWidth: imageWidth, imageHeight: imageHeight)
    let format = overrideFormat ?? formatValue(for: observation.symbology)
    let formatName = overrideFormatName ?? formatName(for: observation.symbology, fallbackFormat: format)

    return CodeCandidate(
      text: overrideText ?? observation.payloadStringValue ?? "",
      format: format,
      formatName: formatName,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      topLeftX: rect.minX,
      topLeftY: rect.minY,
      topRightX: rect.maxX,
      topRightY: rect.minY,
      bottomLeftX: rect.minX,
      bottomLeftY: rect.maxY,
      bottomRightX: rect.maxX,
      bottomRightY: rect.maxY,
      pass: "vision"
    )
  }

  private static func pixelRect(
    from normalizedRect: CGRect,
    imageWidth: Int,
    imageHeight: Int
  ) -> PixelRect {
    let minX = Int((normalizedRect.minX * CGFloat(imageWidth)).rounded())
    let maxX = Int((normalizedRect.maxX * CGFloat(imageWidth)).rounded())
    let minY = Int(((1 - normalizedRect.maxY) * CGFloat(imageHeight)).rounded())
    let maxY = Int(((1 - normalizedRect.minY) * CGFloat(imageHeight)).rounded())
    return PixelRect(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
  }

  private static func formatValue(for symbology: VNBarcodeSymbology) -> Int {
    let rawValue = symbology.rawValue
    if rawValue.localizedCaseInsensitiveContains("Code128") { return formatCode128 }
    if rawValue.localizedCaseInsensitiveContains("GS1DataBarExpanded") { return formatDataBarExpanded }
    if rawValue.localizedCaseInsensitiveContains("GS1DataBarLimited") { return formatDataBarLimited }
    if rawValue.localizedCaseInsensitiveContains("GS1DataBar") { return formatDataBar }
    if rawValue.localizedCaseInsensitiveContains("EAN8") { return formatEAN8 }
    if rawValue.localizedCaseInsensitiveContains("EAN13") { return formatEAN13 }
    if rawValue.localizedCaseInsensitiveContains("PDF417") { return formatPDF417 }
    if rawValue.localizedCaseInsensitiveContains("UPCE") { return formatUPCE }
    return 0
  }

  private static func formatName(
    for symbology: VNBarcodeSymbology,
    fallbackFormat: Int
  ) -> String {
    switch fallbackFormat {
    case formatCode128: return "Code128"
    case formatDataBar: return "DataBar"
    case formatDataBarExpanded: return "DataBarExpanded"
    case formatDataBarLimited: return "DataBarLimited"
    case formatEAN8: return "EAN8"
    case formatEAN13: return "EAN13"
    case formatPDF417: return symbology.rawValue.localizedCaseInsensitiveContains("Micro")
      ? "MicroPDF417"
      : "PDF417"
    case formatUPCE: return "UPCE"
    default: return symbology.rawValue
    }
  }

  @available(iOS 17.0, *)
  private static func compositeTypeName(_ type: VNBarcodeCompositeType) -> String {
    switch type {
    case .gs1TypeA: return "CC-A"
    case .gs1TypeB: return "CC-B"
    case .gs1TypeC: return "CC-C"
    case .linked: return "Linked composite"
    case .none: return "No composite"
    @unknown default: return "Composite"
    }
  }

  private static func makeCameraCGImage(
    data: Data,
    width: Int,
    height: Int,
    rowStride: Int,
    imageFormatGroup: String?
  ) -> CGImage? {
    guard width > 0, height > 0, rowStride > 0, !data.isEmpty else { return nil }

    if imageFormatGroup == "bgra8888" {
      guard data.count >= rowStride * height else { return nil }
      guard let provider = CGDataProvider(data: data as CFData),
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
      else { return nil }

      let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(
        CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
      )
      return CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: rowStride,
        space: colorSpace,
        bitmapInfo: bitmapInfo,
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
      )
    }

    var luminance = [UInt8](repeating: 0, count: width * height)
    data.withUnsafeBytes { rawBuffer in
      guard let source = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
      for y in 0..<height {
        let sourceOffset = y * rowStride
        let destinationOffset = y * width
        if sourceOffset + width <= data.count {
          luminance.withUnsafeMutableBytes { destinationBuffer in
            let destination = destinationBuffer.bindMemory(to: UInt8.self).baseAddress!
            destination.advanced(by: destinationOffset)
              .update(from: source.advanced(by: sourceOffset), count: width)
          }
        }
      }
    }

    let grayData = Data(luminance)
    guard let provider = CGDataProvider(data: grayData as CFData) else { return nil }
    return CGImage(
      width: width,
      height: height,
      bitsPerComponent: 8,
      bitsPerPixel: 8,
      bytesPerRow: width,
      space: CGColorSpaceCreateDeviceGray(),
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
      provider: provider,
      decode: nil,
      shouldInterpolate: false,
      intent: .defaultIntent
    )
  }

  private static func emptyResult(
    source: String,
    durationMs: Int,
    warning: String,
    codes: [[String: Any?]] = []
  ) -> [String: Any?] {
    [
      "hasResult": false,
      "source": source,
      "durationMs": durationMs,
      "warning": warning,
      "codes": codes,
    ]
  }

  private static func elapsedMs(since startedAt: UInt64) -> Int {
    Int((DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000)
  }
}

private struct PixelRect {
  let minX: Int
  let minY: Int
  let maxX: Int
  let maxY: Int
}

private struct PairCandidate {
  let linear: CodeCandidate
  let component: CodeCandidate
  let score: Double
}

private struct CompositeAssembly {
  let linear: CodeCandidate
  let component: CodeCandidate
  let confidence: Double
  let typeEstimate: String
  let elements: [Gs1VisionElement]
  let warnings: [String]

  func toMap(
    source: String,
    durationMs: Int,
    rawCodes: [[String: Any?]]
  ) -> [String: Any?] {
    [
      "hasResult": true,
      "source": source,
      "durationMs": durationMs,
      "nativeDurationMs": durationMs,
      "formatName": "GS1 Composite Native POC",
      "typeEstimate": typeEstimate,
      "confidence": confidence,
      "linear": linear.toMap(),
      "component": component.toMap(),
      "elements": elements.map { $0.toMap() },
      "warnings": warnings,
      "codes": rawCodes,
      "text": displayText(),
    ]
  }

  private func displayText() -> String {
    var lines = [
      "Confidence: \(Int(confidence * 100))%",
      "Linear: \(linear.formatName)",
      linear.text.visibleSeparators(),
      "",
      "2D component: \(component.formatName)",
      component.text.visibleSeparators(),
    ]

    if !elements.isEmpty {
      lines += ["", "Parsed GS1 fields:"]
      lines += elements.map {
        "(\($0.ai)) \($0.title): \($0.value.visibleSeparators())"
      }
    }

    if !warnings.isEmpty {
      lines += ["", "Native POC warnings:"]
      lines += warnings.map { "- \($0)" }
    }

    return lines.joined(separator: "\n")
  }
}

private struct CodeCandidate {
  let text: String
  let format: Int
  let formatName: String
  let imageWidth: Int
  let imageHeight: Int
  let topLeftX: Int
  let topLeftY: Int
  let topRightX: Int
  let topRightY: Int
  let bottomLeftX: Int
  let bottomLeftY: Int
  let bottomRightX: Int
  let bottomRightY: Int
  let pass: String

  var left: Int { min(min(topLeftX, topRightX), min(bottomLeftX, bottomRightX)) }
  var right: Int { max(max(topLeftX, topRightX), max(bottomLeftX, bottomRightX)) }
  var top: Int { min(min(topLeftY, topRightY), min(bottomLeftY, bottomRightY)) }
  var bottom: Int { max(max(topLeftY, topRightY), max(bottomLeftY, bottomRightY)) }
  var width: Int { right - left }
  var height: Int { bottom - top }
  var centerY: Double { Double(top + bottom) / 2.0 }

  var isLinear: Bool {
    format == (1 << 4) ||
      format == (1 << 5) ||
      format == (1 << 6) ||
      format == (1 << 8) ||
      format == (1 << 9) ||
      format == (1 << 15) ||
      format == (1 << 19)
  }

  var isCompositeComponent: Bool {
    format == (1 << 12)
  }

  func toMap() -> [String: Any?] {
    [
      "text": text,
      "format": format,
      "formatName": formatName,
      "imageWidth": imageWidth,
      "imageHeight": imageHeight,
      "topLeftX": topLeftX,
      "topLeftY": topLeftY,
      "topRightX": topRightX,
      "topRightY": topRightY,
      "bottomLeftX": bottomLeftX,
      "bottomLeftY": bottomLeftY,
      "bottomRightX": bottomRightX,
      "bottomRightY": bottomRightY,
      "isInverted": false,
      "isMirrored": false,
      "pass": pass,
    ]
  }
}

private struct Gs1VisionElement {
  let ai: String
  let value: String
  let title: String

  func toMap() -> [String: String] {
    ["ai": ai, "value": value, "title": title]
  }
}

private enum Gs1VisionElementParser {
  static func parse(_ raw: String, fallbackFormat: Int) -> [Gs1VisionElement] {
    let normalized = normalize(raw, fallbackFormat: fallbackFormat)
    if normalized.isEmpty { return [] }
    if normalized.contains("(") { return parseBracketed(normalized) }
    return parseRaw(normalized)
  }

  private static func normalize(_ raw: String, fallbackFormat: Int) -> String {
    var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.count >= 3,
      value.first == "]",
      let thirdIndex = value.index(value.startIndex, offsetBy: 3, limitedBy: value.endIndex)
    {
      value = String(value[thirdIndex...])
    }

    if value.allSatisfy(\.isNumber) {
      if fallbackFormat == (1 << 9), value.count == 13 {
        return "01" + value.leftPadded(to: 14, with: "0")
      }
      if value.count == 12 {
        return "01" + value.leftPadded(to: 14, with: "0")
      }
      if fallbackFormat == (1 << 8), value.count == 8 {
        return "01" + value.leftPadded(to: 14, with: "0")
      }
    }

    return value
  }

  private static func parseBracketed(_ input: String) -> [Gs1VisionElement] {
    let pattern = #"\((\d{2,4})\)([^\(]*)"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let range = NSRange(input.startIndex..<input.endIndex, in: input)

    return regex.matches(in: input, range: range).compactMap { match in
      guard let aiRange = Range(match.range(at: 1), in: input),
        let valueRange = Range(match.range(at: 2), in: input)
      else { return nil }

      let ai = String(input[aiRange])
      let value = String(input[valueRange])
        .replacingOccurrences(of: "\u{001D}", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      return Gs1VisionElement(ai: ai, value: value, title: title(for: ai))
    }
  }

  private static func parseRaw(_ input: String) -> [Gs1VisionElement] {
    var elements: [Gs1VisionElement] = []
    var index = input.startIndex

    while index < input.endIndex {
      if input[index].unicodeScalars.first?.value == 29 {
        index = input.index(after: index)
        continue
      }

      guard let definition = matchAi(input, at: index) else { break }
      index = input.index(index, offsetBy: definition.ai.count)
      if index >= input.endIndex { break }

      let value: String
      if let fixedLength = definition.fixedLength {
        let end = input.index(index, offsetBy: fixedLength, limitedBy: input.endIndex) ?? input.endIndex
        value = String(input[index..<end])
        index = end
      } else {
        let maxEnd = input.index(index, offsetBy: definition.maxLength, limitedBy: input.endIndex)
          ?? input.endIndex
        let separator = input[index..<maxEnd].firstIndex(of: "\u{001D}") ?? maxEnd
        value = String(input[index..<separator])
        index = separator
      }

      elements.append(
        Gs1VisionElement(ai: definition.ai, value: value, title: definition.title)
      )
    }

    return elements
  }

  private static func matchAi(_ input: String, at index: String.Index) -> AiDefinition? {
    for definition in fixedDefinitions where input[index...].hasPrefix(definition.ai) {
      return definition
    }
    for definition in variableDefinitions where input[index...].hasPrefix(definition.ai) {
      return definition
    }

    if let ai4End = input.index(index, offsetBy: 4, limitedBy: input.endIndex) {
      let ai4 = String(input[index..<ai4End])
      let prefix = Int(ai4.prefix(3))
      if let prefix = prefix, (310...369).contains(prefix) {
        return AiDefinition.fixed(ai4, length: 6, title: "Measurement")
      }
      if ai4.range(of: #"^39[23]\d$"#, options: .regularExpression) != nil {
        return AiDefinition.variable(ai4, maxLength: 18, title: "Amount payable")
      }
    }

    if let ai2End = input.index(index, offsetBy: 2, limitedBy: input.endIndex) {
      let ai2 = String(input[index..<ai2End])
      if ai2.hasPrefix("9") {
        return AiDefinition.variable(ai2, maxLength: 90, title: "Company internal")
      }
    }

    return nil
  }

  private static func title(for ai: String) -> String {
    if let definition = (fixedDefinitions + variableDefinitions).first(where: { $0.ai == ai }) {
      return definition.title
    }
    if ai.range(of: #"^3[1-6]\d\d$"#, options: .regularExpression) != nil {
      return "Measurement"
    }
    if ai.range(of: #"^39[23]\d$"#, options: .regularExpression) != nil {
      return "Amount payable"
    }
    if ai.hasPrefix("9") { return "Company internal" }
    return "AI \(ai)"
  }

  private static let fixedDefinitions: [AiDefinition] = [
    .fixed("8017", length: 18, title: "GSRN provider"),
    .fixed("8018", length: 18, title: "GSRN recipient"),
    .fixed("8005", length: 6, title: "Price per unit of measure"),
    .fixed("8006", length: 18, title: "ITIP"),
    .fixed("8026", length: 18, title: "ITIP contained"),
    .fixed("415", length: 13, title: "Pay to GLN"),
    .fixed("414", length: 13, title: "Physical location GLN"),
    .fixed("422", length: 3, title: "Country of origin"),
    .fixed("424", length: 3, title: "Country of processing"),
    .fixed("425", length: 3, title: "Country of disassembly"),
    .fixed("426", length: 3, title: "Country covering full process"),
    .fixed("00", length: 18, title: "SSCC"),
    .fixed("01", length: 14, title: "GTIN"),
    .fixed("02", length: 14, title: "Content GTIN"),
    .fixed("11", length: 6, title: "Production date"),
    .fixed("12", length: 6, title: "Due date"),
    .fixed("13", length: 6, title: "Packaging date"),
    .fixed("15", length: 6, title: "Best before date"),
    .fixed("16", length: 6, title: "Sell by date"),
    .fixed("17", length: 6, title: "Expiration date"),
    .fixed("20", length: 2, title: "Product variant"),
  ]

  private static let variableDefinitions: [AiDefinition] = [
    .variable("8110", maxLength: 70, title: "Coupon code"),
    .variable("8112", maxLength: 70, title: "Paperless coupon code"),
    .variable("8004", maxLength: 30, title: "GIAI"),
    .variable("8008", maxLength: 12, title: "Production date/time"),
    .variable("8010", maxLength: 30, title: "CPID"),
    .variable("8011", maxLength: 12, title: "CPID serial"),
    .variable("8012", maxLength: 20, title: "Software version"),
    .variable("8200", maxLength: 70, title: "Extended packaging URL"),
    .variable("240", maxLength: 30, title: "Additional product identification"),
    .variable("241", maxLength: 30, title: "Customer part number"),
    .variable("242", maxLength: 6, title: "Made-to-order variation"),
    .variable("243", maxLength: 20, title: "Packaging component number"),
    .variable("250", maxLength: 30, title: "Secondary serial number"),
    .variable("251", maxLength: 30, title: "Reference to source entity"),
    .variable("253", maxLength: 30, title: "GDTI"),
    .variable("254", maxLength: 20, title: "GLN extension component"),
    .variable("255", maxLength: 25, title: "GCN"),
    .variable("400", maxLength: 30, title: "Customer purchase order number"),
    .variable("401", maxLength: 30, title: "GINC"),
    .variable("403", maxLength: 30, title: "Routing code"),
    .variable("420", maxLength: 20, title: "Ship to postal code"),
    .variable("421", maxLength: 15, title: "Ship to postal code with country"),
    .variable("10", maxLength: 20, title: "Batch or lot number"),
    .variable("21", maxLength: 20, title: "Serial number"),
    .variable("22", maxLength: 20, title: "Consumer product variant"),
    .variable("30", maxLength: 8, title: "Variable count"),
    .variable("37", maxLength: 8, title: "Count of trade items"),
  ]

  private struct AiDefinition {
    let ai: String
    let fixedLength: Int?
    let maxLength: Int
    let title: String

    static func fixed(_ ai: String, length: Int, title: String) -> AiDefinition {
      AiDefinition(ai: ai, fixedLength: length, maxLength: length, title: title)
    }

    static func variable(_ ai: String, maxLength: Int, title: String) -> AiDefinition {
      AiDefinition(ai: ai, fixedLength: nil, maxLength: maxLength, title: title)
    }
  }
}

private extension String {
  func visibleSeparators() -> String {
    replacingOccurrences(of: "\u{001D}", with: "<GS>")
  }

  func leftPadded(to length: Int, with character: Character) -> String {
    if count >= length { return self }
    return String(repeating: String(character), count: length - count) + self
  }
}
