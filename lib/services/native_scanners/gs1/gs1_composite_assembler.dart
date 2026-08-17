import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:poc_multi_scan/services/native_scanners/gs1/gs1_detected_code.dart';

enum Gs1CompositeTypeEstimate {
  ccaOrCcb('CC-A/CC-B candidate'),
  ccc('CC-C candidate'),
  unknown('Composite candidate');

  const Gs1CompositeTypeEstimate(this.label);

  final String label;
}

class Gs1CompositeAssembly {
  const Gs1CompositeAssembly({
    required this.linearCode,
    required this.compositeCode,
    required this.typeEstimate,
    required this.confidence,
    required this.linearElements,
    required this.compositeElements,
    required this.warnings,
  });

  final Gs1DetectedCode linearCode;
  final Gs1DetectedCode compositeCode;
  final Gs1CompositeTypeEstimate typeEstimate;
  final double confidence;
  final List<Gs1Element> linearElements;
  final List<Gs1Element> compositeElements;
  final List<String> warnings;

  List<Gs1Element> get elements => <Gs1Element>[
    ...linearElements,
    ...compositeElements,
  ];

  String get resultText {
    if (compositeElements.isEmpty &&
        (compositeCode.text?.isNotEmpty ?? false)) {
      return toDisplayText();
    }

    final String formatted = Gs1ElementStringParser.formatElements(elements);
    return formatted.isEmpty ? toDisplayText() : formatted;
  }

  String get title => 'GS1 Composite POC (${typeEstimate.label})';

  String toDisplayText() {
    final StringBuffer buffer = StringBuffer()
      ..writeln('Confidence: ${(confidence * 100).round()}%')
      ..writeln('Linear: ${Gs1DetectedFormat.name(linearCode.format)}')
      ..writeln(_visibleSeparators(linearCode.text ?? ''))
      ..writeln()
      ..writeln('2D component: ${Gs1DetectedFormat.name(compositeCode.format)}')
      ..writeln(_visibleSeparators(compositeCode.text ?? ''));

    final List<int>? rawBytes = compositeCode.rawBytes;
    if (rawBytes != null && rawBytes.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('2D raw bytes (hex):')
        ..writeln(_hexBytes(rawBytes))
        ..writeln('2D raw bytes (base64):')
        ..writeln(base64Encode(rawBytes));
    }

    if (elements.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Parsed GS1 fields:');
      for (final Gs1Element element in elements) {
        buffer.writeln(
          '(${element.ai}) ${element.title}: ${_visibleSeparators(element.value)}',
        );
      }
    }

    if (warnings.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('POC warnings:');
      for (final String warning in warnings) {
        buffer.writeln('- $warning');
      }
    }

    return buffer.toString().trim();
  }
}

class Gs1Element {
  const Gs1Element({
    required this.ai,
    required this.value,
    required this.title,
  });

  final String ai;
  final String value;
  final String title;
}

class Gs1CompositeAssembler {
  const Gs1CompositeAssembler();

  Gs1CompositeAssembly? assemble(List<Gs1DetectedCode> codes) {
    final List<Gs1DetectedCode> validCodes = codes
        .where(
          (Gs1DetectedCode code) =>
              code.isValid &&
              ((code.text?.isNotEmpty ?? false) ||
                  (code.rawBytes?.isNotEmpty ?? false)),
        )
        .toList();
    final List<Gs1DetectedCode> linearCodes = validCodes
        .where(_isLinear)
        .toList();
    final List<Gs1DetectedCode> compositeCodes = validCodes
        .where(_isCompositeComponent)
        .toList();

    if (linearCodes.isEmpty || compositeCodes.isEmpty) {
      return null;
    }

    _PairCandidate? best;
    for (final Gs1DetectedCode linear in linearCodes) {
      for (final Gs1DetectedCode composite in compositeCodes) {
        final _PairCandidate? candidate = _scorePair(linear, composite);
        if (candidate == null) continue;
        if (best == null || candidate.score > best.score) {
          best = candidate;
        }
      }
    }

    best ??= _fallbackPairAfterGeometryReject(linearCodes, compositeCodes);
    if (best == null) return null;

    final List<String> warnings = <String>[...best.warnings];

    final List<Gs1Element> linearElements = Gs1ElementStringParser.parse(
      best.linear.text ?? '',
      fallbackFormat: best.linear.format,
    );
    final _CompositePayloadParse compositePayload = _parseCompositePayload(
      best.composite,
    );
    final List<Gs1Element> compositeElements = compositePayload.elements;

    if (linearElements.isEmpty) {
      warnings.add(
        'Linear payload could not be parsed as GS1 element strings.',
      );
    }
    if (compositePayload.source != null && compositeElements.isNotEmpty) {
      warnings.add('2D component parsed from ${compositePayload.source}.');
    }
    if (compositeElements.isEmpty) {
      warnings.add(
        '2D component payload could not be parsed as GS1 element strings.',
      );
    }

    return Gs1CompositeAssembly(
      linearCode: best.linear,
      compositeCode: best.composite,
      typeEstimate: _estimateType(best.linear, best.composite),
      confidence: best.score.clamp(0.0, 1.0),
      linearElements: linearElements,
      compositeElements: compositeElements,
      warnings: warnings,
    );
  }

