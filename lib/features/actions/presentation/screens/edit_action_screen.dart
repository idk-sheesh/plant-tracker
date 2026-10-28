import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../../domain/entities/plant_action.dart';
import '../providers/action_provider.dart';
import '../../../plants/presentation/providers/plant_provider.dart';
import '../../../../core/services/form_draft_store.dart';
import '../../../../core/services/photo_storage_service.dart';
import '../../../../core/utils/app_utils.dart';
import '../../../../core/utils/numeric_input_parser.dart';
import '../widgets/harvest_weight_fields.dart';
import '../../../../core/widgets/form_draft_banner.dart';
import '../../../../core/widgets/safe_file_image.dart';
import '../../../plants/presentation/screens/cutting_protocol_screen.dart';

class EditActionScreen extends StatefulWidget {
  final PlantAction action;
  const EditActionScreen({super.key, required this.action});
  @override
  State<EditActionScreen> createState() => _EditActionScreenState();
}

class _ValidationException implements Exception {
  final String message;
  const _ValidationException(this.message);
}

class _EditActionScreenState extends State<EditActionScreen> {
  static const _editableActionTypes = <String>[
    'arrosage',
    'nutriments',
    'traitement',
    'observation',
    'mesure',
    'taille',
    'rempotage',
    'floraison',
    'bouturage',
    'recolte',
    'mort',
  ];

  late TextEditingController _volumeCtrl;
  late TextEditingController _phCtrl;
  late TextEditingController _tdsCtrl;
  late TextEditingController _produitCtrl;
  late TextEditingController _notesCtrl;
  late TextEditingController _cuttingCtrl;
  late TextEditingController _harvestFreshCtrl;
  late TextEditingController _harvestStoredCtrl;
  late TextEditingController _harvestWasteCtrl;
  late String _unit;
  late String _pruningType;
  late String _actionType;
  late bool _phNA;
  late bool _tdsNA;
  late bool _isWateringCombined;
  late DateTime _dateTime;
  late List<String> _photos;
  final Set<String> _draftPhotos = {};
  String? _parentPlantId;
  String? _repotContainerType;
  bool _isLoading = false;
  late final FormDraftSession _draftSession;
  bool _draftRestored = false;

  @override
  void initState() {
    super.initState();
    final a = widget.action;
    _volumeCtrl = TextEditingController(text: a.quantity?.toString() ?? '');
    _phCtrl = TextEditingController(text: a.ph?.toString() ?? '');
    _tdsCtrl = TextEditingController(text: a.tds?.toString() ?? '');
    _produitCtrl = TextEditingController(text: a.productUsed ?? '');
    _notesCtrl = TextEditingController(text: a.notes ?? '');
    _cuttingCtrl = TextEditingController(text: a.cuttingNotes ?? '');
    _harvestFreshCtrl =
        TextEditingController(text: a.harvestWeightFresh?.toString() ?? '');
    _harvestStoredCtrl =
        TextEditingController(text: a.harvestWeightStored?.toString() ?? '');
    _harvestWasteCtrl =
        TextEditingController(text: a.harvestWeightWaste?.toString() ?? '');
    _unit = a.quantityUnit ?? 'L';
    _pruningType = AppUtils.pruningTypes.contains(a.pruningType)
        ? a.pruningType!
        : AppUtils.pruningTypes.first;
    _actionType = a.actionType;
    final units = _unitsFor(_actionType);
    if (units.isNotEmpty && !units.contains(_unit)) _unit = units.first;
    _phNA = a.phNA;
    _tdsNA = a.tdsNA;
    _dateTime = a.timestamp;
    _parentPlantId = a.parentPlantId;
    _repotContainerType = a.repotContainerType;
    _isWateringCombined = a.isWateringCombined;
    _photos = List<String>.from(a.photoPaths); // copie mutable
    _draftSession = FormDraftSession(
      key: 'action-edit-${widget.action.id}',
      snapshot: _draftSnapshot,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreDraft());
  }

