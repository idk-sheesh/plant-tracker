class NumericInputParser {
  const NumericInputParser._();

  static const double maximumHarvestWeightGrams = 1000000;

  /// Accepts French and dot decimals without interpreting ambiguous separators.
  static double? tryParse(String raw) {
    final value = double.tryParse(raw.trim().replaceAll(',', '.'));
    return value != null && value.isFinite ? value : null;
  }

  static double parse(String raw) {
    final value = tryParse(raw);
    if (value == null) throw const FormatException('Nombre invalide.');
    return value;
  }

  static double? optionalNonNegative(
    String raw, {
    required String fieldLabel,
    double maximum = maximumHarvestWeightGrams,
  }) {
    return optionalBounded(
      raw,
      fieldLabel: fieldLabel,
      minimum: 0,
      maximum: maximum,
    );
  }

  static double? optionalBounded(
    String raw, {
    required String fieldLabel,
    double? minimum,
    double? maximum,
  }) {
    final normalized = raw.trim().replaceAll(',', '.');
    if (normalized.isEmpty) return null;
    final value = tryParse(normalized);
    if (value == null || !value.isFinite) {
      throw FormatException('$fieldLabel doit être un nombre fini.');
    }
    if (minimum != null && value < minimum) {
      throw FormatException(
        '$fieldLabel doit être supérieur ou égal à $minimum.',
      );
    }
    if (maximum != null && value > maximum) {
      throw FormatException(
        '$fieldLabel doit être inférieur ou égal à $maximum.',
      );
    }
    return value;
  }

  static void validateNonNegative(
    double? value, {
    required String fieldLabel,
    double maximum = maximumHarvestWeightGrams,
  }) {
    if (value == null) return;
    if (!value.isFinite || value < 0 || value > maximum) {
      throw FormatException(
        '$fieldLabel doit être compris entre 0 et ${maximum.toStringAsFixed(0)}.',
      );
    }
  }
}
