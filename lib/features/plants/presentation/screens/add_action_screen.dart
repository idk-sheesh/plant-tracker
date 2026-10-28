import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../../../actions/presentation/providers/action_provider.dart';
import '../../domain/entities/plant.dart';
import '../../presentation/providers/plant_provider.dart';
import '../../../../core/services/photo_storage_service.dart';
import '../../../../core/services/form_draft_store.dart';
import '../../../../core/utils/app_utils.dart';
import '../../../../core/utils/numeric_input_parser.dart';
import '../../../actions/presentation/widgets/harvest_weight_fields.dart';
import '../../../../core/widgets/form_draft_banner.dart';
import '../../../../core/widgets/safe_file_image.dart';
import '../../../spaces/presentation/providers/space_provider.dart';
import 'cutting_protocol_screen.dart';

class AddActionScreen extends StatefulWidget {
  final Plant plant;
  final DateTime? initialDate;
  final String? initialActionType;
  final FormDraftStore? draftStore;
  const AddActionScreen(
      {super.key,
      required this.plant,
      this.initialDate,
      this.initialActionType,
      this.draftStore});
  @override
  State<AddActionScreen> createState() => _AddActionScreenState();
}

class _ValidationException implements Exception {
  final String message;
  const _ValidationException(this.message);
}

class _AddActionScreenState extends State<AddActionScreen> {
  String _type = 'arrosage';

  final _volumeCtrl = TextEditingController();
  final _phCtrl = TextEditingController();
  final _tdsCtrl = TextEditingController();
  final _produitCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _cuttingCtrl = TextEditingController();
  final _harvestFreshCtrl = TextEditingController();
  final _harvestStoredCtrl = TextEditingController();
  final _harvestWasteCtrl = TextEditingController();

