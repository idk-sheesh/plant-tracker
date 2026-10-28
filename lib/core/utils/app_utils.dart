import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';

class AppUtils {
  /// Counts local calendar days, including days spanning a DST change.
  static int elapsedDays(DateTime start, {DateTime? end}) {
    final first = start.toLocal();
    final last = (end ?? DateTime.now()).toLocal();
    final days = DateTime.utc(last.year, last.month, last.day)
        .difference(DateTime.utc(first.year, first.month, first.day))
        .inDays;
    return days < 0 ? 0 : days;
  }

  static String floweringDuration(DateTime start, {DateTime? end}) {
    final days = elapsedDays(start, end: end);
    return 'Depuis $days jour${days == 1 ? '' : 's'}';
  }

  static String formatDate(DateTime date) =>
      DateFormat('dd/MM/yyyy').format(date);
  static String formatDateTime(DateTime date) =>
      DateFormat('dd/MM/yyyy HH:mm').format(date);
  static String formatDateShort(DateTime date) =>
      DateFormat('dd/MM/yyyy').format(date);

  static String timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inDays > 0) return 'il y a ${diff.inDays}j';
    if (diff.inHours > 0) return 'il y a ${diff.inHours}h';
    if (diff.inMinutes > 0) return 'il y a ${diff.inMinutes}min';
    return "a l'instant";
  }

  static Color actionColor(String type) {
    switch (type) {
      case 'arrosage':
        return AppTheme.watering;
      case 'nutriments':
        return AppTheme.nutrients;
      case 'traitement':
        return const Color(0xFFD84315);
      case 'observation':
        return const Color(0xFF607D8B);
      case 'mesure':
        return const Color(0xFF1976D2);
      case 'cycle':
        return const Color(0xFF2E7D32);
      case 'taille':
        return AppTheme.pruning;
      case 'floraison':
        return AppTheme.flowering;
      case 'rempotage':
        return AppTheme.repotting;
      case 'bouturage':
        return AppTheme.cutting;
      case 'recolte':
        return AppTheme.harvest;
      case 'mort':
        return const Color(0xFF616161);
      default:
        return AppTheme.primary;
    }
  }

  static IconData actionIcon(String type) {
    switch (type) {
      case 'arrosage':
        return Icons.water_drop;
      case 'nutriments':
        return Icons.science;
      case 'traitement':
        return Icons.healing_outlined;
      case 'observation':
        return Icons.visibility_outlined;
      case 'mesure':
        return Icons.speed_outlined;
      case 'cycle':
        return Icons.sync_alt;
      case 'taille':
        return Icons.content_cut;
      case 'floraison':
        return Icons.local_florist;
      case 'rempotage':
        return Icons.yard;
      case 'bouturage':
        return Icons.call_split;
      case 'recolte':
        return Icons.agriculture;
      case 'mort':
        return Icons.eco_outlined;
      default:
        return Icons.eco;
    }
  }

  static String actionLabel(String type) {
    switch (type) {
      case 'arrosage':
        return 'Arrosage';
      case 'nutriments':
        return 'Nutriments';
      case 'traitement':
        return 'Traitement';
      case 'observation':
        return 'Observation';
      case 'mesure':
        return 'Mesure';
      case 'cycle':
        return 'Cycle';
      case 'taille':
        return 'Taille / tuteurage';
      case 'floraison':
        return 'Floraison';
      case 'rempotage':
        return 'Rempotage';
      case 'bouturage':
        return 'Bouturage';
      case 'recolte':
        return 'Recolte';
      case 'mort':
        return 'Plante morte';
      default:
        return type;
    }
  }

  static List<String> get cultureTypes => [
        'Terre vivante',
        'Terreau pour tomates',
        'Hydro (DWC)',
        'Hydro (NFT)',
        'Hydro (Aeroponie)',
        'Écorces pour orchidées',
        'Tourbe',
        'Aquaponie',
        'Bio / Organique',
        'Autre',
      ];

  static List<String> get actionTypes => [
        'arrosage',
        'nutriments',
        'traitement',
        'observation',
        'taille',
        'rempotage',
        'mesure',
        'cycle',
      ];

  static List<String> get pruningTypes => [
        'Tuteurage',
        'Pincement',
        'Taille de formation',
        'Retrait des feuilles abîmées',
        'Retrait des gourmands',
        'Taille d’entretien',
        'Palissage',
        'Éclaircissage',
        'Autre',
      ];

  static List<String> get potSizes => [
        '0.5L',
        '1L',
        '2L',
        '3L',
        '5L',
        '7L',
        '10L',
        '15L',
        '20L',
        '25L',
        '30L',
        '50L',
        'Personnalise',
      ];

  static List<Color> get groupColors => [
        const Color(0xFF4CAF50),
        const Color(0xFF2196F3),
        const Color(0xFFE91E63),
        const Color(0xFFFF9800),
        const Color(0xFF9C27B0),
        const Color(0xFF00BCD4),
        const Color(0xFFFF5722),
        const Color(0xFF607D8B),
      ];
}
