import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/core/utils/app_utils.dart';

void main() {
  test('la floraison compte des jours calendaires et gère le singulier', () {
    expect(
        AppUtils.floweringDuration(DateTime(2026, 10, 24, 23, 59),
            end: DateTime(2026, 10, 25, 0, 1)),
        'Depuis 1 jour');
    expect(
        AppUtils.floweringDuration(DateTime(2026, 10, 1),
            end: DateTime(2026, 10, 25)),
        'Depuis 24 jours');
    expect(
        AppUtils.floweringDuration(DateTime(2026, 10, 26),
            end: DateTime(2026, 10, 25)),
        'Depuis 0 jours');
  });
}
