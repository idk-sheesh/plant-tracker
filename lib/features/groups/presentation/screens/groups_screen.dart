import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/utils/app_utils.dart';
import '../../../spaces/presentation/providers/space_provider.dart';
import '../../../spaces/presentation/widgets/zone_move_sheet.dart';
import '../../data/models/plant_group.dart';
import '../providers/group_provider.dart';

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  String? _currentGroupId;

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: _currentGroupId == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _currentGroupId == null) return;
        _goToParent(context.read<GroupProvider>());
      },
      child: Scaffold(
        appBar: AppBar(
          leading: _currentGroupId == null
              ? null
              : IconButton(
                  tooltip: 'Dossier parent',
                  onPressed: () => _goToParent(context.read<GroupProvider>()),
                  icon: const Icon(Icons.arrow_back),
                ),
          title: Consumer<GroupProvider>(
            builder: (_, provider, __) => Text(_currentGroupId == null
                ? 'Groupes / Cultures'
                : (provider.getGroupById(_currentGroupId)?.name ?? 'Dossier')),
          ),
        ),
        body: Consumer<GroupProvider>(builder: (_, provider, __) {
          if (provider.isLoading && provider.groups.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (provider.error != null && provider.groups.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 40),
                  const SizedBox(height: 10),
                  Text(provider.error!, textAlign: TextAlign.center),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: provider.loadGroups,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Réessayer'),
                  ),
                ]),
              ),
            );
          }
          if (provider.groups.isEmpty) {
            return _emptyState(context, provider);
          }

          final current = provider.getGroupById(_currentGroupId);
          final folders = provider.groups
              .where((group) => group.parentGroupId == _currentGroupId)
              .toList();

          return Column(
            children: [
              _breadcrumbBar(provider),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: _folderList(
                    context,
                    provider,
                    current,
                    folders,
                    key: ValueKey(_currentGroupId),
                  ),
                ),
              ),
            ],
          );
        }),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showCreate(
            context,
            context.read<GroupProvider>(),
            _currentGroupId,
          ),
          icon: const Icon(Icons.create_new_folder_outlined),
          label: Text(_currentGroupId == null
              ? 'Nouveau dossier'
              : 'Nouveau sous-dossier'),
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context, GroupProvider provider) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.folder_open_outlined,
            size: 56, color: Color(0xFF9E9E9E)),
        const SizedBox(height: 16),
        const Text('Aucun dossier',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        const Text('Organisez vos plantes par année, salle ou session',
            style: TextStyle(color: Color(0xFF757575))),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: () => _showCreate(context, provider, null),
          icon: const Icon(Icons.add),
          label: const Text('Créer un dossier'),
          style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white),
        ),
      ]),
    );
  }

  Widget _breadcrumbBar(GroupProvider provider) {
    final breadcrumbs = _breadcrumbs(provider);
    if (breadcrumbs.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _currentGroupId = null),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.home_outlined, size: 19),
            ),
          ),
          for (final group in breadcrumbs) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.chevron_right, size: 18, color: Colors.grey),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _currentGroupId = group.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Text(
                  group.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  List<PlantGroup> _breadcrumbs(GroupProvider provider) {
    final result = <PlantGroup>[];
    final visited = <String>{};
    var current = provider.getGroupById(_currentGroupId);
    while (current != null && visited.add(current.id)) {
      result.insert(0, current);
      current = provider.getGroupById(current.parentGroupId);
    }
    return result;
  }

  Widget _folderList(
    BuildContext context,
    GroupProvider provider,
    PlantGroup? current,
    List<PlantGroup> folders, {
    Key? key,
  }) {
    final description = current?.description?.trim();
    return ListView(
      key: key,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        if (current != null) ...[
          Text(
            description?.isNotEmpty == true ? description! : 'Sous-dossiers',
            style: const TextStyle(color: Color(0xFF757575)),
          ),
          const SizedBox(height: 10),
        ] else ...[
          const Text(
            'Dossiers principaux',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
        ],
        if (folders.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Column(children: [
              Icon(Icons.folder_open_outlined,
                  size: 42, color: Color(0xFFBDBDBD)),
              SizedBox(height: 10),
              Text('Aucun sous-dossier',
                  style: TextStyle(color: Color(0xFF757575))),
              SizedBox(height: 4),
              Text('Utilisez le bouton + pour en créer un',
                  style: TextStyle(fontSize: 12, color: Color(0xFF9E9E9E))),
            ]),
          )
        else
          ...folders.map((folder) => _folderTile(context, provider, folder)),
      ],
    );
  }

  Widget _folderTile(
      BuildContext context, GroupProvider provider, PlantGroup folder) {
    final childCount = provider.groups
        .where((group) => group.parentGroupId == folder.id)
        .length;
    final description = folder.description?.trim();
    final detail = [
      if (description?.isNotEmpty == true) description!,
      if (childCount == 0)
        'Dossier'
      else
        '$childCount sous-dossier${childCount > 1 ? 's' : ''}',
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Icon(Icons.folder, color: folder.color, size: 34),
        title: Text(folder.name,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
        subtitle: Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'move') {
                showGroupZoneMoveSheet(context, folder);
              } else if (value == 'child') {
                _showCreate(context, provider, folder.id);
              } else if (value == 'edit') {
                _showEdit(context, provider, folder);
              } else if (value == 'delete') {
                _confirmDelete(context, provider, folder);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'move',
                child: Text('Déplacer vers une zone'),
              ),
              PopupMenuItem(
                value: 'child',
                child: Text('Créer un sous-groupe'),
              ),
              PopupMenuItem(value: 'edit', child: Text('Modifier')),
              PopupMenuItem(value: 'delete', child: Text('Supprimer')),
            ],
          ),
          const Icon(Icons.chevron_right, color: Color(0xFF9E9E9E)),
        ]),
        onTap: () => setState(() => _currentGroupId = folder.id),
      ),
    );
  }

  void _goToParent(GroupProvider provider) {
    final current = provider.getGroupById(_currentGroupId);
    setState(() => _currentGroupId = current?.parentGroupId);
  }

  void _showCreate(
      BuildContext context, GroupProvider provider, String? parentId) {
    showDialog(
      context: context,
      builder: (_) => _GroupDialog(provider: provider, parentGroupId: parentId),
    );
  }

  void _showEdit(
      BuildContext context, GroupProvider provider, PlantGroup group) {
    showDialog(
      context: context,
      builder: (_) => _GroupDialog(
        provider: provider,
        group: group,
        parentGroupId: group.parentGroupId,
      ),
    );
  }

  void _confirmDelete(
      BuildContext context, GroupProvider provider, PlantGroup group) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer ce groupe ?'),
        content: const Text(
            'Les plantes ne seront pas supprimées, juste dissociées.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler')),
          TextButton(
            onPressed: () async {
              try {
                final parentId = group.parentGroupId;
                await provider.deleteGroup(group.id);
                if (mounted && _currentGroupId == group.id) {
                  setState(() => _currentGroupId = parentId);
                }
                if (context.mounted) Navigator.pop(context);
              } catch (_) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        provider.error ?? 'Suppression du groupe impossible'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _GroupDialog extends StatefulWidget {
  final GroupProvider provider;
  final PlantGroup? group;
  final String? parentGroupId;

  const _GroupDialog({required this.provider, this.group, this.parentGroupId});

  @override
  State<_GroupDialog> createState() => _GroupDialogState();
}

class _GroupDialogState extends State<_GroupDialog> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  Color _color = const Color(0xFF4CAF50);
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.group != null) {
      _nameCtrl.text = widget.group!.name;
      _descCtrl.text = widget.group!.description ?? '';
      _color = widget.group!.color;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSub = widget.parentGroupId != null && widget.group == null;
    return AlertDialog(
      title: Text(widget.group == null
          ? (isSub ? 'Nouveau sous-groupe' : 'Nouveau groupe')
          : 'Modifier le groupe'),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (isSub)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(8)),
              child: const Row(children: [
                Icon(Icons.subdirectory_arrow_right,
                    color: Color(0xFF2E7D32), size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Ce groupe sera un sous-groupe',
                      style: TextStyle(fontSize: 13, color: Color(0xFF2E7D32))),
                ),
              ]),
            ),
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            decoration: const InputDecoration(
                labelText: 'Nom du groupe *', prefixIcon: Icon(Icons.folder)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descCtrl,
            decoration: const InputDecoration(
                labelText: 'Description (optionnel)',
                prefixIcon: Icon(Icons.notes)),
          ),
          const SizedBox(height: 16),
          const Align(
              alignment: Alignment.centerLeft,
              child: Text('Couleur',
                  style: TextStyle(fontSize: 12, color: Color(0xFF757575)))),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: AppUtils.groupColors.map((color) {
              final selected = color.toARGB32() == _color.toARGB32();
              return GestureDetector(
                onTap: () => setState(() => _color = color),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: selected
                        ? Border.all(color: Colors.black38, width: 3)
                        : null,
                  ),
                  child: selected
                      ? const Icon(Icons.check, color: Colors.white, size: 18)
                      : null,
                ),
              );
            }).toList(),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_error!,
                  style: const TextStyle(color: Colors.red, fontSize: 12)),
            ),
          const SizedBox(height: 16),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Annuler')),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white),
          child: Text(widget.group == null ? 'Créer' : 'Enregistrer'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Le nom du groupe est obligatoire.');
      return;
    }
    if (_saving) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final description =
          _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim();
      if (widget.group == null) {
        await widget.provider.createGroup(
          name: name,
          description: description,
          color: _color,
          parentGroupId: widget.parentGroupId,
        );
      } else {
        await widget.provider.updateGroup(widget.group!.copyWith(
          name: name,
          description: description,
          color: _color,
        ));
        await context.read<SpaceProvider>().refresh();
      }
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = widget.provider.error ?? 'Impossible d’enregistrer le groupe.';
      });
    }
  }
}
