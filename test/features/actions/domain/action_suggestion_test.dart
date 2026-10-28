import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/features/actions/domain/entities/action_home_summary.dart';
import 'package:garden_journal/features/actions/domain/entities/action_suggestion.dart';
import 'package:garden_journal/features/actions/domain/entities/plant_action.dart';
import 'package:garden_journal/features/plants/domain/entities/plant.dart';

void main() {
  final now = DateTime(2026, 10, 25, 12);
  Plant plant(String id, {String location = 'indoor', bool? reminder}) => Plant(
      id: id,
      name: id,
      pottingDate: now,
      cultureType: 'Terre',
      qrCode: 'plant:$id',
      createdAt: now,
      updatedAt: now,
      location: location,
      wateringReminder: reminder);

  test('la pluie supprime le suivi automatique, le choix individuel prime', () {
    final outdoor = plant('out', location: 'outdoor');
    final sheltered = plant('sheltered', location: 'outdoor', reminder: true);
    expect(outdoor.hasWateringReminder, isFalse);
    expect(sheltered.hasWateringReminder, isTrue);
    expect(sheltered.copyWith(location: 'indoor').wateringReminder, isTrue);
    expect(Plant.fromMap(sheltered.toMap()).wateringReminder, isTrue);
    expect(sheltered.copyWith(wateringReminder: null).hasWateringReminder,
        isFalse);
    final suggestions = ActionSuggestion.forPlants(
        plants: [outdoor, sheltered], summaries: {}, planned: [], now: now);
    expect(
        suggestions
            .where((s) => s.actionType == 'arrosage')
            .map((s) => s.plant.id),
        ['sheltered']);
  });

  test('une action planifiée évite les doublons sans compter comme réalisée',
      () {
    final p = plant('p');
    final planned = PlantAction(
        id: 'plan',
        plantId: p.id,
        actionType: 'nutriments',
        timestamp: now.add(const Duration(days: 1)),
        createdAt: now,
        status: 'planned',
        isWateringCombined: true);
    final suggestions = ActionSuggestion.forPlants(
        plants: [p], summaries: {}, planned: [planned], now: now);
    expect(suggestions.map((s) => s.actionType), ['observation']);
    expect(planned.isPlanned, isTrue);
  });

  test('les observations et arrosages récents ne sont pas reproposés', () {
    final p = plant('p');
    expect(
        ActionSuggestion.forPlants(plants: [
          p
        ], summaries: {
          p.id: ActionHomeSummary(
              plantId: p.id, lastWaterAt: now, lastObservationAt: now),
        }, planned: [], now: now),
        isEmpty);
    expect(
        ActionSuggestion.forPlants(plants: [
          p.copyWith(isDead: true),
          p.copyWith(id: 'harvested', isHarvested: true)
        ], summaries: {}, planned: [], now: now),
        isEmpty);
  });
}