  bool _isLinear(Gs1DetectedCode code) {
    return switch (code.format) {
      Gs1DetectedFormat.code128 ||
      Gs1DetectedFormat.ean8 ||
      Gs1DetectedFormat.ean13 ||
      Gs1DetectedFormat.upca ||
      Gs1DetectedFormat.upce ||
      Gs1DetectedFormat.dataBar ||
      Gs1DetectedFormat.dataBarExpanded ||
      Gs1DetectedFormat.dataBarLimited => true,
      _ => false,
    };
  }

  bool _isCompositeComponent(Gs1DetectedCode code) {
    return code.format == Gs1DetectedFormat.pdf417 ||
        code.format == Gs1DetectedFormat.microPdf417;
  }

  _PairCandidate? _scorePair(
    Gs1DetectedCode linear,
    Gs1DetectedCode composite,
  ) {
    final Rect? linearRect = _rectFor(linear.position);
    final Rect? compositeRect = _rectFor(composite.position);

    if (linearRect == null || compositeRect == null) {
      return _fallbackPair(linear, composite);
    }

    final double overlap = _horizontalOverlap(linearRect, compositeRect);
    final double overlapRatio =
        overlap / math.min(linearRect.width, compositeRect.width);
    final bool compositeAbove =
        compositeRect.center.dy < linearRect.center.dy &&
        compositeRect.bottom <= linearRect.bottom;
    final double gap = linearRect.top - compositeRect.bottom;
    final double maxReasonableGap = math.max(
      linearRect.height * 1.8,
      compositeRect.height * 1.2,
    );
    final bool closeEnough =
        gap <= maxReasonableGap && gap >= -compositeRect.height * 0.6;

    if (overlapRatio < 0.35 || !compositeAbove || !closeEnough) {
      return null;
    }

    final double gapScore = 1 - (gap.abs() / maxReasonableGap).clamp(0.0, 1.0);
    final double score = overlapRatio * 0.55 + gapScore * 0.25 + 0.20;

    return _PairCandidate(
      linear: linear,
      composite: composite,
      score: score,
      warnings: const <String>[],
    );
  }

  _PairCandidate? _fallbackPair(
    Gs1DetectedCode linear,
    Gs1DetectedCode composite,
  ) {
    return _PairCandidate(
      linear: linear,
      composite: composite,
      score: 0.35,
      warnings: const <String>[
        'ZXing did not return complete geometry for at least one component; pair is based on one linear + one 2D candidate only.',
      ],
    );
  }

  _PairCandidate? _fallbackPairAfterGeometryReject(
    List<Gs1DetectedCode> linearCodes,
    List<Gs1DetectedCode> compositeCodes,
  ) {
    if (linearCodes.isEmpty || compositeCodes.isEmpty) return null;

    final Gs1DetectedCode? preferredLinear = _firstWhereOrNull(
      linearCodes,
      (Gs1DetectedCode code) => code.format == Gs1DetectedFormat.code128,
    );
    final Gs1DetectedCode? preferredComposite = _firstWhereOrNull(
      compositeCodes,
      (Gs1DetectedCode code) => code.format == Gs1DetectedFormat.pdf417,
    );

    return _PairCandidate(
      linear: preferredLinear ?? linearCodes.first,
      composite: preferredComposite ?? compositeCodes.first,
      score: 0.25,
      warnings: const <String>[
        'Linear and 2D candidates were both detected, but geometry did not match. Pair is accepted as a fallback because decode passes may use different crop coordinate spaces.',
      ],
    );
  }

