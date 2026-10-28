class AppConfig {
  static const appVersion = '0.1.0+1';
  static const appName = 'GardenJournal';
  static const projectLabel = 'Tomates et orchidées';
  static const editionLabel = 'Démo jardin';
  static const buildId = 'demo';
  static const testerId = 'demo';
  static String get shortLabel => '$appName - $editionLabel';
  static String get buildLabel => editionLabel;
  static String get exportWatermark => '$appName $appVersion';
}
