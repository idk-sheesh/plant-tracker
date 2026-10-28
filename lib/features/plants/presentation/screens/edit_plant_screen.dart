import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../../domain/entities/plant.dart';
import '../providers/plant_provider.dart';
import '../../../groups/presentation/providers/group_provider.dart';
import '../../../spaces/presentation/providers/space_provider.dart';
import '../../../../core/services/form_draft_store.dart';
import '../../../../core/services/photo_storage_service.dart';
import '../../../../core/widgets/form_draft_banner.dart';
import '../../../../core/widgets/safe_file_image.dart';
import '../../../../core/utils/app_utils.dart';
import '../widgets/watering_reminder_field.dart';

class EditPlantScreen extends StatefulWidget {
  final Plant plant;
  const EditPlantScreen({super.key, required this.plant});
  @override
  State<EditPlantScreen> createState() => _EditPlantScreenState();
}

class _EditPlantScreenState extends State<EditPlantScreen> {
  final _fk = GlobalKey<FormState>();
  late TextEditingController _nameCtrl, _varCtrl, _notesCtrl;
  late TextEditingController _specimenCtrl;
  bool? _wateringReminder;
  late String? _potSize;
  late String _culture, _location, _container, _origin;
  late DateTime _date;
  String? _groupId, _photo;
  bool _loading = false;
  late final FormDraftSession _draftSession;
  bool _draftRestored = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.plant.name);
    _varCtrl = TextEditingController(text: widget.plant.variety ?? '');
    _specimenCtrl =
        TextEditingController(text: widget.plant.observationCode ?? '');
    _wateringReminder = widget.plant.wateringReminder;
    _notesCtrl = TextEditingController(text: widget.plant.notes ?? '');
    _culture = widget.plant.cultureType;
    _location = widget.plant.location;
    _container = widget.plant.containerType;
    _potSize = _container == 'plein_sol'
        ? null
        : (widget.plant.potSize ?? AppUtils.potSizes.first);
    _origin = widget.plant.origin;
    _date = widget.plant.pottingDate;
    _groupId = widget.plant.groupId;
    _photo = widget.plant.photoPath;
    _draftSession = FormDraftSession(
      key: 'plant-edit-${widget.plant.id}',
      snapshot: _draftSnapshot,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreDraft());
  }

  @override
  void dispose() {
    _draftSession.dispose();
    _nameCtrl.dispose();
    _varCtrl.dispose();
    _specimenCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic> _draftSnapshot() => {
        'version': 1,
        'name': _nameCtrl.text,
        'variety': _varCtrl.text,
        'observationCode': _specimenCtrl.text,
        'wateringReminder': _wateringReminder,
        'notes': _notesCtrl.text,
        'date': _date.toIso8601String(),
        'culture': _culture,
        'potSize': _potSize,
        'location': _location,
        'container': _container,
        'origin': _origin,
        'groupId': _groupId,
        'photo': _photo,
      };

  Future<void> _restoreDraft() async {
    final draft = await _draftSession.restore();
    if (!mounted) return;
    if (draft != null && draft['version'] == 1) {
      final restoredDate = DateTime.tryParse('${draft['date'] ?? ''}');
      setState(() {
        _nameCtrl.text = draft['name'] as String? ?? _nameCtrl.text;
        _varCtrl.text = draft['variety'] as String? ?? _varCtrl.text;
        _specimenCtrl.text =
            draft['observationCode'] as String? ?? _specimenCtrl.text;
        if (draft.containsKey('wateringReminder')) {
          _wateringReminder = draft['wateringReminder'] as bool?;
        }
        _notesCtrl.text = draft['notes'] as String? ?? _notesCtrl.text;
        if (restoredDate != null) _date = restoredDate;
        _culture = draft['culture'] as String? ?? _culture;
        _potSize = draft['potSize'] as String?;
        _location = draft['location'] as String? ?? _location;
        _container = draft['container'] as String? ?? _container;
        _origin = draft['origin'] as String? ?? _origin;
        _groupId = draft['groupId'] as String?;
        _photo = draft['photo'] as String?;
        _draftRestored = true;
      });
    }
    _draftSession.start();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Modifier la plante'), actions: [
          IconButton(
            tooltip: 'Abandonner le brouillon',
            onPressed: _loading ? null : _discardDraft,
            icon: const Icon(Icons.delete_outline),
          ),
          TextButton(
              onPressed: _loading ? null : _save,
              child: const Text('Enregistrer',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)))
        ]),
        body: Form(
            key: _fk,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              FormDraftBanner(restored: _draftRestored),
              const SizedBox(height: 16),
              _photoSection(),
              const SizedBox(height: 20),
              _tf(_nameCtrl, 'Nom *', Icons.eco,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Obligatoire' : null),
              const SizedBox(height: 12),
              _tf(_varCtrl, 'Espèce / variété', Icons.grass),
              const SizedBox(height: 12),
              _tf(_specimenCtrl, 'Repère de plante (ex. P01, P02…)',
                  Icons.science_outlined),
              const SizedBox(height: 16),
              _sectionTitle('Emplacement'),
              _locationRow(),
              const SizedBox(height: 12),
              _containerRow(),
              WateringReminderField(
                location: _location,
                containerType: _container,
                value: _wateringReminder,
                onChanged: (v) => setState(() => _wateringReminder = v),
              ),
              const SizedBox(height: 12),
              _sectionTitle('Origine'),
              _originRow(),
              const SizedBox(height: 16),
              _sectionTitle('Culture'),
              _datePicker(),
              const SizedBox(height: 12),
              _dropdown(
                  'Type de culture',
                  Icons.science_outlined,
                  AppUtils.cultureTypes,
                  AppUtils.cultureTypes.contains(_culture)
                      ? _culture
                      : AppUtils.cultureTypes.first,
                  (v) => setState(() => _culture = v!)),
              const SizedBox(height: 12),
              _container == 'plein_sol'
                  ? _fullGroundPotInfo()
                  : _dropdown(
                      'Taille du pot',
                      Icons.yard_outlined,
                      AppUtils.potSizes,
                      AppUtils.potSizes.contains(_potSize)
                          ? _potSize!
                          : AppUtils.potSizes.first,
                      (v) => setState(() => _potSize = v)),
              const SizedBox(height: 12),
              _groupPicker(),
              const SizedBox(height: 12),
              _tf(_notesCtrl, 'Notes', Icons.notes, lines: 4),
              const SizedBox(height: 24),
              SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                      onPressed: _loading ? null : _save,
                      icon: const Icon(Icons.check),
                      label: const Text('Enregistrer'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2E7D32),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          textStyle: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)))),
              const SizedBox(height: 32),
            ])),
      );

  Future<void> _discardDraft() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Abandonner les modifications ?'),
        content: const Text(
          'La saisie non enregistrée et la nouvelle photo seront supprimées.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continuer la saisie'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Abandonner'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _draftSession.clear();
    if (_photo != widget.plant.photoPath) {
      _deleteDraftPhoto(_photo);
    }
    if (mounted) Navigator.pop(context);
  }

  Widget _sectionTitle(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(t,
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2E7D32),
              letterSpacing: 0.8)));

  Widget _photoSection() => Center(
      child: GestureDetector(
          onTap: _photoOpts,
          child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF4CAF50), width: 2)),
              child: _photo != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: SafeFileImage(
                          path: _photo!,
                          fit: BoxFit.cover,
                          enableFullscreen: false))
                  : const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                          Icon(Icons.add_a_photo,
                              size: 32, color: Color(0xFF4CAF50)),
                          SizedBox(height: 4),
                          Text('Photo',
                              style: TextStyle(
                                  color: Color(0xFF4CAF50), fontSize: 12))
                        ]))));

  Widget _locationRow() => Row(children: [
        _locChip('indoor', '🏠', 'Intérieur'),
        const SizedBox(width: 10),
        _locChip('outdoor', '☀️', 'Extérieur')
      ]);
  Widget _locChip(String v, String e, String l) {
    final sel = _location == v;
    return Expanded(
        child: GestureDetector(
            onTap: () => setState(() => _location = v),
            child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                    color:
                        sel ? const Color(0xFF2E7D32) : const Color(0xFFF1F8E9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: sel
                            ? const Color(0xFF2E7D32)
                            : const Color(0xFFE0E0E0),
                        width: sel ? 2 : 1)),
                child: Column(children: [
                  Text(e, style: const TextStyle(fontSize: 20)),
                  const SizedBox(height: 3),
                  Text(l,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: sel ? Colors.white : const Color(0xFF424242)))
                ]))));
  }

  Widget _originRow() => Row(children: [
        _origChip('seed', '🌱', 'Graine'),
        const SizedBox(width: 8),
        _origChip('cutting', '✂️', 'Bouture'),
        const SizedBox(width: 8),
        _origChip('unknown', '❓', 'Inconnu'),
      ]);

  Widget _origChip(String v, String emoji, String label) {
    final sel = _origin == v;
    return Expanded(
        child: GestureDetector(
            onTap: () => setState(() => _origin = v),
            child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                    color:
                        sel ? const Color(0xFF7B1FA2) : const Color(0xFFF3E5F5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: sel
                            ? const Color(0xFF7B1FA2)
                            : const Color(0xFFE1BEE7),
                        width: sel ? 2 : 1)),
                child: Column(children: [
                  Text(emoji, style: const TextStyle(fontSize: 18)),
                  const SizedBox(height: 2),
                  Text(label,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 10,
                          color: sel ? Colors.white : const Color(0xFF7B1FA2))),
                ]))));
  }

  Widget _containerRow() => Row(children: [
        _contChip('pot', '🪴', 'Pot'),
        const SizedBox(width: 8),
        _contChip('pot_tissu', '🧺', 'Pot tissu'),
        const SizedBox(width: 8),
        _contChip('plein_sol', '🌍', 'Plein sol')
      ]);
  Widget _contChip(String v, String e, String l) {
    final sel = _container == v;
    return Expanded(
        child: GestureDetector(
            onTap: () => setState(() {
                  _container = v;
                  _potSize ??= '5L';
                  if (v == 'plein_sol') _potSize = null;
                }),
            child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                    color:
                        sel ? const Color(0xFF2E7D32) : const Color(0xFFF1F8E9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: sel
                            ? const Color(0xFF2E7D32)
                            : const Color(0xFFE0E0E0),
                        width: sel ? 2 : 1)),
                child: Column(children: [
                  Text(e, style: const TextStyle(fontSize: 18)),
                  const SizedBox(height: 2),
                  Text(l,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 10,
                          color: sel ? Colors.white : const Color(0xFF424242)))
                ]))));
  }

  Widget _fullGroundPotInfo() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F8E9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFC8E6C9)),
        ),
        child: const Row(
          children: [
            Icon(Icons.grass, color: Color(0xFF2E7D32)),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Plein sol : aucun volume de pot à renseigner.',
                style: TextStyle(color: Color(0xFF33691E)),
              ),
            ),
          ],
        ),
      );

  Widget _datePicker() => InkWell(
      onTap: () async {
        final d = await showDatePicker(
            context: context,
            initialDate: _date,
            firstDate: DateTime(2000),
            lastDate: DateTime.now(),
            builder: (ctx, child) => Theme(
                data: Theme.of(ctx).copyWith(
                    colorScheme:
                        const ColorScheme.light(primary: Color(0xFF2E7D32))),
                child: child!));
        if (d != null) setState(() => _date = d);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
              color: const Color(0xFFF1F8E9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE0E0E0))),
          child: Row(children: [
            const Icon(Icons.calendar_today,
                color: Color(0xFF2E7D32), size: 20),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Date de mise en pot',
                  style: TextStyle(fontSize: 12, color: Color(0xFF757575))),
              Text(AppUtils.formatDate(_date),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w500))
            ]),
            const Spacer(),
            const Icon(Icons.edit_outlined, color: Color(0xFF9E9E9E), size: 18)
          ])));

  Widget _dropdown(String label, IconData icon, List<String> items,
          String value, Function(String?) onChange) =>
      DropdownButtonFormField<String>(
          initialValue: value,
          decoration: _deco(label, icon),
          items: items
              .map((s) => DropdownMenuItem(value: s, child: Text(s)))
              .toList(),
          onChanged: onChange);

  Widget _groupPicker() => Consumer<GroupProvider>(
      builder: (_, gp, __) => DropdownButtonFormField<String>(
          initialValue: _groupId,
          decoration: _deco('Groupe (optionnel)', Icons.folder_outlined),
          items: [
            const DropdownMenuItem(value: null, child: Text('Sans groupe')),
            ...gp.groups.map((g) => DropdownMenuItem(
                value: g.id,
                child: Row(children: [
                  CircleAvatar(radius: 6, backgroundColor: g.color),
                  const SizedBox(width: 8),
                  Text(g.name)
                ])))
          ],
          onChanged: (v) => setState(() => _groupId = v)));

  Widget _tf(TextEditingController c, String label, IconData icon,
          {String? Function(String?)? validator, int lines = 1}) =>
      TextFormField(
          controller: c,
          validator: validator,
          maxLines: lines,
          decoration: _deco(label, icon));

  InputDecoration _deco(String label, IconData icon) => InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: const Color(0xFF2E7D32)),
      filled: true,
      fillColor: const Color(0xFFF1F8E9),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2E7D32), width: 2)));

  Future<void> _photoOpts() => showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 16),
            ListTile(
                leading: const Icon(Icons.camera_alt, color: Color(0xFF2E7D32)),
                title: const Text('Prendre une photo'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImg(ImageSource.camera);
                }),
            ListTile(
                leading:
                    const Icon(Icons.photo_library, color: Color(0xFF2E7D32)),
                title: const Text('Galerie'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImg(ImageSource.gallery);
                }),
            if (_photo != null)
              ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: const Text('Supprimer',
                      style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(ctx);
                    final removed = _photo;
                    setState(() => _photo = null);
                    if (removed != widget.plant.photoPath) {
                      _deleteDraftPhoto(removed);
                    }
                  }),
            const SizedBox(height: 16)
          ])));

  Future<void> _pickImg(ImageSource src) async {
    try {
      final p = await ImagePicker()
          .pickImage(source: src, imageQuality: 80, maxWidth: 800);
      if (p == null) return;
      final storedPath = await PhotoStorageService.persistImage(
        p.path,
        bucket: 'plants',
      );
      if (!mounted) {
        _deleteDraftPhoto(storedPath);
        return;
      }
      final replaced = _photo;
      setState(() => _photo = storedPath);
      if (replaced != storedPath && replaced != widget.plant.photoPath) {
        _deleteDraftPhoto(replaced);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur photo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _save() async {
    if (!_fk.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await context.read<PlantProvider>().updatePlant(widget.plant.copyWith(
          name: _nameCtrl.text.trim(),
          variety: _varCtrl.text.trim().isEmpty ? null : _varCtrl.text.trim(),
          observationCode: _specimenCtrl.text.trim().isEmpty
              ? null
              : _specimenCtrl.text.trim(),
          wateringReminder: _wateringReminder,
          pottingDate: _date,
          cultureType: _culture,
          potSize: _container == 'plein_sol' ? null : _potSize,
          photoPath: _photo,
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          groupId: _groupId,
          location: _location,
          containerType: _container,
          origin: _origin));
      await context.read<SpaceProvider>().refresh();
      await _draftSession.clear();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _deleteDraftPhoto(String? photoPath) {
    if (photoPath == null) return;
    unawaited(
      PhotoStorageService.deleteManagedFile(photoPath).catchError(
        (Object error, StackTrace stackTrace) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stackTrace,
              library: 'gardenjournal plant form',
              context:
                  ErrorDescription('suppression d\u2019une photo brouillon'),
            ),
          );
          return false;
        },
      ),
    );
  }
}