  Gs1DetectedCode? _firstWhereOrNull(
    List<Gs1DetectedCode> codes,
    bool Function(Gs1DetectedCode code) test,
  ) {
    for (final Gs1DetectedCode code in codes) {
      if (test(code)) return code;
    }
    return null;
  }

  Rect? _rectFor(Gs1DetectedPosition? position) {
    if (position == null) return null;

    final List<int> xs = <int>[
      position.topLeftX,
      position.topRightX,
      position.bottomLeftX,
      position.bottomRightX,
    ];
    final List<int> ys = <int>[
      position.topLeftY,
      position.topRightY,
      position.bottomLeftY,
      position.bottomRightY,
    ];

    return Rect.fromLTRB(
      xs.reduce(math.min).toDouble(),
      ys.reduce(math.min).toDouble(),
      xs.reduce(math.max).toDouble(),
      ys.reduce(math.max).toDouble(),
    );
  }

  double _horizontalOverlap(Rect a, Rect b) {
    return math.max(0, math.min(a.right, b.right) - math.max(a.left, b.left));
  }

  Gs1CompositeTypeEstimate _estimateType(
    Gs1DetectedCode linear,
    Gs1DetectedCode composite,
  ) {
    if (linear.format == Gs1DetectedFormat.code128 &&
        composite.format == Gs1DetectedFormat.pdf417) {
      return Gs1CompositeTypeEstimate.ccc;
    }
    if (composite.format == Gs1DetectedFormat.microPdf417) {
      return Gs1CompositeTypeEstimate.ccaOrCcb;
    }
    return Gs1CompositeTypeEstimate.unknown;
  }

  _CompositePayloadParse _parseCompositePayload(Gs1DetectedCode code) {
    final String text = code.text ?? '';
    final List<Gs1Element> textElements = Gs1ElementStringParser.parse(
      text,
      fallbackFormat: code.format,
    );
    if (textElements.isNotEmpty) {
      return _CompositePayloadParse(elements: textElements);
    }

    final List<int>? rawBytes = code.rawBytes;
    if (rawBytes == null || rawBytes.isEmpty) {
      return const _CompositePayloadParse(elements: <Gs1Element>[]);
    }

    final List<_PayloadCandidate> candidates = <_PayloadCandidate>[
      if (_decodeCompositeBinaryPayload(rawBytes) case final String decoded?)
        _PayloadCandidate('GS1 Composite binary general field', decoded),
      _PayloadCandidate('raw bytes as Latin-1', latin1.decode(rawBytes)),
      _PayloadCandidate(
        'raw bytes as UTF-8',
        utf8.decode(rawBytes, allowMalformed: true),
      ),
      _PayloadCandidate('raw bytes printable map', _printablePayload(rawBytes)),
    ];

    for (final _PayloadCandidate candidate in candidates) {
      final List<Gs1Element> elements = Gs1ElementStringParser.parse(
        candidate.value,
        fallbackFormat: code.format,
      );
      if (elements.isNotEmpty) {
        return _CompositePayloadParse(
          elements: elements,
          source: candidate.source,
        );
      }
    }

    return const _CompositePayloadParse(elements: <Gs1Element>[]);
  }
}

class Gs1ElementStringParser {
  const Gs1ElementStringParser._();

  static String formatElements(List<Gs1Element> elements) {
    return elements
        .map((Gs1Element element) => '(${element.ai})${element.value}')
        .join();
  }

  static String? tryFormatElementString(
    String raw, {
    int? fallbackFormat,
    bool requireGs1Marker = false,
  }) {
    if (requireGs1Marker && !_hasGs1Marker(raw)) return null;

    final List<Gs1Element> elements = parse(
      raw,
      fallbackFormat: fallbackFormat,
    );
    if (elements.isEmpty) return null;

    return formatElements(elements);
  }

  static bool looksLikeEscapedBinaryControlPayload(String raw) {
    final bool hasControlRunes = raw.runes.any(
      (int rune) => rune < 32 && rune != 10 && rune != 13 && rune != 29,
    );
    if (hasControlRunes) return true;

    return RegExp(
      r'<(?:NUL|SOH|STX|ETX|EOT|ENQ|ACK|BEL|BS|HT|LF|VT|FF|CR|SO|SI|DLE|DC[1-4]|NAK|SYN|ETB|CAN|EM|SUB|ESC|FS|RS|US)>',
      caseSensitive: false,
    ).hasMatch(raw);
  }

