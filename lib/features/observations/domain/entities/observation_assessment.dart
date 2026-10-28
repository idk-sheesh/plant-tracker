import 'dart:convert';

class ObservationCriterion {
  final String key;
  final String label;
  final String section;
  final String? unit;
  final double maximum;
  const ObservationCriterion(this.key, this.label, this.section,
      {this.unit, this.maximum = 1000000});
}

const observationScores = <ObservationCriterion>[
  ObservationCriterion('vigor', 'Vigueur générale', 'Croissance'),
  ObservationCriterion('rooting', 'Enracinement', 'Croissance'),
  ObservationCriterion(
      'growth_regularity', 'Régularité de croissance', 'Croissance'),
  ObservationCriterion(
      'recovery', 'Reprise après taille / rempotage', 'Croissance'),
  ObservationCriterion('propagation', 'Facilité de bouturage', 'Croissance'),
  ObservationCriterion('branching', 'Ramification', 'Structure'),
  ObservationCriterion('stem_strength', 'Solidité des tiges', 'Structure'),
  ObservationCriterion(
      'internodes', 'Espacement des entre-nœuds adapté', 'Structure'),
  ObservationCriterion('shape', 'Port / forme recherchée', 'Structure'),
  ObservationCriterion('training', 'Facilité de conduite', 'Structure'),
  ObservationCriterion(
      'flowering_speed', 'Précocité de floraison', 'Floraison'),
  ObservationCriterion(
      'flowering_uniformity', 'Homogénéité de floraison', 'Floraison'),
  ObservationCriterion('growth_balance', 'Croissance équilibrée', 'Floraison'),
  ObservationCriterion('flower_density', 'Densité des fleurs', 'Floraison'),
  ObservationCriterion('flower_structure', 'Structure des fleurs', 'Floraison'),
  ObservationCriterion('fruit_quality', 'Qualité des fruits', 'Floraison'),
  ObservationCriterion(
      'aroma_intensity', 'Intensité aromatique', 'Arômes et aspect'),
  ObservationCriterion(
      'aroma_quality', 'Qualité aromatique recherchée', 'Arômes et aspect'),
  ObservationCriterion(
      'aroma_originality', 'Originalité aromatique', 'Arômes et aspect'),
  ObservationCriterion(
      'appearance', 'Aspect / couleurs recherchés', 'Arômes et aspect'),
  ObservationCriterion(
      'pest_resistance', 'Résistance aux ravageurs', 'Résistance'),
  ObservationCriterion(
      'disease_resistance', 'Résistance aux maladies', 'Résistance'),
  ObservationCriterion(
      'heat_tolerance', 'Tolérance à la chaleur', 'Résistance'),
  ObservationCriterion(
      'water_stress', 'Tolérance au stress hydrique', 'Résistance'),
  ObservationCriterion('stability', 'Stabilité observée', 'Résistance'),
  ObservationCriterion('yield', 'Rendement recherché', 'Récolte et bilan'),
  ObservationCriterion('picking', 'Facilité de cueillette', 'Récolte et bilan'),
  ObservationCriterion('storage', 'Tenue en conservation', 'Récolte et bilan'),
  ObservationCriterion(
      'aroma_retention', 'Conservation des arômes', 'Récolte et bilan'),
  ObservationCriterion('overall', 'Appréciation globale', 'Récolte et bilan'),
];

const observationMeasurements = <ObservationCriterion>[
  ObservationCriterion('height', 'Hauteur', 'Mesures',
      unit: 'cm', maximum: 10000),
  ObservationCriterion('width', 'Largeur', 'Mesures',
      unit: 'cm', maximum: 10000),
  ObservationCriterion('internode_cm', 'Entre-nœud moyen', 'Mesures',
      unit: 'cm', maximum: 1000),
  ObservationCriterion('growth_ratio', 'Facteur de croissance', 'Mesures',
      unit: '×', maximum: 100),
  ObservationCriterion('flowering_days', 'Durée de floraison', 'Mesures',
      unit: 'jours', maximum: 1000),
  ObservationCriterion('fresh_g', 'Poids récolté', 'Mesures', unit: 'g'),
  ObservationCriterion('stored_g', 'Poids conservé', 'Mesures', unit: 'g'),
  ObservationCriterion('waste_g', 'Poids écarté', 'Mesures', unit: 'g'),
];

const observationStages = <String, String>{
  'growth': 'Croissance',
  'flowering': 'Floraison',
  'harvest': 'Récolte',
  'stored': 'Après conservation',
};

const observationDecisions = <String, String>{
  'undecided': 'À décider',
  'watch': 'À revoir',
  'keep': 'À conserver',
  'discard': 'Non retenu',
};

class ObservationAssessment {
  final String id;
  final String plantId;
  final DateTime observedAt;
  final String stage;
  final Map<String, int> scores;
  final Map<String, double> measurements;
  final String? aromas;
  final String? notes;
  final String decision;
  final DateTime createdAt;

  ObservationAssessment({
    required this.id,
    required this.plantId,
    required this.observedAt,
    required this.stage,
    Map<String, int> scores = const {},
    Map<String, double> measurements = const {},
    this.aromas,
    this.notes,
    this.decision = 'undecided',
    required this.createdAt,
  })  : scores = Map.unmodifiable(scores),
        measurements = Map.unmodifiable(measurements);

  void validate() {
    if (id.trim().isEmpty ||
        plantId.trim().isEmpty ||
        !observationStages.containsKey(stage) ||
        !observationDecisions.containsKey(decision)) {
      throw const FormatException('Observation de plante invalide.');
    }
    final scoreKeys = observationScores.map((c) => c.key).toSet();
    for (final score in scores.entries) {
      if (!scoreKeys.contains(score.key) ||
          score.value < 1 ||
          score.value > 5) {
        throw const FormatException(
            'Les notes doivent être comprises entre 1 et 5.');
      }
    }
    final criteria = {for (final c in observationMeasurements) c.key: c};
    for (final measure in measurements.entries) {
      final criterion = criteria[measure.key];
      if (criterion == null ||
          !measure.value.isFinite ||
          measure.value < 0 ||
          measure.value > criterion.maximum) {
        throw const FormatException('Mesure de plante invalide.');
      }
    }
    if (scores.isEmpty &&
        measurements.isEmpty &&
        (aromas?.trim().isEmpty ?? true) &&
        (notes?.trim().isEmpty ?? true) &&
        decision == 'undecided') {
      throw const FormatException(
          'Renseigne au moins un critère, une mesure ou une note.');
    }
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'plant_id': plantId,
        'observed_at': observedAt.toIso8601String(),
        'stage': stage,
        'scores_json': jsonEncode(scores),
        'measurements_json': jsonEncode(measurements),
        'aromas': aromas,
        'notes': notes,
        'decision': decision,
        'created_at': createdAt.toIso8601String(),
      };

  factory ObservationAssessment.fromMap(Map<String, Object?> map) =>
      ObservationAssessment(
        id: map['id'] as String,
        plantId: map['plant_id'] as String,
        observedAt: DateTime.parse(map['observed_at'] as String),
        stage: map['stage'] as String,
        scores:
            (jsonDecode(map['scores_json'] as String) as Map<String, dynamic>)
                .map((key, value) => MapEntry(key, value as int)),
        measurements: (jsonDecode(map['measurements_json'] as String)
                as Map<String, dynamic>)
            .map((key, value) => MapEntry(key, (value as num).toDouble())),
        aromas: map['aromas'] as String?,
        notes: map['notes'] as String?,
        decision: map['decision'] as String,
        createdAt: DateTime.parse(map['created_at'] as String),
      );
}