  String _unit = 'L';
  String _pruningType = 'Tuteurage';
  String _nutrientMode = 'Solution nutritive';
  String _treatmentTarget = 'Acariens';
  String _treatmentMethod = 'Foliaire';
  String _measureContext = 'Solution';
  bool _phNA = false;
  bool _tdsNA = false;
  bool _isWateringCombined = false;
  bool _isLoading = false;
  late DateTime _dateTime;
  String? _parentPlantId;
  // Rempotage: nouveau container_type (null = pas change)
  String? _newContainerType;
  final List<String> _photos = [];
  late final FormDraftSession _draftSession;
  bool _draftRestored = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialActionType != null &&
        AppUtils.actionTypes.contains(widget.initialActionType)) {
      _type = widget.initialActionType!;
    }
    _dateTime = widget.initialDate ?? DateTime.now();
    _draftSession = FormDraftSession(
      store: widget.draftStore,
      key:
          'action-add-${widget.plant.id}${widget.initialActionType == null ? '' : '-${widget.initialActionType}'}',
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
        'type': _type,
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
        'nutrientMode': _nutrientMode,
        'treatmentTarget': _treatmentTarget,
        'treatmentMethod': _treatmentMethod,
        'measureContext': _measureContext,
        'phNA': _phNA,
        'tdsNA': _tdsNA,
        'wateringCombined': _isWateringCombined,
        'dateTime': _dateTime.toIso8601String(),
        'parentPlantId': _parentPlantId,
        'newContainerType': _newContainerType,
        'photos': List<String>.from(_photos),
      };

  Future<void> _restoreDraft() async {
    final draft = await _draftSession.restore();
    if (!mounted) return;
    if (draft != null && draft['version'] == 1) {
      final restoredType = draft['type'];
      final restoredDate = DateTime.tryParse('${draft['dateTime'] ?? ''}');
      setState(() {
        if (restoredType is String &&
            (AppUtils.actionTypes.contains(restoredType) ||
                _isCycleType(restoredType))) {
          _type = restoredType;
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
        _nutrientMode = draft['nutrientMode'] as String? ?? _nutrientMode;
        _treatmentTarget =
            draft['treatmentTarget'] as String? ?? _treatmentTarget;
        _treatmentMethod =
            draft['treatmentMethod'] as String? ?? _treatmentMethod;
        _measureContext = draft['measureContext'] as String? ?? _measureContext;
        _phNA = draft['phNA'] as bool? ?? _phNA;
        _tdsNA = draft['tdsNA'] as bool? ?? _tdsNA;
        _isWateringCombined =
            draft['wateringCombined'] as bool? ?? _isWateringCombined;
        if (restoredDate != null) _dateTime = restoredDate;
        _parentPlantId = draft['parentPlantId'] as String?;
        _newContainerType = draft['newContainerType'] as String?;
        _photos
          ..clear()
          ..addAll(
            (draft['photos'] as List?)
                    ?.whereType<String>()
                    .toList(growable: false) ??
                const [],
          );
        _draftRestored = true;
      });
    }
    _draftSession.start();
  }

  Future<void> _cleanupDraftPhotos() async {
    try {
      await PhotoStorageService.deleteManagedFiles(_photos);
    } catch (error, stackTrace) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'gardenjournal actions',
        context: ErrorDescription('nettoyage des photos d’un brouillon'),
      ));
    }
  }

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

  @override
  Widget build(BuildContext context) {
    if (widget.plant.isDead || widget.plant.isHarvested) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.plant.name)),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 48, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'Le cycle de cette plante est terminé.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(
                  'Son historique reste consultable, mais aucune nouvelle action ne peut être ajoutée.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text('Ajouter - ${widget.plant.name}'),
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
        _typeGrid(),
        const SizedBox(height: 16),
        _datePicker(),
        if (_dateTime.isAfter(DateTime.now())) ...[
          const SizedBox(height: 8),
          _plannedBanner(),
        ],
        const SizedBox(height: 16),
        _buildFields(),
        const SizedBox(height: 12),
        _buildNotesField(),
        const SizedBox(height: 12),
        _buildPhotoSection(),
        const SizedBox(height: 24),
        _saveBtn(),
        const SizedBox(height: 32),
      ]),
    );
  }

  Future<void> _discardDraft() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Abandonner ce brouillon ?'),
        content: const Text(
          'La saisie et les photos ajoutées à cette action seront supprimées.',
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

  Widget _plannedBanner() => Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: const Color(0xFFFFF8E1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFFFE082))),
      child: const Row(children: [
        Icon(Icons.schedule, color: Color(0xFFF57C00), size: 18),
        SizedBox(width: 8),
        Expanded(
            child: Text(
                'Action planifiee: elle restera en attente avec rappel a l heure prevue.',
                style: TextStyle(fontSize: 12, color: Color(0xFF795548)))),
      ]));

  // --- Type selector --------------------------------------------------------
  Widget _typeGrid() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text("Type d'action",
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2E7D32),
              letterSpacing: 0.8)),
      const SizedBox(height: 10),
      GridView.builder(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 112,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1.05,
          ),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: AppUtils.actionTypes.length,
          itemBuilder: (context, index) {
            final t = AppUtils.actionTypes[index];
            final sel = _type == t || (t == 'cycle' && _isCycleType(_type));
            final displayType = t == 'cycle' && _isCycleType(_type) ? _type : t;
            final color = AppUtils.actionColor(displayType);
            return Semantics(
                button: true,
                selected: sel,
                label: AppUtils.actionLabel(displayType),
                child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      if (t == 'cycle') {
                        _openCycleSheet();
                        return;
                      }
                      setState(() {
                        _type = t;
                        _resetFields();
                      });
                    },
                    child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        decoration: BoxDecoration(
                            color: sel ? color : color.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color:
                                    sel ? color : color.withValues(alpha: 0.25),
                                width: sel ? 2 : 1)),
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(AppUtils.actionIcon(displayType),
                                  color: sel ? Colors.white : color, size: 20),
                              const SizedBox(height: 3),
                              Text(AppUtils.actionLabel(displayType),
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: sel ? Colors.white : color),
                                  textAlign: TextAlign.center,
                                  maxLines: 2),
                            ]))));
          }),
    ]);
  }

  bool _isCycleType(String type) =>
      type == 'floraison' ||
      type == 'bouturage' ||
      type == 'recolte' ||
      type == 'mort';

  Future<void> _openCycleSheet() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                    color: const Color(0xFFE0E0E0),
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 14),
            const Align(
                alignment: Alignment.centerLeft,
                child: Text('Cycle de culture',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
            const SizedBox(height: 8),
            const Align(
                alignment: Alignment.centerLeft,
                child: Text('Choisis uniquement l etape a enregistrer.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF757575)))),
            const SizedBox(height: 12),
            _cycleChoice(ctx, 'floraison', 'Passage floraison',
                'Debut ou changement de cycle lumineux'),
            _cycleChoice(ctx, 'bouturage', 'Bouturage',
                'Bouture creee ou reliee a une plante source'),
            _cycleChoice(
                ctx, 'recolte', 'Recolte', 'Fin de cycle et poids de recolte'),
            _cycleChoice(ctx, 'mort', 'Plante morte',
                'Fin du suivi actif sans supprimer les donnees'),
          ]),
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() {
        _type = selected;
        _resetFields();
      });
    }
  }

  Widget _cycleChoice(
    BuildContext ctx,
    String type,
    String title,
    String subtitle,
  ) {
    final color = AppUtils.actionColor(type);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(AppUtils.actionIcon(type), color: color)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.pop(ctx, type),
    );
  }

  void _resetFields() {
    _volumeCtrl.clear();
    _phCtrl.clear();
    _tdsCtrl.clear();
    _produitCtrl.clear();
    _cuttingCtrl.clear();
    _harvestFreshCtrl.clear();
    _harvestStoredCtrl.clear();
    _harvestWasteCtrl.clear();
    _phNA = false;
    _tdsNA = false;
    _isWateringCombined = false;
    _unit = 'L';
    _parentPlantId = null;
    _newContainerType = null;
    _nutrientMode = 'Solution nutritive';
    _treatmentTarget = 'Acariens';
    _treatmentMethod = 'Foliaire';
    _measureContext = 'Solution';
  }

  // --- Date picker ----------------------------------------------------------
  Widget _datePicker() {
    return InkWell(
      onTap: _pickDate,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
            color: const Color(0xFFF1F8E9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE0E0E0))),
        child: Row(children: [
          const Icon(Icons.event, color: Color(0xFF2E7D32), size: 20),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Date / Heure',
                style: TextStyle(fontSize: 12, color: Color(0xFF757575))),
            Text(AppUtils.formatDateTime(_dateTime),
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ]),
          const Spacer(),
          const Icon(Icons.edit_outlined, color: Color(0xFF9E9E9E), size: 18),
        ]),
      ),
    );
  }

  // --- Champs dynamiques ----------------------------------------------------
  Widget _buildFields() {
    switch (_type) {
      case 'arrosage':
        return _arrosageFields();
      case 'nutriments':
        return _nutrimentFields();
      case 'traitement':
        return _traitementFields();
      case 'observation':
        return _infoBox('', 'Observation',
            'Note libre, photo, symptome, vigueur, odeur ou changement visible.');
      case 'taille':
        return _tailleFields();
      case 'mesure':
        return _mesureFields();
      case 'floraison':
        return _infoBox('', 'Floraison',
            'Passage en floraison enregistre a la date selectionnee.');
      case 'rempotage':
        return _rempotageFields();
      case 'bouturage':
        return _bouturageFields();
      case 'recolte':
        return _recolteFields();
      case 'mort':
        return _infoBox(
          '',
          'Plante morte',
          'Cette action restera dans l’historique. La plante quittera les '
              'vues actives sans perdre sa fiche, ses photos ni ses données.',
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _arrosageFields() {
    return _section('Arrosage', [
      _qtyRow('Volume', ['mL', 'L', 'gal'], _volumeCtrl),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _phField()),
        const SizedBox(width: 12),
        Expanded(child: _tdsField()),
      ]),
    ]);
  }

  Widget _nutrimentFields() {
    return _section('Nutriments', [
      _selectField(
          label: 'Mode',
          icon: Icons.grass_outlined,
          value: _nutrientMode,
          values: const ['Solution nutritive', 'Top dress', 'Amendement sol'],
          onChanged: (v) => setState(() => _nutrientMode = v)),
      const SizedBox(height: 12),
      _inputField(_produitCtrl, 'Produit / Engrais', Icons.science_outlined),
      const SizedBox(height: 12),
      _qtyRow('Quantite', ['mL', 'L', 'g', 'oz'], _volumeCtrl),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _phField()),
        const SizedBox(width: 12),
        Expanded(child: _tdsField()),
      ]),
      const SizedBox(height: 12),
      _wateringCombinedToggle(),
    ]);
  }

  Widget _traitementFields() {
    return _section('Traitement', [
      _selectField(
          label: 'Cible',
          icon: Icons.bug_report_outlined,
          value: _treatmentTarget,
          values: const [
            'Acariens',
            'Thrips',
            'Mildiou',
            'Oidium',
            'Preventif',
            'Autre',
          ],
          onChanged: (v) => setState(() => _treatmentTarget = v)),
      const SizedBox(height: 12),
      _selectField(
          label: 'Application',
          icon: Icons.spa_outlined,
          value: _treatmentMethod,
          values: const ['Foliaire', 'Substrat', 'Pulverisation', 'Autre'],
          onChanged: (v) => setState(() => _treatmentMethod = v)),
      const SizedBox(height: 12),
      _inputField(_produitCtrl, 'Produit utilise', Icons.healing_outlined),
      const SizedBox(height: 12),
      _qtyRow('Dose / volume', ['mL/L', 'mL', 'g/L', 'g'], _volumeCtrl),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _phField()),
        const SizedBox(width: 12),
        Expanded(child: _tdsField()),
      ]),
    ]);
  }

  Widget _mesureFields() {
    return _section('Mesure', [
      _selectField(
          label: 'Contexte',
          icon: Icons.speed_outlined,
          value: _measureContext,
          values: const ['Solution', 'Drain', 'Substrat', 'Ambiance'],
          onChanged: (v) => setState(() => _measureContext = v)),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _phField()),
        const SizedBox(width: 12),
        Expanded(child: _tdsField()),
      ]),
    ]);
  }

  Widget _tailleFields() {
    return _section('Taille', [
      DropdownButtonFormField<String>(
          initialValue: _pruningType,
          decoration: _deco('Type de taille', Icons.content_cut),
          items: AppUtils.pruningTypes
              .map((t) => DropdownMenuItem(
                  value: t, child: Text(t, overflow: TextOverflow.ellipsis)))
              .toList(),
          onChanged: (v) => setState(() => _pruningType = v!)),
    ]);
  }

  Widget _rempotageFields() {
    // Selecteur de taille de pot
    final currentPot = AppUtils.potSizes.contains(_produitCtrl.text)
        ? _produitCtrl.text
        : '5L';
    // Selecteur de type de contenant
    final containerChoices = [
      {'value': 'pot', 'label': 'Pot classique'},
      {'value': 'pot_tissu', 'label': 'Pot tissu'},
      {'value': 'plein_sol', 'label': 'Plein sol'},
    ];
    _newContainerType ??= widget.plant.containerType;

    final isFullGround = _newContainerType == 'plein_sol';

    return _section('Rempotage', [
      if (isFullGround)
        _fullGroundPotInfo()
      else ...[
        const Text('Nouvelle taille de pot',
            style: TextStyle(fontSize: 12, color: Color(0xFF757575))),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
            initialValue: currentPot,
            decoration: _deco('Taille du pot', Icons.yard_outlined),
            items: AppUtils.potSizes
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            onChanged: (v) => setState(() => _produitCtrl.text = v ?? '5L')),
      ],
      const SizedBox(height: 12),
      const Text('Type de contenant',
          style: TextStyle(fontSize: 12, color: Color(0xFF757575))),
      const SizedBox(height: 6),
      DropdownButtonFormField<String>(
          initialValue: _newContainerType,
          decoration: _deco('Contenant', Icons.move_to_inbox),
          items: containerChoices
              .map((c) =>
                  DropdownMenuItem(value: c['value'], child: Text(c['label']!)))
              .toList(),
          onChanged: (v) => setState(() {
                _newContainerType = v;
                if (v == 'plein_sol') {
                  _produitCtrl.clear();
                } else if (_produitCtrl.text.trim().isEmpty) {
                  _produitCtrl.text = '5L';
                }
              })),
      const SizedBox(height: 12),
      _inputField(_notesCtrl, 'Substrat utilise (optionnel)', Icons.notes),
    ]);
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

  Widget _bouturageFields() {
    final plants = context
        .read<PlantProvider>()
        .allPlants
        .where((p) => p.id != widget.plant.id && !p.isDead && !p.isHarvested)
        .toList();
    return _section('Bouturage', [
      Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: const Color(0xFF00897B).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10)),
          child: const Row(children: [
            Icon(Icons.call_split, color: Color(0xFF00897B), size: 18),
            SizedBox(width: 8),
            Expanded(
                child: Text('Relie cette bouture a sa plante source.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF00897B)))),
          ])),
      const SizedBox(height: 12),
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
                child: Text(p.name, overflow: TextOverflow.ellipsis))),
          ],
          onChanged: (v) => setState(() => _parentPlantId = v)),
      const SizedBox(height: 12),
      _inputField(
          _cuttingCtrl, 'Notes (hormone, milieu, methode...)', Icons.notes),
      const SizedBox(height: 12),
      TextFormField(
          controller: _volumeCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: false),
          decoration: _deco('Nombre de boutures', Icons.call_split)),
    ]);
  }

  int? _cuttingCuttingCount() {
    final value = double.tryParse(_volumeCtrl.text.trim().replaceAll(',', '.'));
    if (value == null || value <= 0 || value != value.roundToDouble()) {
      return null;
    }
    return value.toInt();
  }

  /// Récolte : poids humide, sec et waste.
  Widget _recolteFields() {
    return _section('Recolte', [
      Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: const Color(0xFFF57F17).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: const Color(0xFFF57F17).withValues(alpha: 0.3))),
          child: const Row(children: [
            Icon(Icons.agriculture, color: Color(0xFFF57F17), size: 24),
            SizedBox(width: 12),
            Expanded(
                child: Text(
                    'La plante sera marquee comme recoltee.\nLe compteur d\'arrosage s\'arretera.',
                    style: TextStyle(
                        fontSize: 13, color: Color(0xFFF57F17), height: 1.5))),
          ])),
      const SizedBox(height: 16),
      HarvestWeightFields(
        wetController: _harvestFreshCtrl,
        dryController: _harvestStoredCtrl,
        wasteController: _harvestWasteCtrl,
        decorationBuilder: _deco,
        helperText:
            'Laissez vide si pas encore pesé - vous pourrez modifier l’action plus tard.',
      ),
    ]);
  }

  Widget _infoBox(String emoji, String title, String message) {
    return _section(title, [
      Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: AppUtils.actionColor(_type).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Text(emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Expanded(
                child: Text(message,
                    style: const TextStyle(fontSize: 14, height: 1.5))),
          ])),
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
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('Combine avec un arrosage',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: _isWateringCombined
                                ? const Color(0xFF29B6F6)
                                : const Color(0xFF424242))),
                    const Text('Les nutriments sont dilues dans l\'eau',
                        style:
                            TextStyle(fontSize: 11, color: Color(0xFF9E9E9E))),
                  ])),
              Checkbox(
                  value: _isWateringCombined,
                  onChanged: (v) => setState(() => _isWateringCombined = v!),
                  activeColor: const Color(0xFF29B6F6)),
            ])));
  }

  // --- pH / TDS -------------------------------------------------------------
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
          decoration: _deco(_phNA ? 'N/A' : 'ex: 6,5', Icons.science).copyWith(
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

  // --- Quantite -------------------------------------------------------------
  Widget _qtyRow(String label, List<String> units, TextEditingController ctrl) {
    if (!units.contains(_unit)) _unit = units.first;
    return Row(children: [
      Expanded(
          flex: 3,
          child: TextFormField(
              controller: ctrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: _deco(label, Icons.straighten))),
      const SizedBox(width: 10),
      Expanded(
          flex: 2,
          child: DropdownButtonFormField<String>(
              initialValue: _unit,
              decoration: _deco('Unite', Icons.label_outline),
              items: units
                  .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                  .toList(),
              onChanged: (v) => setState(() => _unit = v!))),
    ]);
  }

  // --- Notes ----------------------------------------------------------------
  Widget _buildNotesField() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Notes',
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2E7D32),
              letterSpacing: 0.8)),
      const SizedBox(height: 8),
      TextFormField(
          controller: _notesCtrl,
          maxLines: 3,
          decoration: _deco('Notes libres...', Icons.notes)),
    ]);
  }

  // --- Photos ---------------------------------------------------------------
  Widget _buildPhotoSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Photos',
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2E7D32),
              letterSpacing: 0.8)),
      const SizedBox(height: 8),
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
                        onPressed: () => _removeDraftPhoto(path),
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
                          Icon(Icons.add_a_photo,
                              color: Color(0xFF4CAF50), size: 24),
                          SizedBox(height: 4),
                          Text('Photo',
                              style: TextStyle(
                                  fontSize: 10, color: Color(0xFF4CAF50))),
                        ]))),
          ])),
    ]);
  }

  // --- Bouton save ----------------------------------------------------------
  Widget _saveBtn() {
    final color = AppUtils.actionColor(_type);
    return SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton.icon(
            onPressed: _isLoading ? null : _save,
            icon: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Icon(AppUtils.actionIcon(_type)),
            label: Text(_isLoading
                ? 'Enregistrement...'
                : 'Enregistrer ${AppUtils.actionLabel(_type)}'),
            style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                textStyle: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold))));
  }

  // --- Helpers --------------------------------------------------------------
  Widget _section(String title, List<Widget> children) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title,
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2E7D32),
              letterSpacing: 0.8)),
      const SizedBox(height: 10),
      ...children,
    ]);
  }

  Widget _inputField(TextEditingController ctrl, String label, IconData icon,
          {int lines = 1}) =>
      TextFormField(
          controller: ctrl, maxLines: lines, decoration: _deco(label, icon));

  Widget _selectField({
    required String label,
    required IconData icon,
    required String value,
    required List<String> values,
    required ValueChanged<String> onChanged,
  }) {
    final safeValue = values.contains(value) ? value : values.first;
    return DropdownButtonFormField<String>(
      initialValue: safeValue,
      decoration: _deco(label, icon),
      items: values
          .map((v) => DropdownMenuItem(value: v, child: Text(v)))
          .toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
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
        lastDate: DateTime.now().add(const Duration(days: 90)),
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
      if (mounted) setState(() => _photos.add(storedPath));
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

  Future<void> _removeDraftPhoto(String photoPath) async {
    setState(() => _photos.remove(photoPath));
    try {
      await PhotoStorageService.deleteManagedFile(photoPath);
    } catch (error, stackTrace) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'gardenjournal actions',
        context: ErrorDescription('suppression d’une photo de brouillon'),
      ));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nettoyage de la photo incomplet.')),
        );
      }
    }
  }

  // --- SAVE -----------------------------------------------------------------
  Future<void> _save() async {
    if (widget.plant.isDead || widget.plant.isHarvested || _isLoading) return;
    setState(() => _isLoading = true);
    try {
      final ph = _phNA
          ? null
          : _parseOptionalNumber(_phCtrl, 'pH', min: 3.5, max: 9.0);
      final tds = _tdsNA
          ? null
          : _parseOptionalNumber(_tdsCtrl, 'TDS', min: 0, max: 5000);
      final qty = _parseOptionalNumber(_volumeCtrl, 'Quantite', min: 0);

      if (_type == 'bouturage' && qty != null && qty != qty.roundToDouble()) {
        throw const _ValidationException(
          'Nombre de boutures invalide: utilisez un nombre entier',
        );
      }

      String? produit =
          _produitCtrl.text.trim().isNotEmpty ? _produitCtrl.text.trim() : null;
      if (_type == 'rempotage' && _newContainerType == 'plein_sol') {
        produit = null;
      }
      String? cuttingNotes =
          _cuttingCtrl.text.trim().isNotEmpty ? _cuttingCtrl.text.trim() : null;
      String? notes =
          _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : null;
      notes = _buildStructuredNotes(notes);

      final isHarvest = _type == 'recolte';
      final harvestFresh = isHarvest
          ? _parseHarvestWeight(_harvestFreshCtrl, 'Poids récolté')
          : null;
      final harvestStored = isHarvest
          ? _parseHarvestWeight(_harvestStoredCtrl, 'Poids conservé')
          : null;
      final harvestWaste = isHarvest
          ? _parseHarvestWeight(_harvestWasteCtrl, 'Poids écarté')
          : null;

      await context.read<ActionProvider>().addAction(
            plantId: widget.plant.id,
            actionType: _type,
            timestamp: _dateTime,
            quantity: qty,
            quantityUnit: _type == 'bouturage' ? null : _unit,
            ph: ph,
            phNA: _phNA,
            tds: tds,
            tdsNA: _tdsNA,
            productUsed: produit,
            pruningType: _type == 'taille' ? _pruningType : null,
            notes: notes,
            parentPlantId: _parentPlantId,
            cuttingNotes: cuttingNotes,
            repotContainerType: _newContainerType,
            photoPaths: _photos,
            isWateringCombined: _isWateringCombined,
            harvestWeightFresh: harvestFresh,
            harvestWeightStored: harvestStored,
            harvestWeightWaste: harvestWaste,
          );

      if (mounted) {
        await Future.wait([
          context.read<PlantProvider>().loadPlants(),
          context.read<SpaceProvider>().refresh(),
        ]);
      }
      await _draftSession.clear();
      if (mounted) Navigator.pop(context, true);
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

  String? _buildStructuredNotes(String? rawNotes) {
    final lines = <String>[];
    if (_type == 'nutriments') {
      lines.add('Mode: $_nutrientMode');
    }
    if (_type == 'traitement') {
      lines.add('Cible: $_treatmentTarget');
      lines.add('Application: $_treatmentMethod');
    }
    if (_type == 'mesure') {
      lines.add('Contexte: $_measureContext');
    }
    if (rawNotes != null && rawNotes.isNotEmpty) lines.add(rawNotes);
    return lines.isEmpty ? null : lines.join('\n');
  }
}