  static List<Gs1Element> parse(String raw, {int? fallbackFormat}) {
    final String normalized = _normalize(raw, fallbackFormat: fallbackFormat);
    if (normalized.isEmpty) return const <Gs1Element>[];

    if (normalized.contains('(')) {
      return _parseBracketed(normalized);
    }

    return _parseRawElementString(normalized);
  }

  static String _normalize(String raw, {int? fallbackFormat}) {
    String value = raw.trim();
    value = value.replaceFirst(RegExp(r'^\][A-Za-z0-9]{2}'), '');
    value = value
        .replaceAll(
          RegExp(r'\{GS\}|<GS>|\\u001d|\\x1d', caseSensitive: false),
          '\u001d',
        )
        .replaceAll('\u241d', '\u001d');
    value = value.replaceFirst(RegExp(r'^\u001d+'), '');

    if (RegExp(r'^\d+$').hasMatch(value)) {
      if (fallbackFormat == Gs1DetectedFormat.ean13 && value.length == 13) {
        return '01${value.padLeft(14, '0')}';
      }
      if (fallbackFormat == Gs1DetectedFormat.upca && value.length == 12) {
        return '01${value.padLeft(14, '0')}';
      }
      if (fallbackFormat == Gs1DetectedFormat.ean8 && value.length == 8) {
        return '01${value.padLeft(14, '0')}';
      }
    }

    return value;
  }

  static bool _hasGs1Marker(String raw) {
    final String value = raw.trim();
    return value.startsWith(RegExp(r'\][A-Za-z0-9]{2}')) ||
        value.contains('\u001d') ||
        value.contains('\u241d') ||
        RegExp(
          r'\{GS\}|<GS>|\\u001d|\\x1d',
          caseSensitive: false,
        ).hasMatch(value);
  }

  static List<Gs1Element> _parseBracketed(String input) {
    final List<Gs1Element> elements = <Gs1Element>[];
    final RegExp pattern = RegExp(r'\((\d{2,4})\)([^\(]*)');

    for (final RegExpMatch match in pattern.allMatches(input)) {
      final String ai = match.group(1)!;
      final String value = match.group(2)!.replaceAll('\u001d', '').trim();
      elements.add(Gs1Element(ai: ai, value: value, title: _titleFor(ai)));
    }

    return elements;
  }

  static List<Gs1Element> _parseRawElementString(String input) {
    final List<Gs1Element> elements = <Gs1Element>[];
    int index = 0;

    while (index < input.length) {
      if (input.codeUnitAt(index) == 29) {
        index++;
        continue;
      }

      final _AiDefinition? definition = _matchAi(input, index);
      if (definition == null) {
        break;
      }

      index += definition.ai.length;
      final int remaining = input.length - index;
      if (remaining <= 0) break;

      final String value;
      if (definition.fixedLength != null) {
        final int length = math.min(definition.fixedLength!, remaining);
        value = input.substring(index, index + length);
        index += length;
      } else {
        final int separator = input.indexOf('\u001d', index);
        final int maxEnd = math.min(input.length, index + definition.maxLength);
        final int end = separator == -1 ? maxEnd : math.min(separator, maxEnd);
        value = input.substring(index, end);
        index = end;
      }

      elements.add(
        Gs1Element(ai: definition.ai, value: value, title: definition.title),
      );
    }

    return elements;
  }

  static _AiDefinition? _matchAi(String input, int index) {
    for (final _AiDefinition definition in _fixedDefinitions) {
      if (input.startsWith(definition.ai, index)) {
        return definition;
      }
    }

    for (final _AiDefinition definition in _variableDefinitions) {
      if (input.startsWith(definition.ai, index)) {
        return definition;
      }
    }

    if (index + 4 <= input.length) {
      final String ai4 = input.substring(index, index + 4);
      final int? prefix = int.tryParse(ai4.substring(0, 3));
      if (prefix != null && prefix >= 310 && prefix <= 369) {
        return _AiDefinition.fixed(ai4, 6, 'Measurement');
      }
      if (RegExp(r'^39[23]\d$').hasMatch(ai4)) {
        return _AiDefinition.variable(ai4, 18, 'Amount payable');
      }
    }

    if (index + 2 <= input.length) {
      final String ai2 = input.substring(index, index + 2);
      if (ai2.startsWith('9')) {
        return _AiDefinition.variable(ai2, 90, 'Company internal');
      }
    }

    return null;
  }

