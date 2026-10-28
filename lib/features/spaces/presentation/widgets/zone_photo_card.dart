import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../core/widgets/photo_viewer_screen.dart';
import '../../../../core/widgets/safe_file_image.dart';
import '../../domain/entities/zone_photo.dart';
import '../providers/space_provider.dart';

class ZonePhotoCard extends StatefulWidget {
  final String zoneId;
  final Future<XFile?> Function(ImageSource)? pickImage;
  const ZonePhotoCard({super.key, required this.zoneId, this.pickImage});

  @override
  State<ZonePhotoCard> createState() => _ZonePhotoCardState();
}

class _ZonePhotoCardState extends State<ZonePhotoCard> {
  late Future<List<ZonePhoto>> _photos;
  bool _saving = false;
  int _visibleCount = 3;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant ZonePhotoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.zoneId != widget.zoneId) _reload();
  }

  void _reload() {
    _photos = context.read<SpaceProvider>().photosForZone(widget.zoneId);
  }

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Journal photo de l’espace',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const Text(
                    'Ajoute tes photos et une note pour garder une trace. '
                    'Elles restent dans le téléphone et dans ses sauvegardes.'),
                const SizedBox(height: 8),
                FilledButton.icon(
                    onPressed: _saving ? null : _add,
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: Text(
                        _saving ? 'Enregistrement…' : 'Ajouter une photo')),
                FutureBuilder<List<ZonePhoto>>(
                    future: _photos,
                    builder: (_, snapshot) {
                      if (snapshot.hasError) {
                        return Column(children: [
                          const Text('Impossible de charger les photos.'),
                          TextButton(
                              onPressed: () => setState(_reload),
                              child: const Text('Réessayer')),
                        ]);
                      }
                      if (!snapshot.hasData)
                        return const LinearProgressIndicator();
                      final photos = snapshot.data!;
                      if (photos.isEmpty)
                        return const Text(
                            'Aucune photo ajoutée pour le moment.');
                      return Column(
                          children: photos
                              .take(_visibleCount)
                              .map((photo) => Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          InkWell(
                                              onTap: () =>
                                                  PhotoViewerScreen.openGallery(
                                                      context,
                                                      photos
                                                          .map((item) =>
                                                              item.photoPath)
                                                          .toList(),
                                                      initialIndex:
                                                          photos.indexOf(photo),
                                                      semanticLabel:
                                                          'Photo de l’espace'),
                                              child: ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  child: SizedBox(
                                                      height: 180,
                                                      width: double.infinity,
                                                      child: SafeFileImage(
                                                          path: photo.photoPath,
                                                          fit: BoxFit.cover,
                                                          enableFullscreen:
                                                              false,
                                                          semanticLabel: 'Photo de l’espace')))),
                                          const SizedBox(height: 4),
                                          Text(DateFormat('dd/MM/yyyy HH:mm')
                                              .format(photo.capturedAt)),
                                          if (photo.caption != null)
                                            Text(photo.caption!),
                                        ]),
                                  ))
                              .toList());
                    }),
                FutureBuilder<List<ZonePhoto>>(
                    future: _photos,
                    builder: (_, snapshot) {
                      final count = snapshot.data?.length ?? 0;
                      return count > _visibleCount
                          ? TextButton(
                              onPressed: () =>
                                  setState(() => _visibleCount += 6),
                              child: Text(
                                  'Voir plus de photos (${count - _visibleCount})'))
                          : const SizedBox.shrink();
                    }),
              ],
            )),
      );

  Future<void> _add() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choisir dans la galerie'),
            onTap: () => Navigator.pop(sheetContext, ImageSource.gallery)),
        ListTile(
            leading: const Icon(Icons.camera_alt_outlined),
            title: const Text('Prendre une photo'),
            onTap: () => Navigator.pop(sheetContext, ImageSource.camera)),
      ])),
    );
    if (source == null || !mounted) return;
    setState(() => _saving = true);
    try {
      final selected = await (widget.pickImage?.call(source) ??
          ImagePicker().pickImage(source: source));
      if (selected == null || !mounted) return;
      final details = await showDialog<({String note, DateTime at})>(
          context: context, builder: (_) => const _PhotoDetailsDialog());
      if (details == null || !mounted) return;
      await context.read<SpaceProvider>().addZonePhoto(
          zoneId: widget.zoneId,
          sourcePath: selected.path,
          capturedAt: details.at,
          caption: details.note);
      if (mounted) setState(_reload);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Photo non enregistree. Verifie les autorisations et reessaie.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _PhotoDetailsDialog extends StatefulWidget {
  const _PhotoDetailsDialog();
  @override
  State<_PhotoDetailsDialog> createState() => _PhotoDetailsDialogState();
}

class _PhotoDetailsDialogState extends State<_PhotoDetailsDialog> {
  final _note = TextEditingController();
  DateTime _at = DateTime.now();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Ajouter au journal photo'),
        content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: _note,
              maxLines: 3,
              maxLength: 1000,
              decoration:
                  const InputDecoration(labelText: 'Note (facultative)')),
          TextButton.icon(
              icon: const Icon(Icons.calendar_today),
              label: Text(DateFormat('dd/MM/yyyy').format(_at)),
              onPressed: () async {
                final day = await showDatePicker(
                    context: context,
                    initialDate: _at,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now());
                if (day != null && mounted)
                  setState(() => _at = DateTime(
                      day.year, day.month, day.day, _at.hour, _at.minute));
              }),
          TextButton.icon(
              icon: const Icon(Icons.schedule),
              label: Text(DateFormat('HH:mm').format(_at)),
              onPressed: () async {
                final time = await showTimePicker(
                    context: context, initialTime: TimeOfDay.fromDateTime(_at));
                if (time != null && mounted)
                  setState(() => _at = DateTime(
                      _at.year, _at.month, _at.day, time.hour, time.minute));
              }),
        ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(context, (note: _note.text, at: _at)),
              child: const Text('Enregistrer')),
        ],
      );
}
