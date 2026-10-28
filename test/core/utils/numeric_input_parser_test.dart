import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/core/utils/numeric_input_parser.dart';

void main() {
  test(
      'le parseur commun accepte les décimales signées et rejette les ambiguïtés',
      () {
    expect(NumericInputParser.tryParse(' -0,25 '), -0.25);
    expect(NumericInputParser.parse('6,5'), 6.5);
    for (final input in ['1,2.3', '1,2,3', 'NaN', 'Infinity', '1e999', '']) {
      expect(NumericInputParser.tryParse(input), isNull);
      expect(() => NumericInputParser.parse(input), throwsFormatException);
    }
  });
  test('accepte virgule, point, zéro et valeur vide', () {
    expect(
      NumericInputParser.optionalNonNegative(
        '42,5',
        fieldLabel: 'Poids',
      ),
      42.5,
    );
    expect(
      NumericInputParser.optionalNonNegative(
        '42.5',
        fieldLabel: 'Poids',
      ),
      42.5,
    );
    expect(
      NumericInputParser.optionalNonNegative('0', fieldLabel: 'Poids'),
      0,
    );
    expect(
      NumericInputParser.optionalNonNegative('', fieldLabel: 'Poids'),
      isNull,
    );
  });

  test('refuse négatif, NaN, Infinity et valeur excessive', () {
    for (final value in const ['-1', 'NaN', 'Infinity', '1000001']) {
      expect(
        () => NumericInputParser.optionalNonNegative(
          value,
          fieldLabel: 'Poids',
        ),
        throwsFormatException,
      );
    }
  });

  test('applique des bornes configurables aux autres champs', () {
    expect(
      NumericInputParser.optionalBounded(
        '6,5',
        fieldLabel: 'pH',
        minimum: 3.5,
        maximum: 9,
      ),
      6.5,
    );
    expect(
      () => NumericInputParser.optionalBounded(
        '9,1',
        fieldLabel: 'pH',
        minimum: 3.5,
        maximum: 9,
      ),
      throwsFormatException,
    );
  });
}