  @override
  void dispose() {
    _draftSession.dispose();
    _volumeCtrl.dispose();
    _phCtrl.dispose();
    _tdsCtrl.dispose();
    _produitCtrl.dispose();
    _notesCtrl.dispose();
    _cuttingCtrl.dispose();
    _harvestFreshCtrl.dispose();
    _harvestStoredCtrl.dispose();
    _harvestWasteCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic> _draftSnapshot() => {
        'version': 1,
        'actionType': _actionType,
        'volume': _volumeCtrl.text,
        'ph': _phCtrl.text,
        'tds': _tdsCtrl.text,
        'product': _produitCtrl.text,
        'notes': _notesCtrl.text,
        'cuttingNotes': _cuttingCtrl.text,
        'harvestFresh': _harvestFreshCtrl.text,
        'harvestStored': _harvestStoredCtrl.text,
        'harvestWaste': _harvestWasteCtrl.text,
        'unit': _unit,
        'pruningType': _pruningType,
        'phNA': _phNA,
        'tdsNA': _tdsNA,
        'wateringCombined': _isWateringCombined,
        'dateTime': _dateTime.toIso8601String(),
        'parentPlantId': _parentPlantId,
        'repotContainerType': _repotContainerType,
        'photos': List<String>.from(_photos),
        'draftPhotos': List<String>.from(_draftPhotos),
      };

  Future<void> _restoreDraft() async {
    final draft = await _draftSession.restore();
    if (!mounted) return;
    if (draft != null && draft['version'] == 1) {
      final restoredType = draft['actionType'];
      final restoredDate = DateTime.tryParse('${draft['dateTime'] ?? ''}');
      setState(() {
        if (restoredType is String &&
            (_editableActionTypes.contains(restoredType) ||
                restoredType == widget.action.actionType)) {
          _actionType = restoredType;
        }
        _volumeCtrl.text = draft['volume'] as String? ?? '';
        _phCtrl.text = draft['ph'] as String? ?? '';
        _tdsCtrl.text = draft['tds'] as String? ?? '';
        _produitCtrl.text = draft['product'] as String? ?? '';
        _notesCtrl.text = draft['notes'] as String? ?? '';
        _cuttingCtrl.text = draft['cuttingNotes'] as String? ?? '';
        _harvestFreshCtrl.text = draft['harvestFresh'] as String? ?? '';
        _harvestStoredCtrl.text = draft['harvestStored'] as String? ?? '';
        _harvestWasteCtrl.text = draft['harvestWaste'] as String? ?? '';
        _unit = draft['unit'] as String? ?? _unit;
        _pruningType = draft['pruningType'] as String? ?? _pruningType;
        _phNA = draft['phNA'] as bool? ?? _phNA;
        _tdsNA = draft['tdsNA'] as bool? ?? _tdsNA;
        _isWateringCombined =
            draft['wateringCombined'] as bool? ?? _isWateringCombined;
        if (restoredDate != null) _dateTime = restoredDate;
        _parentPlantId = draft['parentPlantId'] as String?;
        _repotContainerType = draft['repotContainerType'] as String?;
        _photos = (draft['photos'] as List?)
                ?.whereType<String>()
                .toList(growable: true) ??
            List<String>.from(widget.action.photoPaths);
        _draftPhotos
          ..clear()
          ..addAll((draft['draftPhotos'] as List?)?.whereType<String>() ?? []);
        _draftRestored = true;
      });
    }
    _draftSession.start();
  }

  Future<void> _cleanupDraftPhotos() async {
    try {
      await PhotoStorageService.deleteManagedFiles(_draftPhotos);
    } catch (error, stackTrace) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'gardenjournal actions',
        context: ErrorDescription('nettoyage des photos d’édition annulée'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = AppUtils.actionColor(_actionType);
    final label = AppUtils.actionLabel(_actionType);
    final availableTypes = _editableActionTypes.contains(_actionType)
        ? _editableActionTypes
        : <String>[_actionType, ..._editableActionTypes];

    return Scaffold(
      appBar: AppBar(
        title: Text('Modifier — $label'),
        actions: [
          IconButton(
            tooltip: 'Abandonner le brouillon',
            onPressed: _isLoading ? null : _discardDraft,
            icon: const Icon(Icons.delete_outline),
          ),
          TextButton(
              onPressed: _isLoading ? null : _save,
              child: const Text('Enregistrer',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)))
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        FormDraftBanner(restored: _draftRestored),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          key: const ValueKey('edit-action-type'),
          initialValue: _actionType,
          isExpanded: true,
          decoration:
              _deco("Type d'action", AppUtils.actionIcon(_actionType)).copyWith(
            fillColor: color.withValues(alpha: 0.08),
            prefixIcon: Icon(AppUtils.actionIcon(_actionType), color: color),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: color.withValues(alpha: 0.35)),
            ),
          ),
          items: availableTypes
              .map((type) => DropdownMenuItem(
                    value: type,
                    child: Text(
                      AppUtils.actionLabel(type),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ))
              .toList(),
          onChanged: _isLoading
              ? null
              : (type) {
                  if (type != null) _changeActionType(type);
                },
        ),
        const SizedBox(height: 16),

        // Date/heure
        InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(12),
            child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                    color: const Color(0xFFF1F8E9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE0E0E0))),
                child: Row(children: [
                  const Icon(Icons.event, color: Color(0xFF2E7D32), size: 20),
                  const SizedBox(width: 12),
                  Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Date / Heure',
                            style: TextStyle(
                                fontSize: 12, color: Color(0xFF757575))),
                        Text(AppUtils.formatDateTime(_dateTime),
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                      ]),
                  const Spacer(),
                  const Icon(Icons.edit_outlined,
                      color: Color(0xFF9E9E9E), size: 18),
                ]))),
        const SizedBox(height: 16),

        // Champs selon type
        _buildFields(),
        const SizedBox(height: 12),

        // Notes
        TextFormField(
            controller: _notesCtrl,
            maxLines: 3,
            decoration: _deco('Notes (optionnel)', Icons.notes)),
        const SizedBox(height: 16),

        // Section photos (avec ajout possible)
        _buildPhotoSection(),
        const SizedBox(height: 24),

        // Bouton save
        SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _save,
                icon: const Icon(Icons.check),
                label: const Text('Enregistrer les modifications'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    textStyle: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)))),
        const SizedBox(height: 32),
      ]),
    );
  }

  // ─── Photos (avec ajout dans l'édition) ───────────────────────────────────
  Future<void> _discardDraft() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Abandonner les modifications ?'),
        content: const Text(
          'La saisie non enregistrée et les nouvelles photos seront supprimées.',
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
    await _cleanupDraftPhotos();
    if (mounted) Navigator.pop(context);
  }

  Widget _buildPhotoSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('Photos',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF2E7D32),
                letterSpacing: 0.8)),
        const Spacer(),
        TextButton.icon(
            onPressed: _addPhoto,
            icon: const Icon(Icons.add_a_photo,
                size: 16, color: Color(0xFF2E7D32)),
            label: const Text('Ajouter',
                style: TextStyle(color: Color(0xFF2E7D32), fontSize: 12))),
      ]),
      const SizedBox(height: 8),
      if (_photos.isEmpty)
        GestureDetector(
            onTap: _addPhoto,
            child: Container(
                height: 80,
                decoration: BoxDecoration(
                    color: const Color(0xFFF1F8E9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: const Color(0xFF4CAF50),
                        width: 1.5,
                        style: BorderStyle.solid)),
                child: const Center(
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                      Icon(Icons.add_a_photo,
                          color: Color(0xFF4CAF50), size: 28),
                      SizedBox(height: 4),
                      Text('Ajouter une photo',
                          style: TextStyle(
                              color: Color(0xFF4CAF50), fontSize: 12)),
                    ]))))
      else
        SizedBox(
            height: 86,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              ..._photos.map((path) => Stack(children: [
                    Container(
                        margin: const EdgeInsets.only(right: 8),
                        width: 80,
                        height: 80,
                        child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SafeFileImage(
                              path: path,
                              fit: BoxFit.cover,
                              semanticLabel: 'Photo brouillon de l’action',
                            ))),
                    Positioned(
                        top: 0,
                        right: 8,
                        child: IconButton.filled(
                          tooltip: 'Retirer la photo',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _removePhoto(path),
                          icon: const Icon(Icons.close, size: 16),
                        )),
                  ])),
              GestureDetector(
                  onTap: _addPhoto,
                  child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                          color: const Color(0xFFF1F8E9),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: const Color(0xFF4CAF50), width: 2)),
                      child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add, color: Color(0xFF4CAF50), size: 28),
                            Text('+',
                                style: TextStyle(
                                    color: Color(0xFF4CAF50), fontSize: 10)),
                          ]))),
            ])),
    ]);
  }

  // ─── Champs selon type ────────────────────────────────────────────────────
  void _changeActionType(String type) {
    if (type == _actionType) return;
    setState(() {
      _actionType = type;
      final units = _unitsFor(type);
      if (units.isNotEmpty && !units.contains(_unit)) _unit = units.first;
    });
  }

  List<String> _unitsFor(String type) {
    switch (type) {
      case 'arrosage':
        return const ['mL', 'L', 'gal'];
      case 'nutriments':
        return const ['mL', 'L', 'g', 'oz'];
      case 'traitement':
        return const ['mL/L', 'mL', 'g/L', 'g'];
      case 'rempotage':
        return const ['L', 'gal'];
      case 'bouturage':
        return const ['unité'];
      default:
        return const [];
    }
  }

  Widget _buildFields() {
    switch (_actionType) {
      case 'arrosage':
        return Column(children: [
          _qtyRow(['mL', 'L', 'gal'], _volumeCtrl),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _phField()),
            const SizedBox(width: 12),
            Expanded(child: _tdsField())
          ]),
        ]);
      case 'nutriments':
        return Column(children: [
          TextFormField(
              controller: _produitCtrl,
              decoration: _deco('Produit / Engrais', Icons.science_outlined)),
          const SizedBox(height: 12),
          _qtyRow(['mL', 'L', 'g', 'oz'], _volumeCtrl),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _phField()),
            const SizedBox(width: 12),
            Expanded(child: _tdsField())
          ]),
          const SizedBox(height: 12),
          _wateringCombinedToggle(),
        ]);
      case 'traitement':
        return Column(children: [
          TextFormField(
              controller: _produitCtrl,
              decoration: _deco('Produit utilise', Icons.healing_outlined)),
          const SizedBox(height: 12),
          _qtyRow(['mL/L', 'mL', 'g/L', 'g'], _volumeCtrl),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _phField()),
            const SizedBox(width: 12),
            Expanded(child: _tdsField())
          ]),
        ]);
      case 'mesure':
        return Row(children: [
          Expanded(child: _phField()),
          const SizedBox(width: 12),
          Expanded(child: _tdsField())
        ]);
      case 'taille':
        return DropdownButtonFormField<String>(
            initialValue: AppUtils.pruningTypes.contains(_pruningType)
                ? _pruningType
                : AppUtils.pruningTypes.first,
            decoration: _deco('Type de taille', Icons.content_cut),
            items: AppUtils.pruningTypes
                .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                .toList(),
            onChanged: (v) => setState(() => _pruningType = v!));
      case 'rempotage':
        final isFullGround = _repotContainerType == 'plein_sol';
        return Column(children: [
          if (isFullGround)
            _fullGroundPotInfo()
          else ...[
            TextFormField(
                controller: _produitCtrl,
                decoration: _deco('Taille du pot', Icons.yard_outlined)),
            const SizedBox(height: 12),
          ],
          DropdownButtonFormField<String>(
              initialValue: const ['pot', 'pot_tissu', 'plein_sol']
                      .contains(_repotContainerType)
                  ? _repotContainerType
                  : null,
              decoration:
                  _deco('Type de contenant', Icons.move_to_inbox_outlined),
              items: const [
                DropdownMenuItem(value: null, child: Text('Non renseigné')),
                DropdownMenuItem(value: 'pot', child: Text('Pot classique')),
                DropdownMenuItem(value: 'pot_tissu', child: Text('Pot tissu')),
                DropdownMenuItem(value: 'plein_sol', child: Text('Plein sol')),
              ],
              onChanged: (value) => setState(() {
                    _repotContainerType = value;
                    if (value == 'plein_sol') {
                      _produitCtrl.clear();
                    } else if (_produitCtrl.text.trim().isEmpty) {
                      _produitCtrl.text = '5L';
                    }
                  })),
          const SizedBox(height: 12),
          _qtyRow(['L', 'gal'], _volumeCtrl),
        ]);
      case 'bouturage':
        final plants = context
            .read<PlantProvider>()
            .allPlants
            .where((p) => p.id != widget.action.plantId)
            .toList();
        return Column(children: [
          GardenCuttingProtocolButton(
            startDate: _dateTime,
            cuttingCountProvider: _cuttingCuttingCount,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
              initialValue: _parentPlantId,
              decoration: _deco('Plante source (optionnel)', Icons.eco),
              items: [
                const DropdownMenuItem(value: null, child: Text('Aucune')),
                ...plants.map((p) => DropdownMenuItem(
                    value: p.id,
                    child: Text(p.name, overflow: TextOverflow.ellipsis)))
              ],
              onChanged: (v) => setState(() => _parentPlantId = v)),
          const SizedBox(height: 12),
          TextFormField(
              controller: _cuttingCtrl,
              decoration: _deco('Notes bouturage', Icons.notes)),
          const SizedBox(height: 12),
          _qtyRow(['unité'], _volumeCtrl),
        ]);
      case 'recolte':
        return _recolteFields();
      default:
        return const SizedBox.shrink();
    }
  }

  int? _cuttingCuttingCount() {
    final value = double.tryParse(_volumeCtrl.text.trim().replaceAll(',', '.'));
    if (value == null || value <= 0 || value != value.roundToDouble()) {
      return null;
    }
    return value.toInt();
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

  Widget _recolteFields() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Poids de recolte',
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2E7D32),
              letterSpacing: 0.8)),
      const SizedBox(height: 10),
      HarvestWeightFields(
        wetController: _harvestFreshCtrl,
        dryController: _harvestStoredCtrl,
        wasteController: _harvestWasteCtrl,
        decorationBuilder: _deco,
        helperText: 'Laissez vide si le poids n’est pas encore renseigné.',
      ),
    ]);
  }

  Widget _wateringCombinedToggle() {
    return InkWell(
        onTap: () => setState(() => _isWateringCombined = !_isWateringCombined),
        child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
                color: _isWateringCombined
                    ? const Color(0xFF29B6F6).withValues(alpha: 0.12)
                    : const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: _isWateringCombined
                        ? const Color(0xFF29B6F6)
                        : const Color(0xFFE0E0E0))),
            child: Row(children: [
              Icon(Icons.water_drop,
                  color: _isWateringCombined
                      ? const Color(0xFF29B6F6)
                      : const Color(0xFF9E9E9E),
                  size: 20),
              const SizedBox(width: 10),
              Expanded(
                  child: Text('Combiné avec un arrosage',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: _isWateringCombined
                              ? const Color(0xFF29B6F6)
                              : const Color(0xFF424242)))),
              Checkbox(
                  value: _isWateringCombined,
                  onChanged: (v) => setState(() => _isWateringCombined = v!),
                  activeColor: const Color(0xFF29B6F6)),
            ])));
  }

  Widget _phField() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('pH',
            style: TextStyle(fontSize: 12, color: Color(0xFF757575))),
        const Spacer(),
        Transform.scale(
            scale: 0.75,
            child: Switch(
                value: _phNA,
                onChanged: (v) => setState(() {
                      _phNA = v;
                      if (v) _phCtrl.clear();
                    }),
                activeThumbColor: const Color(0xFF2E7D32))),
        const Text('N/A',
            style: TextStyle(fontSize: 10, color: Color(0xFF757575))),
      ]),
      TextFormField(
          controller: _phCtrl,
          enabled: !_phNA,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: _deco(_phNA ? 'N/A' : 'ex: 6.5', Icons.science).copyWith(
              fillColor:
                  _phNA ? const Color(0xFFEEEEEE) : const Color(0xFFF1F8E9))),
    ]);
  }

  Widget _tdsField() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('TDS (ppm)',
            style: TextStyle(fontSize: 12, color: Color(0xFF757575))),
        const Spacer(),
        Transform.scale(
            scale: 0.75,
            child: Switch(
                value: _tdsNA,
                onChanged: (v) => setState(() {
                      _tdsNA = v;
                      if (v) _tdsCtrl.clear();
                    }),
                activeThumbColor: const Color(0xFF2E7D32))),
        const Text('N/A',
            style: TextStyle(fontSize: 10, color: Color(0xFF757575))),
      ]),
      TextFormField(
          controller: _tdsCtrl,
          enabled: !_tdsNA,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: _deco(_tdsNA ? 'N/A' : 'ex: 800', Icons.water_drop)
              .copyWith(
                  fillColor: _tdsNA
                      ? const Color(0xFFEEEEEE)
                      : const Color(0xFFF1F8E9))),
    ]);
  }

  Widget _qtyRow(List<String> units, TextEditingController ctrl) {
    final v = units.contains(_unit) ? _unit : units.first;
    return Row(children: [
      Expanded(
          flex: 3,
          child: TextFormField(
              controller: ctrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: _deco('Quantité', Icons.straighten))),
      const SizedBox(width: 10),
      Expanded(
          flex: 2,
          child: DropdownButtonFormField<String>(
              key: ValueKey('edit-action-unit-$_actionType'),
              initialValue: v,
              decoration: _deco('Unité', Icons.label_outline),
              items: units
                  .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                  .toList(),
              onChanged: (u) => setState(() => _unit = u!))),
    ]);
  }

  InputDecoration _deco(String label, IconData icon) => InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: const Color(0xFF2E7D32), size: 20),
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

  Future<void> _pickDate() async {
    final d = await showDatePicker(
        context: context,
        initialDate: _dateTime,
        firstDate: DateTime(2000),
        lastDate: DateTime.now().add(const Duration(days: 1)),
        builder: (ctx, child) => Theme(
            data: Theme.of(ctx).copyWith(
                colorScheme:
                    const ColorScheme.light(primary: Color(0xFF2E7D32))),
            child: child!));
    if (d == null || !mounted) return;
    final t = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_dateTime),
        builder: (ctx, child) => Theme(
            data: Theme.of(ctx).copyWith(
                colorScheme:
                    const ColorScheme.light(primary: Color(0xFF2E7D32))),
            child: child!));
    if (t == null || !mounted) return;
    setState(
        () => _dateTime = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  Future<void> _addPhoto() async {
    showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 16),
              ListTile(
                  leading:
                      const Icon(Icons.camera_alt, color: Color(0xFF2E7D32)),
                  title: const Text('Prendre une photo'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickPhoto(ImageSource.camera);
                  }),
              ListTile(
                  leading:
                      const Icon(Icons.photo_library, color: Color(0xFF2E7D32)),
                  title: const Text('Galerie'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickPhoto(ImageSource.gallery);
                  }),
              const SizedBox(height: 16),
            ])));
  }

  Future<void> _pickPhoto(ImageSource src) async {
    try {
      final p = await ImagePicker()
          .pickImage(source: src, imageQuality: 75, maxWidth: 1200);
      if (p == null) return;
      final storedPath = await PhotoStorageService.persistImage(
        p.path,
        bucket: 'actions',
      );
      if (mounted) {
        setState(() {
          _photos.add(storedPath);
          _draftPhotos.add(storedPath);
        });
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

  Future<void> _removePhoto(String photoPath) async {
    setState(() => _photos.remove(photoPath));
    if (_draftPhotos.remove(photoPath)) {
      try {
        await PhotoStorageService.deleteManagedFile(photoPath);
      } catch (error, stackTrace) {
        FlutterError.reportError(FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'gardenjournal actions',
          context: ErrorDescription('suppression d’une photo de brouillon'),
        ));
      }
    }
  }

  // ─── Helper : accepte virgule ET point comme séparateur décimal ──────────
  double? _parseOptionalNumber(
    TextEditingController controller,
    String label, {
    double? min,
    double? max,
  }) {
    try {
      return NumericInputParser.optionalBounded(
        controller.text,
        fieldLabel: label,
        minimum: min,
        maximum: max,
      );
    } on FormatException catch (error) {
      throw _ValidationException(error.message);
    }
  }

  // ─── SAVE ─────────────────────────────────────────────────────────────────
  Future<void> _save() async {
    setState(() => _isLoading = true);
    try {
      final hasSolutionValues = const {
        'arrosage',
        'nutriments',
        'traitement',
        'mesure',
      }.contains(_actionType);
      final hasQuantity = const {
        'arrosage',
        'nutriments',
        'traitement',
        'rempotage',
        'bouturage',
      }.contains(_actionType);
      final hasProduct = const {
        'nutriments',
        'traitement',
        'rempotage',
      }.contains(_actionType);

      // pH — null explicite si le type ne l'utilise pas, si vide ou si N/A.
      final double? ph = !hasSolutionValues || _phNA
          ? null
          : _parseOptionalNumber(_phCtrl, 'pH', min: 3.5, max: 9.0);

      // TDS
      final double? tds = !hasSolutionValues || _tdsNA
          ? null
          : _parseOptionalNumber(_tdsCtrl, 'TDS', min: 0, max: 5000);

      // Quantité
      final double? qty = hasQuantity
          ? _parseOptionalNumber(_volumeCtrl, 'Quantite', min: 0)
          : null;
      final isHarvest = _actionType == 'recolte';
      final harvestFresh = isHarvest
          ? _parseHarvestWeight(_harvestFreshCtrl, 'Poids récolté')
          : null;
      final harvestStored = isHarvest
          ? _parseHarvestWeight(_harvestStoredCtrl, 'Poids conservé')
          : null;
      final harvestWaste = isHarvest
          ? _parseHarvestWeight(_harvestWasteCtrl, 'Poids écarté')
          : null;

      if (_actionType == 'bouturage' &&
          qty != null &&
          qty != qty.roundToDouble()) {
        throw const _ValidationException(
          'Nombre de boutures invalide: utilisez un nombre entier',
        );
      }

      // Produit
      String? produit = hasProduct && _produitCtrl.text.trim().isNotEmpty
          ? _produitCtrl.text.trim()
          : null;
      if (_actionType == 'rempotage' && _repotContainerType == 'plein_sol') {
        produit = null;
      }

      // Notes bouturage
      final String? cuttingNotes =
          _actionType == 'bouturage' && _cuttingCtrl.text.trim().isNotEmpty
              ? _cuttingCtrl.text.trim()
              : null;

      // Notes générales
      final String? notes =
          _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : null;

      // On reconstruit l'objet complet plutôt que d'utiliser copyWith
      // pour éviter le problème null vs "non fourni"
      final updated = PlantAction(
        id: widget.action.id,
        plantId: widget.action.plantId,
        actionType: _actionType,
        createdAt: widget.action.createdAt,
        timestamp: _dateTime,
        quantity: qty,
        quantityUnit: hasQuantity && _actionType != 'bouturage' ? _unit : null,
        ph: ph,
        phNA: hasSolutionValues && _phNA,
        tds: tds,
        tdsNA: hasSolutionValues && _tdsNA,
        productUsed: produit,
        pruningType: _actionType == 'taille' ? _pruningType : null,
        notes: notes,
        parentPlantId: _actionType == 'bouturage' ? _parentPlantId : null,
        cuttingNotes: cuttingNotes,
        repotContainerType:
            _actionType == 'rempotage' ? _repotContainerType : null,
        isWateringCombined: _actionType == 'nutriments' && _isWateringCombined,
        photoPaths: _photos,
        harvestWeightFresh: harvestFresh,
        harvestWeightStored: harvestStored,
        harvestWeightWaste: harvestWaste,
        status: widget.action.status,
        completedAt: widget.action.completedAt,
      );

      await context.read<ActionProvider>().updateAction(updated);
      if (mounted) await context.read<PlantProvider>().loadPlants();
      await _draftSession.clear();
      _draftPhotos.clear();
      if (mounted) Navigator.pop(context);
    } on _ValidationException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  double? _parseHarvestWeight(
    TextEditingController controller,
    String label,
  ) {
    try {
      return NumericInputParser.optionalNonNegative(
        controller.text,
        fieldLabel: label,
      );
    } on FormatException catch (error) {
      throw _ValidationException(error.message);
    }
  }
}