  static String _titleFor(String ai) {
    final _AiDefinition? definition = _fixedDefinitions
        .cast<_AiDefinition?>()
        .followedBy(_variableDefinitions)
        .firstWhere(
          (_AiDefinition? definition) => definition?.ai == ai,
          orElse: () => null,
        );
    if (definition != null) return definition.title;
    if (RegExp(
      r'^31\d\d$|^32\d\d$|^33\d\d$|^34\d\d$|^35\d\d$|^36\d\d$',
    ).hasMatch(ai)) {
      return 'Measurement';
    }
    if (RegExp(r'^39[23]\d$').hasMatch(ai)) {
      return 'Amount payable';
    }
    if (ai.startsWith('9')) return 'Company internal';
    return 'AI $ai';
  }

  static final List<_AiDefinition> _fixedDefinitions = <_AiDefinition>[
    _AiDefinition.fixed('8017', 18, 'GSRN provider'),
    _AiDefinition.fixed('8018', 18, 'GSRN recipient'),
    _AiDefinition.fixed('8005', 6, 'Price per unit of measure'),
    _AiDefinition.fixed('8006', 18, 'ITIP'),
    _AiDefinition.fixed('8026', 18, 'ITIP contained'),
    _AiDefinition.fixed('410', 13, 'Ship to GLN'),
    _AiDefinition.fixed('411', 13, 'Bill to GLN'),
    _AiDefinition.fixed('412', 13, 'Purchased from GLN'),
    _AiDefinition.fixed('413', 13, 'Ship for GLN'),
    _AiDefinition.fixed('415', 13, 'Pay to GLN'),
    _AiDefinition.fixed('414', 13, 'Physical location GLN'),
    _AiDefinition.fixed('422', 3, 'Country of origin'),
    _AiDefinition.fixed('424', 3, 'Country of processing'),
    _AiDefinition.fixed('425', 3, 'Country of disassembly'),
    _AiDefinition.fixed('426', 3, 'Country covering full process'),
    _AiDefinition.fixed('00', 18, 'SSCC'),
    _AiDefinition.fixed('01', 14, 'GTIN'),
    _AiDefinition.fixed('02', 14, 'Content GTIN'),
    _AiDefinition.fixed('11', 6, 'Production date'),
    _AiDefinition.fixed('12', 6, 'Due date'),
    _AiDefinition.fixed('13', 6, 'Packaging date'),
    _AiDefinition.fixed('15', 6, 'Best before date'),
    _AiDefinition.fixed('16', 6, 'Sell by date'),
    _AiDefinition.fixed('17', 6, 'Expiration date'),
    _AiDefinition.fixed('20', 2, 'Product variant'),
  ];

  static final List<_AiDefinition> _variableDefinitions = <_AiDefinition>[
    _AiDefinition.variable('8110', 70, 'Coupon code'),
    _AiDefinition.variable('8112', 70, 'Paperless coupon code'),
    _AiDefinition.variable('8004', 30, 'GIAI'),
    _AiDefinition.variable('8008', 12, 'Production date/time'),
    _AiDefinition.variable('8010', 30, 'CPID'),
    _AiDefinition.variable('8011', 12, 'CPID serial'),
    _AiDefinition.variable('8012', 20, 'Software version'),
    _AiDefinition.variable('8200', 70, 'Extended packaging URL'),
    _AiDefinition.variable('240', 30, 'Additional product identification'),
    _AiDefinition.variable('241', 30, 'Customer part number'),
    _AiDefinition.variable('242', 6, 'Made-to-order variation'),
    _AiDefinition.variable('243', 20, 'Packaging component number'),
    _AiDefinition.variable('250', 30, 'Secondary serial number'),
    _AiDefinition.variable('251', 30, 'Reference to source entity'),
    _AiDefinition.variable('253', 30, 'GDTI'),
    _AiDefinition.variable('254', 20, 'GLN extension component'),
    _AiDefinition.variable('255', 25, 'GCN'),
    _AiDefinition.variable('400', 30, 'Customer purchase order number'),
    _AiDefinition.variable('401', 30, 'GINC'),
    _AiDefinition.variable('403', 30, 'Routing code'),
    _AiDefinition.variable('420', 20, 'Ship to postal code'),
    _AiDefinition.variable('421', 15, 'Ship to postal code with country'),
    _AiDefinition.variable('10', 20, 'Batch or lot number'),
    _AiDefinition.variable('21', 20, 'Serial number'),
    _AiDefinition.variable('22', 20, 'Consumer product variant'),
    _AiDefinition.variable('30', 8, 'Variable count'),
    _AiDefinition.variable('37', 8, 'Count of trade items'),
  ];
}

