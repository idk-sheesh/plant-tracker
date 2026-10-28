import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../../features/actions/domain/entities/plant_action.dart';
import '../../features/plants/domain/entities/plant.dart';
import '../config/app_config.dart';
import '../utils/app_utils.dart';

class ShareableExportService {
  static const _maxEmbeddedImageBytes = 12 * 1024 * 1024;
  static const _maxActionImages = 30;
  static final PdfColor _ink = PdfColor.fromHex('#142118');
  static final PdfColor _muted = PdfColor.fromHex('#657267');
  static final PdfColor _line = PdfColor.fromHex('#D9E4DC');
  static final PdfColor _green = PdfColor.fromHex('#1F7A3A');
  static final PdfColor _blue = PdfColor.fromHex('#1769AA');
  static final PdfColor _orange = PdfColor.fromHex('#D96D1F');
  static final PdfColor _purple = PdfColor.fromHex('#7B3FA3');

  static Future<void> exportPlantHistory(
    BuildContext context,
    Plant plant,
    List<PlantAction> actions,
  ) async {
    try {
      final bytes = await buildPlantHistoryPdf(plant, actions);
      final dir = await getTemporaryDirectory();
      final safe = normalizeFileName(plant.name);
      final file = File(
        '${dir.path}/gardenjournal_${safe}_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/pdf')],
          text: 'Fiche GardenJournal - ${plant.name}',
          subject: 'GardenJournal - ${plant.name}',
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Erreur export: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  static Future<Uint8List> buildPlantHistoryPdf(
    Plant plant,
    List<PlantAction> actions,
  ) async {
    final sorted = [...actions]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final image = await _loadImage(plant.photoPath);
    final actionImages = await _loadActionImages(sorted);
    final pdf = pw.Document();
    final theme = await _pdfTheme();

    pdf.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(30, 28, 30, 28),
        footer: _footer,
        build: (_) => [
          _hero(plant, sorted, image),
          pw.SizedBox(height: 14),
          _summary(plant, sorted),
          pw.SizedBox(height: 12),
          _cultureAndActivity(plant, sorted),
          if (_keyEvents(sorted).isNotEmpty ||
              (plant.notes != null && plant.notes!.trim().isNotEmpty)) ...[
            pw.SizedBox(height: 12),
            _eventsAndNotesSection(sorted, plant.notes?.trim()),
          ],
          pw.SizedBox(height: 15),
          _sectionTitle('Historique detaille'),
          pw.SizedBox(height: 8),
          if (sorted.isEmpty)
            _empty('Aucune action enregistree pour cette plante.')
          else
            ...sorted.map((action) => _timelineItem(
                  action,
                  image: actionImages[action.id],
                  isLast: action == sorted.last,
                )),
        ],
      ),
    );

