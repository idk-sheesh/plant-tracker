import '../../../plants/domain/entities/plant.dart';
import 'action_home_summary.dart';
import 'plant_action.dart';

class ActionSuggestion {
  final Plant plant;
  final String actionType;
  final String title;
  final String reason;
  const ActionSuggestion(
      {required this.plant,
      required this.actionType,
      required this.title,
      required this.reason});

  static List<ActionSuggestion> forPlants(
      {required Iterable<Plant> plants,
      required Map<String, ActionHomeSummary> summaries,
      required Iterable<PlantAction> planned,
      DateTime? now}) {
    final today = now ?? DateTime.now();
    final result = <ActionSuggestion>[];
    final pending = <String>{
      for (final action in planned.where((a) => a.isPlanned))
        '${action.plantId}:${action.actionType}'
    };
    for (final action in planned) {
      if (action.isPlanned &&
          action.actionType == 'nutriments' &&
          action.isWateringCombined) {
        pending.add('${action.plantId}:arrosage');
      }
    }
    for (final plant in plants) {
      if (plant.isDead || plant.isHarvested) continue;
      final summary = summaries[plant.id];
      final lastWater = summary?.lastWaterAt;
      if (plant.hasWateringReminder &&
          !pending.contains('${plant.id}:arrosage') &&
          (lastWater == null || today.difference(lastWater).inDays >= 3)) {
        result.add(ActionSuggestion(
            plant: plant,
            actionType: 'arrosage',
            title: 'Vérifier le besoin d’eau',
            reason: lastWater == null
                ? 'Aucun arrosage enregistré. Vérifie le substrat avant d’arroser.'
                : 'Dernier arrosage il y a ${today.difference(lastWater).inDays} jours. '
                    'Le délai seul ne signifie pas que la plante a soif.'));
      }
      final observation = summary?.lastObservationAt;
      if (!pending.contains('${plant.id}:observation') &&
          (observation == null || today.difference(observation).inDays >= 7)) {
        result.add(ActionSuggestion(
            plant: plant,
            actionType: 'observation',
            title: 'Faire un point sur la plante',
            reason: observation == null
                ? 'Ajoute une première observation, avec des notes ou une photo.'
                : 'Aucune observation depuis ${today.difference(observation).inDays} jours.'));
      }
    }
    return result;
  }
}