String? _decodeCompositeBinaryPayload(List<int> rawBytes) {
  final _BitCursor bits = _BitCursor(rawBytes);
  if (bits.remaining < 1) return null;

  if (bits.peek(1) == 0) {
    bits.skip(1);
    return _decodeCompositeGeneralField(
      bits,
      _CompositeGeneralFieldMode.numeric,
    );
  }

  if (bits.remaining >= 4 && bits.peek(4) == 0x0B) {
    // Encodation method "10" with no date data. The AI "10" is implied and
    // the remaining bits hold the lot number/general field.
    bits.skip(4);
    final String? generalField = _decodeCompositeGeneralField(
      bits,
      _CompositeGeneralFieldMode.numeric,
    );
    if (generalField == null) return null;
    return '10$generalField';
  }

  return null;
}

String? _decodeCompositeGeneralField(
  _BitCursor bits,
  _CompositeGeneralFieldMode mode,
) {
  final StringBuffer buffer = StringBuffer();

  while (bits.remaining > 0) {
    if (_looksLikeCompositePadding(bits, mode)) break;

    switch (mode) {
      case _CompositeGeneralFieldMode.numeric:
        if (bits.remaining >= 4 && bits.peek(4) == 0) {
          bits.skip(4);
          mode = _CompositeGeneralFieldMode.alphanumeric;
          continue;
        }
        if (bits.remaining < 7) {
          return buffer.isEmpty ? null : buffer.toString();
        }

        final int value = bits.read(7);
        if (value < 8 || value > 128) {
          return buffer.isEmpty ? null : buffer.toString();
        }

        final int pairValue = value - 8;
        final int first = pairValue ~/ 11;
        final int second = pairValue % 11;
        if (first > 10 || second > 10) {
          return buffer.isEmpty ? null : buffer.toString();
        }

        buffer.write(first == 10 ? '\u001d' : first.toString());
        if (second == 10 &&
            _looksLikeCompositePadding(
              bits,
              _CompositeGeneralFieldMode.numeric,
            )) {
          break;
        }
        buffer.write(second == 10 ? '\u001d' : second.toString());

      case _CompositeGeneralFieldMode.alphanumeric:
        if (bits.remaining >= 3 && bits.peek(3) == 0) {
          bits.skip(3);
          mode = _CompositeGeneralFieldMode.numeric;
          continue;
        }
        if (bits.remaining >= 5) {
          final int value5 = bits.peek(5);
          if (value5 == 15) {
            bits.skip(5);
            buffer.write('\u001d');
            mode = _CompositeGeneralFieldMode.numeric;
            continue;
          }
          if (value5 == 4) {
            bits.skip(5);
            mode = _CompositeGeneralFieldMode.isoIec646;
            continue;
          }
          if (value5 >= 5 && value5 <= 14) {
            bits.skip(5);
            buffer.writeCharCode(value5 + 43);
            continue;
          }
        }
        if (bits.remaining < 6) {
          return buffer.isEmpty ? null : buffer.toString();
        }

        final int value6 = bits.read(6);
        if (value6 >= 32 && value6 <= 57) {
          buffer.writeCharCode(value6 + 33);
        } else if (value6 >= 58 && value6 <= 62) {
          buffer.write('*,-./'[value6 - 58]);
        } else {
          return buffer.isEmpty ? null : buffer.toString();
        }

      case _CompositeGeneralFieldMode.isoIec646:
        if (bits.remaining >= 3 && bits.peek(3) == 0) {
          bits.skip(3);
          mode = _CompositeGeneralFieldMode.numeric;
          continue;
        }
        if (bits.remaining >= 5) {
          final int value5 = bits.peek(5);
          if (value5 == 15) {
            bits.skip(5);
            buffer.write('\u001d');
            mode = _CompositeGeneralFieldMode.numeric;
            continue;
          }
          if (value5 == 4) {
            bits.skip(5);
            mode = _CompositeGeneralFieldMode.alphanumeric;
            continue;
          }
          if (value5 >= 5 && value5 <= 14) {
            bits.skip(5);
            buffer.writeCharCode(value5 + 43);
            continue;
          }
        }
        if (bits.remaining >= 7) {
          final int value7 = bits.peek(7);
          if (value7 >= 64 && value7 <= 89) {
            bits.skip(7);
            buffer.writeCharCode(value7 + 1);
            continue;
          }
          if (value7 >= 90 && value7 <= 115) {
            bits.skip(7);
            buffer.writeCharCode(value7 + 7);
            continue;
          }
        }
        if (bits.remaining < 8) {
          return buffer.isEmpty ? null : buffer.toString();
        }

        final int value8 = bits.read(8);
        const String punctuation = '!"%&\'()*+,-./:;<=>?_ ';
        if (value8 >= 232 && value8 < 232 + punctuation.length) {
          buffer.write(punctuation[value8 - 232]);
        } else {
          return buffer.isEmpty ? null : buffer.toString();
        }
    }
  }

  return buffer.isEmpty ? null : buffer.toString();
}

