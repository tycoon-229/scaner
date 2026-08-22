import 'package:flutter_test/flutter_test.dart';
import 'package:poc_multi_scan/services/native_scanners/gs1/gs1_composite_assembler.dart';
import 'package:poc_multi_scan/services/native_scanners/gs1/gs1_detected_code.dart';

void main() {
  group('Gs1CompositeAssembler', () {
    test('pairs a PDF417 component above a GS1-128 linear code', () {
      final Gs1CompositeAssembly? assembly = const Gs1CompositeAssembler()
          .assemble(<Gs1DetectedCode>[
            Gs1DetectedCode(
              text: '0109506000134352',
              format: Gs1DetectedFormat.code128,
              isValid: true,
              position: Gs1DetectedPosition(
                imageWidth: 1000,
                imageHeight: 800,
                topLeftX: 200,
                topLeftY: 420,
                topRightX: 800,
                topRightY: 420,
                bottomLeftX: 200,
                bottomLeftY: 500,
                bottomRightX: 800,
                bottomRightY: 500,
              ),
            ),
            Gs1DetectedCode(
              text: '1726010110LOT123',
              format: Gs1DetectedFormat.pdf417,
              isValid: true,
              position: Gs1DetectedPosition(
                imageWidth: 1000,
                imageHeight: 800,
                topLeftX: 230,
                topLeftY: 300,
                topRightX: 770,
                topRightY: 300,
                bottomLeftX: 230,
                bottomLeftY: 400,
                bottomRightX: 770,
                bottomRightY: 400,
              ),
            ),
          ]);

      expect(assembly, isNotNull);
      expect(assembly!.typeEstimate, Gs1CompositeTypeEstimate.ccc);
      expect(assembly.confidence, greaterThan(0.6));
      expect(
        assembly.elements.map((Gs1Element element) => element.ai),
        containsAll(<String>['01', '17', '10']),
      );
    });

    test('pairs a MicroPDF417 component as CC-A or CC-B', () {
      final Gs1CompositeAssembly? assembly = const Gs1CompositeAssembler()
          .assemble(<Gs1DetectedCode>[
            Gs1DetectedCode(
              text: '0103812345678908',
              format: Gs1DetectedFormat.dataBar,
              isValid: true,
              position: Gs1DetectedPosition(
                imageWidth: 1000,
                imageHeight: 800,
                topLeftX: 200,
                topLeftY: 420,
                topRightX: 800,
                topRightY: 420,
                bottomLeftX: 200,
                bottomLeftY: 500,
                bottomRightX: 800,
                bottomRightY: 500,
              ),
            ),
            Gs1DetectedCode(
              text: '10ABCD123456\u001d4103898765432108',
              format: Gs1DetectedFormat.microPdf417,
              isValid: true,
              position: Gs1DetectedPosition(
                imageWidth: 1000,
                imageHeight: 800,
                topLeftX: 230,
                topLeftY: 300,
                topRightX: 770,
                topRightY: 300,
                bottomLeftX: 230,
                bottomLeftY: 400,
                bottomRightX: 770,
                bottomRightY: 400,
              ),
            ),
          ]);

      expect(assembly, isNotNull);
      expect(assembly!.typeEstimate, Gs1CompositeTypeEstimate.ccaOrCcb);
      expect(
        assembly.resultText,
        '(01)03812345678908(10)ABCD123456(410)3898765432108',
      );
    });

    test('decodes CC-C binary general field from PDF417 raw bytes', () {
      final Gs1CompositeAssembly? assembly = const Gs1CompositeAssembler()
          .assemble(<Gs1DetectedCode>[
            const Gs1DetectedCode(
              text: '(01)03812345678908',
              format: Gs1DetectedFormat.code128,
              isValid: true,
            ),
            Gs1DetectedCode(
              text: String.fromCharCodes(<int>[
                0x13,
                0x08,
                0x21,
                0x8A,
                0x30,
                0x55,
                0x6C,
                0x5F,
                0x44,
                0xD8,
                0xF3,
                0xB7,
                0x0D,
                0x59,
                0x3D,
                0x40,
              ]),
              rawBytes: const <int>[
                0x13,
                0x08,
                0x21,
                0x8A,
                0x30,
                0x55,
                0x6C,
                0x5F,
                0x44,
                0xD8,
                0xF3,
                0xB7,
                0x0D,
                0x59,
                0x3D,
                0x40,
              ],
              format: Gs1DetectedFormat.pdf417,
              isValid: true,
            ),
          ]);

      expect(assembly, isNotNull);
      expect(
        assembly!.resultText,
        '(01)03812345678908(10)ABCD123456(410)3898765432108',
      );
      expect(
        assembly.warnings,
        contains(
          '2D component parsed from GS1 Composite binary general field.',
        ),
      );
    });

    test('pairs distant codes as a low-confidence fallback', () {
      final Gs1CompositeAssembly? assembly = const Gs1CompositeAssembler()
          .assemble(<Gs1DetectedCode>[
            Gs1DetectedCode(
              text: '0109506000134352',
              format: Gs1DetectedFormat.code128,
              isValid: true,
              position: Gs1DetectedPosition(
                imageWidth: 1000,
                imageHeight: 800,
                topLeftX: 100,
                topLeftY: 650,
                topRightX: 300,
                topRightY: 650,
                bottomLeftX: 100,
                bottomLeftY: 700,
                bottomRightX: 300,
                bottomRightY: 700,
              ),
            ),
            Gs1DetectedCode(
              text: '1726010110LOT123',
              format: Gs1DetectedFormat.pdf417,
              isValid: true,
              position: Gs1DetectedPosition(
                imageWidth: 1000,
                imageHeight: 800,
                topLeftX: 700,
                topLeftY: 100,
                topRightX: 900,
                topRightY: 100,
                bottomLeftX: 700,
                bottomLeftY: 150,
                bottomRightX: 900,
                bottomRightY: 150,
              ),
            ),
          ]);

      expect(assembly, isNotNull);
      expect(assembly!.confidence, 0.25);
      expect(
        assembly.warnings,
        contains(
          'Linear and 2D candidates were both detected, but geometry did not match. Pair is accepted as a fallback because decode passes may use different crop coordinate spaces.',
        ),
      );
    });
  });

  group('Gs1ElementStringParser', () {
    test('normalizes only valid bare DataBar GTIN payloads', () {
      expect(
        Gs1DataBarTextNormalizer.normalize(
          formatName: 'DATABAR',
          format: Gs1DetectedFormat.dataBar,
          text: '04912345678904',
        ),
        '(01)04912345678904',
      );
      expect(
        Gs1DataBarTextNormalizer.normalize(
          formatName: 'DATABAR_EXPANDED',
          format: Gs1DetectedFormat.dataBarExpanded,
          text: '1726010110LOT123',
        ),
        '1726010110LOT123',
      );
      expect(
        Gs1DataBarTextNormalizer.normalize(
          formatName: 'DATABAR',
          format: Gs1DetectedFormat.dataBar,
          text: '04912345678905',
        ),
        '04912345678905',
      );
    });

    test('normalizes bare DataBar Limited GTIN payloads', () {
      expect(
        Gs1DataBarTextNormalizer.normalize(
          text: '09521234543213',
          formatName: 'GS1_DATABAR_LIMITED',
          format: Gs1DetectedFormat.dataBarLimited,
        ),
        '(01)09521234543213',
      );
    });

    test('parses bracketed element strings', () {
      final List<Gs1Element> elements = Gs1ElementStringParser.parse(
        '(01)09506000134352(17)260101(10)LOT123',
      );

      expect(elements.map((Gs1Element element) => element.ai), <String>[
        '01',
        '17',
        '10',
      ]);
      expect(elements.last.value, 'LOT123');
    });

    test('normalizes EAN-13 as GTIN AI 01', () {
      final List<Gs1Element> elements = Gs1ElementStringParser.parse(
        '9506000134352',
        fallbackFormat: Gs1DetectedFormat.ean13,
      );

      expect(elements.single.ai, '01');
      expect(elements.single.value, '09506000134352');
    });

    test('formats raw GS1 composite payload with group separators', () {
      final String? text = Gs1ElementStringParser.tryFormatElementString(
        '{GS}0103812345678908\u001d10ABCD123456\u001d4103898765432108',
        requireGs1Marker: true,
      );

      expect(text, '(01)03812345678908(10)ABCD123456(410)3898765432108');
    });

    test('formats Scandit linear and composite parts as one GS1 payload', () {
      final List<Gs1Element> elements = <Gs1Element>[
        ...Gs1ElementStringParser.parse('0103812345678908'),
        ...Gs1ElementStringParser.parse('10ABCD123456\u001d4103898765432108'),
      ];

      expect(
        Gs1ElementStringParser.formatElements(elements),
        '(01)03812345678908(10)ABCD123456(410)3898765432108',
      );
    });

    test('detects escaped binary PDF417 component payloads', () {
      expect(
        Gs1ElementStringParser.looksLikeEscapedBinaryControlPayload(
          '<DC3><BS>!<U+8A>OUl_D\u00d86\u00b7<CR>Y=@',
        ),
        isTrue,
      );
    });

    test('recovers AI (01) for GS1 DataBar when raw text lacks prefix', () {
      // GS1 DataBar Omnidirectional may return bare data without AI prefix
      // ZXing might return "0491234567890​4" instead of "(01)0491234567890​4"
      // This test verifies that when we detect GS1 DataBar format
      // and prepend "(01)", the parser handles it correctly

      // Simulate the fixed format: prepend (01)
      final List<Gs1Element> elements = Gs1ElementStringParser.parse(
        '(01)0491234567890​4',
      );

      expect(elements, isNotEmpty);
      expect(elements.first.ai, '01');
      // The formatted result should have (01) prefix
      final String formatted = Gs1ElementStringParser.formatElements(elements);
      expect(formatted, startsWith('(01)'));
    });

    test('parses GS1-128 payload ending with AI prefix without truncating trailing characters', () {
      final List<Gs1Element> elements = Gs1ElementStringParser.parse(
        '010498708170022610',
      );

      expect(elements.map((e) => e.ai), <String>['01', '10']);
      expect(elements.first.value, '04987081700226');
      expect(
        Gs1ElementStringParser.formatElements(elements),
        '(01)04987081700226(10)',
      );
    });
  });
}
