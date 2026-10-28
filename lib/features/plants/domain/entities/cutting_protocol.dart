import 'package:flutter/foundation.dart';

@immutable
class CuttingProtocolStep {
  final int startDay;
  final int? endDay;
  final String title;
  final List<String> instructions;

  const CuttingProtocolStep({
    required this.startDay,
    this.endDay,
    required this.title,
    required this.instructions,
  });

  String get dayLabel {
    final lastDay = endDay;
    if (lastDay == null) return 'J$startDay+';
    if (lastDay == startDay) return 'J$startDay';
    return 'J$startDay–J$lastDay';
  }

  bool containsDay(int day) {
    if (day < startDay) return false;
    final lastDay = endDay;
    return lastDay == null || day <= lastDay;
  }
}

abstract final class GardenCuttingProtocol {
  static const String name = 'Jardin — dôme adapté';

  static const List<CuttingProtocolStep> steps = [
    CuttingProtocolStep(
      startDay: 0,
      endDay: 2,
      title: 'Stabilisation',
      instructions: [
        'Dôme fermé et aérations fermées.',
        'Ne pas toucher aux boutures.',
      ],
    ),
    CuttingProtocolStep(
      startDay: 3,
      endDay: 3,
      title: 'Première ouverture',
      instructions: [
        'Ouvrir le dôme pendant 30 secondes.',
        'Retirer l’excès d’eau ou de condensation.',
        'Ouvrir les aérations.',
      ],
    ),
    CuttingProtocolStep(
      startDay: 4,
      endDay: 4,
      title: 'Stabilisation',
      instructions: ['Ne rien changer.'],
    ),
    CuttingProtocolStep(
      startDay: 5,
      endDay: 5,
      title: 'Contrôle du substrat',
      instructions: [
        'Ouvrir le dôme pendant 30 secondes.',
        'Arroser seulement si le substrat sèche réellement.',
      ],
    ),
    CuttingProtocolStep(
      startDay: 6,
      endDay: 6,
      title: 'Observation',
      instructions: ['Observer uniquement, sans intervention.'],
    ),
    CuttingProtocolStep(
      startDay: 7,
      endDay: 7,
      title: 'Début de l’acclimatation',
      instructions: [
        'Ouvrir le dôme pendant 30 secondes.',
        'Laisser un côté légèrement entrouvert.',
      ],
    ),
    CuttingProtocolStep(
      startDay: 8,
      endDay: 10,
      title: 'Acclimatation progressive',
      instructions: [
        'Ouvrir le dôme 30 secondes chaque jour.',
        'Garder un côté entrouvert.',
        'Arroser seulement si nécessaire.',
      ],
    ),
    CuttingProtocolStep(
      startDay: 11,
      endDay: 11,
      title: 'Test sans dôme',
      instructions: [
        'Retirer le dôme pendant 10 minutes.',
        'Si plus de 20 % du lot flétrit, remettre le dôme et retenter le lendemain.',
      ],
    ),
    CuttingProtocolStep(
      startDay: 12,
      endDay: 13,
      title: 'Ouverture progressive',
      instructions: [
        'Augmenter progressivement l’ouverture si le lot reste stable.',
      ],
    ),
    CuttingProtocolStep(
      startDay: 14,
      title: 'Retrait définitif et repiquage',
      instructions: [
        'Retirer définitivement le dôme quand les boutures restent stables sans lui.',
        'Attendre des racines saines et visibles avant de repiquer.',
      ],
    ),
  ];

  static int dayNumber(DateTime startDate, DateTime referenceDate) {
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final reference = DateTime(
      referenceDate.year,
      referenceDate.month,
      referenceDate.day,
    );
    return reference.difference(start).inDays;
  }

  static CuttingProtocolStep? stepForDay(int day) {
    if (day < 0) return null;
    for (final step in steps) {
      if (step.containsDay(day)) return step;
    }
    return null;
  }

  static int? wiltedCuttingThreshold(int? cuttingCount) {
    if (cuttingCount == null || cuttingCount <= 0) return null;
    return (cuttingCount * 0.2).floor() + 1;
  }
}
