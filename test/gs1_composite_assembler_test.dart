import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:poc_multi_scan/services/native_scanners/gs1/gs1_composite_assembler.dart';

void main() {
  group('Gs1CompositeAssembler', () {
    test('pairs a PDF417 component above a GS1-128 linear code', () {
      final Gs1CompositeAssembly?
      assembly = const Gs1CompositeAssembler().assemble(<Code>[
        Code(
          text: '0109506000134352',
          format: Format.code128,
          isValid: true,
          position: Position(1000, 800, 200, 420, 800, 420, 200, 500, 800, 500),
        ),
        Code(
          text: '1726010110LOT123',
          format: Format.pdf417,
          isValid: true,
          position: Position(1000, 800, 230, 300, 770, 300, 230, 400, 770, 400),
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
      final Gs1CompositeAssembly?
      assembly = const Gs1CompositeAssembler().assemble(<Code>[
        Code(
          text: '0109506000134352',
          format: Format.code128,
          isValid: true,
          position: Position(1000, 800, 100, 650, 300, 650, 100, 700, 300, 700),
        ),
        Code(
          text: '1726010110LOT123',
          format: Format.pdf417,
          isValid: true,
          position: Position(1000, 800, 700, 100, 900, 100, 700, 150, 900, 150),
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
        fallbackFormat: Format.ean13,
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
  });
}