    return pdf.save();
  }

  static Future<pw.ThemeData> _pdfTheme() async {
    final baseData = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
    final boldData = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
    final italicData = await rootBundle.load('assets/fonts/Roboto-Italic.ttf');
    final boldItalicData =
        await rootBundle.load('assets/fonts/Roboto-BoldItalic.ttf');
    return pw.ThemeData.withFont(
      base: pw.Font.ttf(baseData),
      bold: pw.Font.ttf(boldData),
      italic: pw.Font.ttf(italicData),
      boldItalic: pw.Font.ttf(boldItalicData),
    );
  }

  static Future<pw.MemoryImage?> _loadImage(String? path) async {
    if (path == null || path.trim().isEmpty) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    if (await file.length() > _maxEmbeddedImageBytes) return null;
    try {
      return pw.MemoryImage(await file.readAsBytes());
    } on Exception catch (error) {
      debugPrint('Photo PDF ignorée (${error.runtimeType})');
      return null;
    }
  }

  static String normalizeFileName(String value) {
    final safe = value
        .trim()
        .replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return safe.isEmpty ? 'plante' : safe;
  }

  static Future<Map<String, pw.MemoryImage>> _loadActionImages(
    List<PlantAction> actions,
  ) async {
    final images = <String, pw.MemoryImage>{};
    for (final action in actions.take(_maxActionImages)) {
      if (action.photoPaths.isEmpty) continue;
      final image = await _loadImage(action.photoPaths.first);
      if (image != null) images[action.id] = image;
    }
    return images;
  }

  static pw.Widget _hero(
    Plant plant,
    List<PlantAction> actions,
    pw.MemoryImage? image,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(17),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#EAF6EC'),
        borderRadius: pw.BorderRadius.circular(18),
        border: pw.Border.all(color: PdfColor.fromHex('#C9E2CF')),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _photo(image),
          pw.SizedBox(width: 15),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  _pdfText(plant.name),
                  style: pw.TextStyle(
                    fontSize: 27,
                    fontWeight: pw.FontWeight.bold,
                    color: _ink,
                  ),
                ),
                if (plant.variety != null && plant.variety!.trim().isNotEmpty)
                  pw.Text(
                    _pdfText(plant.variety!.trim()),
                    style: pw.TextStyle(
                      fontSize: 13,
                      color: _muted,
                      fontStyle: pw.FontStyle.italic,
                    ),
                  ),
                pw.SizedBox(height: 9),
                pw.Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _badge(plant.locationLabel, _green),
                    _badge(plant.containerLabel, _orange),
                    _badge(plant.originLabel, _purple),
                    _badge(plant.cultureType, _blue),
                    if (plant.isHarvested) _badge('Recoltee', _orange),
                  ],
                ),
                pw.SizedBox(height: 11),
                pw.Text(
                  _pdfText(_intro(plant, actions)),
                  style:
                      pw.TextStyle(fontSize: 10, color: _muted, height: 1.35),
                ),
              ],
            ),
          ),
          pw.SizedBox(width: 12),
          _qr(plant),
        ],
      ),
    );
  }

  static pw.Widget _photo(pw.MemoryImage? image) {
    return pw.Container(
      width: 116,
      height: 116,
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(14),
        border: pw.Border.all(color: PdfColor.fromHex('#C5D8CB')),
      ),
      child: image == null
          ? pw.Center(
              child: pw.Text(
                'Grow\nTracker',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                  color: _green,
                ),
              ),
            )
          : pw.Padding(
              padding: const pw.EdgeInsets.all(3),
              child: pw.Image(image, fit: pw.BoxFit.cover),
            ),
    );
  }

  static pw.Widget _qr(Plant plant) {
    return pw.Container(
      width: 78,
      padding: const pw.EdgeInsets.all(7),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: PdfColor.fromHex('#C5D8CB')),
      ),
      child: pw.Column(
        children: [
          pw.BarcodeWidget(
            barcode: pw.Barcode.qrCode(),
            data: plant.qrCode,
            width: 58,
            height: 58,
            drawText: false,
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            'QR fiche',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 7.5, color: _muted),
          ),
        ],
      ),
    );
  }

  static pw.Widget _summary(Plant plant, List<PlantAction> actions) {
    final harvest = _firstWhere(actions, (a) => a.actionType == 'recolte');
    final phAverage = _average(
      actions.where((a) => !a.phNA && a.ph != null).map((a) => a.ph!),
    );
    final tdsAverage = _average(
      actions.where((a) => !a.tdsNA && a.tds != null).map((a) => a.tds!),
    );
    final wateringAverageDays = _averageWateringIntervalDays(actions);
    final cycleDays = (harvest?.timestamp ?? DateTime.now())
        .difference(plant.pottingDate)
        .inDays;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('Resume essentiel'),
        pw.SizedBox(height: 8),
        pw.Row(
          children: [
            _metric(
              'Cycle',
              '${cycleDays}j',
              harvest == null ? 'En cours' : 'Mise en pot > recolte',
              _blue,
            ),
            pw.SizedBox(width: 8),
            _metric(
              'Intervalle H2O',
              wateringAverageDays == null
                  ? '-'
                  : '${_formatDecimal(wateringAverageDays, 1)}j',
              wateringAverageDays == null
                  ? 'Pas assez de donnees'
                  : 'Moyenne entre arrosages',
              _blue,
            ),
            pw.SizedBox(width: 8),
            _metric(
              'pH moyen',
              phAverage == null ? '-' : _formatDecimal(phAverage, 2),
              phAverage == null ? 'Non renseigne' : 'Mesures valides',
              _green,
            ),
            pw.SizedBox(width: 8),
            _metric(
              'TDS moyen',
              tdsAverage == null ? '-' : '${_formatDecimal(tdsAverage, 0)} ppm',
              tdsAverage == null ? 'Non renseigne' : 'Mesures valides',
              _purple,
            ),
          ],
        ),
        if (plant.isHarvested || harvest != null) ...[
          pw.SizedBox(height: 8),
          _harvest(harvest),
        ],
      ],
    );
  }

  static pw.Widget _cultureAndActivity(Plant plant, List<PlantAction> actions) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: _panel(
            'Identite culture',
            [
              _fact('Mise en pot', AppUtils.formatDate(plant.pottingDate)),
              _fact('Origine', plant.originLabel),
              _fact('Emplacement', plant.locationLabel),
              _fact('Contenant', plant.containerLabel),
              if (plant.containerType != 'plein_sol' && plant.potSize != null)
                _fact('Pot', plant.potSize!),
              _fact('Culture', plant.cultureType),
            ],
          ),
        ),
        pw.SizedBox(width: 10),
        pw.Expanded(
          child: _panel(
            'Activite',
            [
              _fact('Actions', '${actions.length}'),
              _fact('Arrosages', '${_count(actions, 'arrosage')}'),
              _fact('Nutriments', '${_count(actions, 'nutriments')}'),
              _fact('Traitements', '${_count(actions, 'traitement')}'),
              _fact('Photos actions',
                  '${actions.fold<int>(0, (s, a) => s + a.photoPaths.length)}'),
              _fact('Export', AppUtils.formatDate(DateTime.now())),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _keyEventsPanel(List<PlantAction> actions) {
    final events = _keyEvents(actions);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('Dates cles'),
        pw.SizedBox(height: 8),
        pw.Wrap(
          spacing: 8,
          runSpacing: 8,
          children: events.map(_event).toList(),
        ),
      ],
    );
  }

  static pw.Widget _eventsAndNotesSection(
    List<PlantAction> actions,
    String? notes,
  ) {
    final events = _keyEvents(actions);
    final hasNotes = notes != null && notes.isNotEmpty;
    if (events.isEmpty && !hasNotes) return pw.SizedBox();

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (events.isNotEmpty) pw.Expanded(child: _keyEventsPanel(actions)),
        if (events.isNotEmpty && hasNotes) pw.SizedBox(width: 10),
        if (hasNotes) pw.Expanded(child: _notesPanel(notes)),
      ],
    );
  }

  static pw.Widget _notesPanel(String notes) {
    return _panel(
      'Notes importantes',
      [
        pw.Text(_pdfText(notes),
            style: pw.TextStyle(fontSize: 10.5, color: _ink, height: 1.35)),
      ],
      accent: _orange,
    );
  }

  static pw.Widget _timelineItem(
    PlantAction action, {
    pw.MemoryImage? image,
    required bool isLast,
  }) {
    final color = _actionColor(action.actionType);
    final details = _details(action);
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 7),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 46,
            child: pw.Text(
              AppUtils.formatDateShort(action.timestamp).substring(0, 5),
              style: pw.TextStyle(fontSize: 8.5, color: _muted),
              textAlign: pw.TextAlign.right,
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Column(
            children: [
              pw.Container(
                width: 9,
                height: 9,
                decoration: pw.BoxDecoration(
                  color: color,
                  shape: pw.BoxShape.circle,
                ),
              ),
              if (!isLast) pw.Container(width: 1, height: 46, color: _line),
            ],
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: pw.Container(
              padding: const pw.EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                borderRadius: pw.BorderRadius.circular(9),
                border: pw.Border.all(color: _line),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Row(
                          children: [
                            pw.Container(
                              width: 4,
                              height: 14,
                              color: color,
                            ),
                            pw.SizedBox(width: 6),
                            pw.Text(
                              AppUtils.actionLabel(action.actionType),
                              style: pw.TextStyle(
                                fontSize: 10.5,
                                fontWeight: pw.FontWeight.bold,
                                color: _ink,
                              ),
                            ),
                            if (action.isWateringCombined) ...[
                              pw.SizedBox(width: 5),
                              _miniBadge('+ arrosage', _blue),
                            ],
                            if (action.photoPaths.isNotEmpty) ...[
                              pw.SizedBox(width: 5),
                              _miniBadge(
                                  '${action.photoPaths.length} photo', _muted),
                            ],
                          ],
                        ),
                        if (details.isNotEmpty) ...[
                          pw.SizedBox(height: 5),
                          pw.Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children:
                                details.map((d) => _chip(d, color)).toList(),
                          ),
                        ],
                        if (action.notes != null &&
                            action.notes!.trim().isNotEmpty) ...[
                          pw.SizedBox(height: 5),
                          pw.Text(
                            _pdfText(action.notes!.trim()),
                            style: pw.TextStyle(
                                fontSize: 9.2, color: _muted, height: 1.22),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (image != null) ...[
                    pw.SizedBox(width: 8),
                    pw.Container(
                      width: 42,
                      height: 42,
                      padding: const pw.EdgeInsets.all(2),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.white,
                        borderRadius: pw.BorderRadius.circular(6),
                        border: pw.Border.all(color: _line),
                      ),
                      child: pw.Image(image, fit: pw.BoxFit.cover),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _sectionTitle(String text) {
    return pw.Row(
      children: [
        pw.Container(width: 4, height: 14, color: _green),
        pw.SizedBox(width: 7),
        pw.Text(
          text.toUpperCase(),
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
            color: _ink,
            letterSpacing: 1.1,
          ),
        ),
      ],
    );
  }

  static pw.Widget _metric(
      String label, String value, String sub, PdfColor color) {
    return pw.Expanded(
      child: pw.Container(
        height: 70,
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: _tint(color, 0.90),
          borderRadius: pw.BorderRadius.circular(12),
          border: pw.Border.all(color: _tint(color, 0.58)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label, style: pw.TextStyle(fontSize: 8.5, color: _muted)),
            pw.Text(
              value,
              maxLines: 1,
              style: pw.TextStyle(
                  fontSize: 18, fontWeight: pw.FontWeight.bold, color: _ink),
            ),
            pw.Text(sub,
                maxLines: 1, style: pw.TextStyle(fontSize: 7.5, color: _muted)),
          ],
        ),
      ),
    );
  }

  static pw.Widget _harvest(PlantAction? harvest) {
    final details = <String>[];
    if (harvest?.harvestWeightFresh != null) {
      details
          .add('Récolté ${_formatDecimal(harvest!.harvestWeightFresh!, 1)} g');
    }
    if (harvest?.harvestWeightStored != null) {
      details.add(
          'Conservé ${_formatDecimal(harvest!.harvestWeightStored!, 1)} g');
    }
    if (harvest?.harvestWeightWaste != null) {
      details
          .add('Écarté ${_formatDecimal(harvest!.harvestWeightWaste!, 1)} g');
    }
    final text = harvest == null
        ? 'Plante marquee recoltee - aucune action recolte datee.'
        : 'Recolte le ${AppUtils.formatDate(harvest.timestamp)}'
            '${details.isEmpty ? '' : ' - ${details.join(' - ')}'}';
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#FFF7E8'),
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: PdfColor.fromHex('#F1C483')),
      ),
      child: pw.Text(
        text,
        style: pw.TextStyle(
            fontSize: 10, color: _ink, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  static pw.Widget _panel(String title, List<pw.Widget> children,
      {PdfColor? accent}) {
    final c = accent ?? _green;
    return pw.Container(
      padding: const pw.EdgeInsets.all(13),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(14),
        border: pw.Border.all(color: _line),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
                fontSize: 11, fontWeight: pw.FontWeight.bold, color: c),
          ),
          pw.SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  static pw.Widget _fact(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 78,
            child: pw.Text(_pdfText(label),
                style: pw.TextStyle(fontSize: 9, color: _muted)),
          ),
          pw.Expanded(
            child: pw.Text(
              _pdfText(value),
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(
                  fontSize: 9.5, color: _ink, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _event(PlantAction action) {
    final color = _actionColor(action.actionType);
    return pw.Container(
      width: 118,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: _tint(color, 0.90),
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: _tint(color, 0.58)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            _pdfText(AppUtils.actionLabel(action.actionType)),
            style: pw.TextStyle(
                fontSize: 10, color: color, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 3),
          pw.Text(AppUtils.formatDate(action.timestamp),
              style: pw.TextStyle(fontSize: 9, color: _ink)),
        ],
      ),
    );
  }

  static pw.Widget _badge(String text, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: pw.BoxDecoration(
        color: _tint(color, 0.88),
        borderRadius: pw.BorderRadius.circular(20),
        border: pw.Border.all(color: _tint(color, 0.52)),
      ),
      child: pw.Text(
        _pdfText(text),
        style: pw.TextStyle(
            fontSize: 9, color: color, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  static pw.Widget _miniBadge(String text, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: pw.BoxDecoration(
        color: _tint(color, 0.90),
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Text(_pdfText(text),
          style: pw.TextStyle(fontSize: 7.5, color: color)),
    );
  }

  static pw.Widget _chip(String text, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#FAFBF7'),
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: _tint(color, 0.45)),
      ),
      child: pw.Text(_pdfText(text),
          style: pw.TextStyle(fontSize: 8.5, color: _ink)),
    );
  }

  static pw.Widget _empty(String message) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#FAFBF7'),
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: _line),
      ),
      child: pw.Text(_pdfText(message),
          style: pw.TextStyle(fontSize: 10, color: _muted)),
    );
  }

  static pw.Widget _footer(pw.Context ctx) {
    return pw.Column(
      children: [
        pw.Divider(color: _line),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              '${AppConfig.appName} ${AppConfig.editionLabel} - Projet : ${AppConfig.projectLabel}',
              style: pw.TextStyle(fontSize: 8.5, color: _muted),
            ),
            pw.Text(
              'Exporte le ${AppUtils.formatDateTime(DateTime.now())} - page ${ctx.pageNumber}/${ctx.pagesCount}',
              style: pw.TextStyle(fontSize: 8.5, color: _muted),
            ),
          ],
        ),
      ],
    );
  }

  static List<String> _details(PlantAction action) {
    final details = <String>[];
    if (action.quantity != null) {
      final q = action.quantity == action.quantity!.roundToDouble()
          ? action.quantity!.toStringAsFixed(0)
          : _formatDecimal(action.quantity!, 2);
      details.add(_formatQuantity(q, action.quantityUnit));
    }
    if (action.phNA) {
      details.add('pH N/A');
    } else if (action.ph != null) {
      details.add('pH ${_formatDecimal(action.ph!, 2)}');
    }
    if (action.tdsNA) {
      details.add('TDS N/A');
    } else if (action.tds != null) {
      details.add('TDS ${action.tds!.toStringAsFixed(0)} ppm');
    }
    if (action.productUsed != null && action.productUsed!.trim().isNotEmpty) {
      details.add(action.productUsed!.trim());
    }
    if (action.pruningType != null && action.pruningType!.trim().isNotEmpty) {
      details.add(action.pruningType!.trim());
    }
    if (action.harvestWeightFresh != null) {
      details.add('Récolté ${_formatDecimal(action.harvestWeightFresh!, 1)} g');
    }
    if (action.harvestWeightStored != null) {
      details
          .add('Conservé ${_formatDecimal(action.harvestWeightStored!, 1)} g');
    }
    if (action.harvestWeightWaste != null) {
      details.add('Écarté ${_formatDecimal(action.harvestWeightWaste!, 1)} g');
    }
    return details;
  }

  static String _formatQuantity(String quantity, String? unit) {
    final cleanUnit = unit?.trim();
    if (cleanUnit == null || cleanUnit.isEmpty) return quantity;
    return '$quantity $cleanUnit';
  }

  static String _intro(Plant plant, List<PlantAction> actions) {
    final first = actions.isEmpty ? plant.pottingDate : actions.last.timestamp;
    final last = actions.isEmpty ? DateTime.now() : actions.first.timestamp;
    return 'Fiche de suivi exportee pour partage. Periode couverte: '
        '${AppUtils.formatDate(first)} au ${AppUtils.formatDate(last)}. '
        'Donnees issues du carnet local GardenJournal.';
  }

  static double? _average(Iterable<double> values) {
    var count = 0;
    var sum = 0.0;
    for (final value in values) {
      sum += value;
      count++;
    }
    if (count == 0) return null;
    return sum / count;
  }

  static double? _averageWateringIntervalDays(List<PlantAction> actions) {
    final waterings = actions.where((a) {
      return a.actionType == 'arrosage' ||
          (a.actionType == 'nutriments' && a.isWateringCombined);
    }).toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    if (waterings.length < 2) return null;

    var totalHours = 0;
    for (var i = 1; i < waterings.length; i++) {
      totalHours += waterings[i]
          .timestamp
          .difference(waterings[i - 1].timestamp)
          .inHours
          .abs();
    }
    return (totalHours / 24) / (waterings.length - 1);
  }

  static List<PlantAction> _keyEvents(List<PlantAction> actions) {
    return actions
        .where((a) =>
            a.actionType == 'floraison' ||
            a.actionType == 'recolte' ||
            a.actionType == 'rempotage' ||
            a.actionType == 'bouturage')
        .take(4)
        .toList();
  }

  static PlantAction? _firstWhere(
    List<PlantAction> actions,
    bool Function(PlantAction action) test,
  ) {
    for (final action in actions) {
      if (test(action)) return action;
    }
    return null;
  }

  static int _count(List<PlantAction> actions, String type) {
    return actions.where((a) => a.actionType == type).length;
  }

  static String _formatDecimal(double value, int decimals) {
    return value.toStringAsFixed(decimals).replaceAll('.', ',');
  }

  static String _pdfText(String value) {
    final replacements = <String, String>{
      'œ': 'oe',
      'Œ': 'OE',
      'æ': 'ae',
      'Æ': 'AE',
      '’': "'",
      '‘': "'",
      '“': '"',
      '”': '"',
      '–': '-',
      '—': '-',
      '−': '-',
      '…': '...',
      '•': '-',
      '·': '-',
      '→': '>',
      '←': '<',
      '×': 'x',
      'µ': 'u',
      '\u00A0': ' ',
    };

    var text = value;
    replacements.forEach((from, to) {
      text = text.replaceAll(from, to);
    });

    final buffer = StringBuffer();
    for (final rune in text.runes) {
      if (rune == 10 ||
          rune == 13 ||
          rune == 9 ||
          (rune >= 32 && rune <= 255)) {
        buffer.writeCharCode(rune);
      } else {
        buffer.write(' ');
      }
    }

    return buffer
        .toString()
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r' *\n *'), '\n')
        .trim();
  }

  static PdfColor _actionColor(String type) {
    switch (type) {
      case 'arrosage':
        return _blue;
      case 'nutriments':
        return _purple;
      case 'traitement':
        return PdfColor.fromHex('#C7501B');
      case 'observation':
        return PdfColor.fromHex('#546E7A');
      case 'mesure':
        return PdfColor.fromHex('#1565C0');
      case 'taille':
        return PdfColor.fromHex('#D95D39');
      case 'floraison':
        return PdfColor.fromHex('#B23A8F');
      case 'rempotage':
        return PdfColor.fromHex('#795548');
      case 'bouturage':
        return PdfColor.fromHex('#00897B');
      case 'recolte':
        return _orange;
      default:
        return _green;
    }
  }

  static PdfColor _tint(PdfColor color, double whiteAmount) {
    final w = whiteAmount.clamp(0.0, 1.0);
    return PdfColor(
      color.red + (1 - color.red) * w,
      color.green + (1 - color.green) * w,
      color.blue + (1 - color.blue) * w,
    );
  }
}
