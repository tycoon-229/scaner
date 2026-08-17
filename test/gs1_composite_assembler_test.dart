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

    test('does not pair distant codes', () {
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

      expect(assembly, isNull);
    });
  });

  group('Gs1ElementStringParser', () {
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
  });
}
