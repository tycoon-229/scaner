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
              code.isValid && (code.text?.isNotEmpty ?? false),
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

    if (best == null) {
      return null;
    }

    final List<String> warnings = <String>[
      ...best.warnings,
      if (best.composite.format == Gs1DetectedFormat.pdf417)
        'This POC maps PDF417-like composite components to one generic PDF417 format and cannot distinguish PDF417 from MicroPDF417.',
    ];

    final List<Gs1Element> linearElements = Gs1ElementStringParser.parse(
      best.linear.text ?? '',
      fallbackFormat: best.linear.format,
    );
    final List<Gs1Element> compositeElements = Gs1ElementStringParser.parse(
      best.composite.text ?? '',
      fallbackFormat: best.composite.format,
    );

    if (linearElements.isEmpty) {
      warnings.add(
        'Linear payload could not be parsed as GS1 element strings.',
      );
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
    return code.format == Gs1DetectedFormat.pdf417;
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
    if (composite.format == Gs1DetectedFormat.pdf417) {
      return Gs1CompositeTypeEstimate.ccaOrCcb;
    }
    return Gs1CompositeTypeEstimate.unknown;
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