bool _looksLikeCompositePadding(
  _BitCursor bits,
  _CompositeGeneralFieldMode mode,
) {
  if (bits.remaining <= 0) return true;

  return switch (mode) {
    _CompositeGeneralFieldMode.numeric =>
      bits.remaining >= 4 &&
          bits.peek(4) == 0 &&
          _remainingMatchesRepeatedPattern(bits, 4, '00100'),
    _CompositeGeneralFieldMode.alphanumeric ||
    _CompositeGeneralFieldMode.isoIec646 => _remainingMatchesRepeatedPattern(
      bits,
      0,
      '00100',
    ),
  };
}

bool _remainingMatchesRepeatedPattern(
  _BitCursor bits,
  int offset,
  String pattern,
) {
  if (bits.remaining < offset) return false;

  for (int i = offset; i < bits.remaining; i++) {
    final int expected = pattern.codeUnitAt((i - offset) % pattern.length) - 48;
    if (bits.peekBit(i) != expected) return false;
  }
  return true;
}

class _AiDefinition {
  const _AiDefinition.fixed(this.ai, int length, this.title)
    : fixedLength = length,
      maxLength = length;

  const _AiDefinition.variable(this.ai, this.maxLength, this.title)
    : fixedLength = null;

  final String ai;
  final int? fixedLength;
  final int maxLength;
  final String title;
}

class _PairCandidate {
  const _PairCandidate({
    required this.linear,
    required this.composite,
    required this.score,
    required this.warnings,
  });

  final Gs1DetectedCode linear;
  final Gs1DetectedCode composite;
  final double score;
  final List<String> warnings;
}

String _visibleSeparators(String value) {
  return value.replaceAll('\u001d', '<GS>');
}

String _hexBytes(List<int> bytes) {
  return bytes
      .map((int byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join(' ');
}

String _printablePayload(List<int> bytes) {
  final StringBuffer buffer = StringBuffer();
  for (final int byte in bytes) {
    if (byte == 29) {
      buffer.write('\u001d');
    } else if (byte >= 32 && byte <= 126) {
      buffer.writeCharCode(byte);
    }
  }
  return buffer.toString();
}

class _CompositePayloadParse {
  const _CompositePayloadParse({required this.elements, this.source});

  final List<Gs1Element> elements;
  final String? source;
}

class _PayloadCandidate {
  const _PayloadCandidate(this.source, this.value);

  final String source;
  final String value;
}

enum _CompositeGeneralFieldMode { numeric, alphanumeric, isoIec646 }

class _BitCursor {
  _BitCursor(this.bytes);

  final List<int> bytes;
  int position = 0;

  int get length => bytes.length * 8;
  int get remaining => length - position;

  int peek(int count) {
    int value = 0;
    for (int i = 0; i < count; i++) {
      value = (value << 1) | peekBit(i);
    }
    return value;
  }

  int read(int count) {
    final int value = peek(count);
    skip(count);
    return value;
  }

  void skip(int count) {
    position += count;
  }

  int peekBit(int offset) {
    final int bitPosition = position + offset;
    if (bitPosition < 0 || bitPosition >= length) return 0;
    final int byte = bytes[bitPosition >> 3];
    return (byte >> (7 - (bitPosition & 7))) & 1;
  }
}
