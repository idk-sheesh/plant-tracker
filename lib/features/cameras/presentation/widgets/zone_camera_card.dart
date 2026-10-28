import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../core/widgets/photo_viewer_screen.dart';
import '../../../../core/widgets/safe_file_image.dart';
import '../../data/repositories/private_camera_gateway_repository.dart';
import '../../domain/entities/camera_snapshot.dart';
import '../providers/camera_provider.dart';

class ZoneCameraCard extends StatelessWidget {
  final String zoneId;
  final String zoneName;

  const ZoneCameraCard({
    super.key,
    required this.zoneId,
    required this.zoneName,
  });

  @override
  Widget build(BuildContext context) {
    final cameras = context.watch<CameraProvider>();
    final camera = cameras.cameraForZone(zoneId);
    final status = cameras.statusForZone(zoneId);
    final image = cameras.imageForZone(zoneId);
    final error = cameras.errorForZone(zoneId);
    final savedPhotos = cameras.savedPhotosForZone(zoneId);
    final loading = cameras.isLoading(zoneId);
    final hasSession = camera != null && cameras.hasSession(camera.id);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.videocam_outlined,
                  color: status?.isOnline == true ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        camera?.name ?? 'Caméra de l’espace',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(_statusLabel(
                          camera != null, hasSession, status?.status)),
                    ],
                  ),
                ),
                if (loading)
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            if (image != null) ...[
              const SizedBox(height: 12),
              _preview(image),
              if (cameras.privateModeForZone(zoneId))
                const Text(
                    'Aperçu temporaire · effacé après 60 secondes ou en arrière-plan.'),
              if (status?.latestSnapshot != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Reçue le ${DateFormat('dd/MM/yyyy à HH:mm').format(status!.latestSnapshot!.capturedAt)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ] else ...[
              const SizedBox(height: 12),
              Text(
                camera == null
                    ? 'Aucune caméra n’est associée à cet espace.'
                    : 'Aucune photo téléchargée pour cette session.',
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: loading
                      ? null
                      : () => _configure(
                          context, camera?.uid, camera?.name, camera?.baseUrl),
                  icon: const Icon(Icons.settings_ethernet),
                  label: Text(camera == null || !hasSession
                      ? 'Connecter'
                      : 'Reconfigurer'),
                ),
                if (hasSession)
                  OutlinedButton.icon(
                    onPressed: loading ? null : () => cameras.refresh(zoneId),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Actualiser'),
                  ),
                if (hasSession)
                  FilledButton.icon(
                    onPressed: loading ? null : () => cameras.capture(zoneId),
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: const Text('Prendre une photo'),
                  ),
                if (hasSession &&
                    image != null &&
                    cameras.privateModeForZone(zoneId))
                  FilledButton.tonalIcon(
                    onPressed: loading || cameras.isCurrentPhotoSaved(zoneId)
                        ? null
                        : () => _savePhoto(context),
                    icon: const Icon(Icons.save_alt),
                    label: Text(cameras.isCurrentPhotoSaved(zoneId)
                        ? 'Photo conservée'
                        : 'Conserver cette photo'),
                  ),
                if (hasSession)
                  TextButton(
                    onPressed: () => cameras.disconnect(zoneId),
                    child: const Text('Déconnecter'),
                  ),
              ],
            ),
            if (savedPhotos.isNotEmpty) ...[
              const SizedBox(height: 16),
              _savedPhotoHistory(context, savedPhotos, loading),
            ],
          ],
        ),
      ),
    );
  }

  Widget _preview(Uint8List image) => Semantics(
        image: true,
        label: 'Dernière photo de $zoneName',
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: _TransientPreview(bytes: image),
          ),
        ),
      );

  String _statusLabel(bool configured, bool session, String? status) {
    if (!configured) return 'Non configurée';
    if (!session) return 'Connexion requise';
    if (status == null) return 'Jeton mémorisé · prête à actualiser';
    return status == 'online' ? 'En ligne' : 'Hors ligne';
  }

  Widget _savedPhotoHistory(
    BuildContext context,
    List<CameraSnapshot> snapshots,
    bool loading,
  ) {
    final paths = snapshots.map((item) => item.photoPath!).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Photos conservées (${snapshots.length})',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 118,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: snapshots.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, index) {
              final snapshot = snapshots[index];
              return SizedBox(
                width: 112,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SafeFileImage(
                            path: snapshot.photoPath!,
                            width: 112,
                            height: 84,
                            semanticLabel: 'Photo conservée de $zoneName',
                            onTap: () => PhotoViewerScreen.openGallery(
                              context,
                              paths,
                              initialIndex: index,
                              semanticLabel: 'Photos caméra de $zoneName',
                            ),
                          ),
                        ),
                        Positioned(
                          right: 2,
                          top: 2,
                          child: Material(
                            color: Colors.black54,
                            shape: const CircleBorder(),
                            child: IconButton(
                              tooltip: 'Supprimer cette photo',
                              visualDensity: VisualDensity.compact,
                              color: Colors.white,
                              iconSize: 18,
                              onPressed: loading
                                  ? null
                                  : () => _confirmDelete(context, snapshot),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      DateFormat('dd/MM · HH:mm').format(snapshot.capturedAt),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _savePhoto(BuildContext context) async {
    final saved = await context.read<CameraProvider>().saveCurrentPhoto(zoneId);
    if (!context.mounted || !saved) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Photo conservée dans GardenJournal.')),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    CameraSnapshot snapshot,
  ) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Supprimer la photo ?'),
            content: const Text(
              'Elle sera retirée de GardenJournal et des prochaines sauvegardes.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Supprimer'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !context.mounted) return;
    final deleted =
        await context.read<CameraProvider>().deleteSavedPhoto(zoneId, snapshot);
    if (!context.mounted || !deleted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Photo supprimée.')),
    );
  }

  Future<void> _configure(
    BuildContext context,
    String? initialId,
    String? initialName,
    String? initialUrl,
  ) async {
    final cameraId = TextEditingController(text: initialId ?? 'cam-01');
    final name = TextEditingController(text: initialName ?? 'Caméra $zoneName');
    final baseUrl = TextEditingController(
      text: initialUrl ?? '',
    );
    final token = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var rememberToken = true;
    try {
      if (initialId != null && initialUrl != null) {
        token.text = await context.read<CameraProvider>().rememberedToken(
                  cameraId: initialId,
                  baseUrl: initialUrl,
                ) ??
            '';
        if (!context.mounted) return;
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          var busy = false;
          String? localError;
          return StatefulBuilder(
            builder: (context, setDialogState) {
              final privateUrl =
                  PrivateCameraGatewayRepository.isPrivateHubUrl(baseUrl.text);
              return AlertDialog(
                title: const Text('Connecter la caméra'),
                content: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          controller: cameraId,
                          decoration:
                              const InputDecoration(labelText: 'Identifiant'),
                          validator: _required,
                        ),
                        TextFormField(
                          controller: name,
                          decoration: const InputDecoration(labelText: 'Nom'),
                          validator: _required,
                        ),
                        TextFormField(
                          controller: baseUrl,
                          decoration: const InputDecoration(
                            labelText: 'URL HTTPS du Raspberry Pi',
                            helperText:
                                'Adresse HTTPS centrale du Pi, sans chemin.',
                            helperMaxLines: 2,
                          ),
                          keyboardType: TextInputType.url,
                          validator: _required,
                          onChanged: (_) => setDialogState(() {}),
                        ),
                        TextFormField(
                          controller: token,
                          decoration: InputDecoration(
                            labelText: 'Jeton application du Pi',
                            helperText: privateUrl && rememberToken
                                ? 'Protégé dans le coffre sécurisé du téléphone.'
                                : 'Conservé uniquement pendant cette session.',
                          ),
                          obscureText: true,
                          enableSuggestions: false,
                          autocorrect: false,
                          validator: (value) =>
                              value == null || value.trim().length < 32
                                  ? 'Jeton trop court'
                                  : null,
                        ),
                        if (privateUrl)
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            value: rememberToken,
                            onChanged: busy
                                ? null
                                : (value) => setDialogState(
                                      () => rememberToken = value,
                                    ),
                            title: const Text('Mémoriser le jeton'),
                            subtitle: const Text(
                              'Le jeton reste hors de la base et des sauvegardes.',
                            ),
                          ),
                        if (localError != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            localError!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: busy ? null : () => Navigator.pop(dialogContext),
                    child: const Text('Annuler'),
                  ),
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () async {
                            if (formKey.currentState?.validate() != true)
                              return;
                            setDialogState(() {
                              busy = true;
                              localError = null;
                            });
                            final connected = await dialogContext
                                .read<CameraProvider>()
                                .connect(
                                  cameraId: cameraId.text,
                                  name: name.text,
                                  zoneId: zoneId,
                                  baseUrl: baseUrl.text,
                                  appToken: token.text,
                                  rememberToken:
                                      privateUrl ? rememberToken : null,
                                );
                            if (!dialogContext.mounted) return;
                            if (connected) {
                              Navigator.pop(dialogContext);
                            } else {
                              setDialogState(() {
                                busy = false;
                                localError = dialogContext
                                    .read<CameraProvider>()
                                    .errorForZone(zoneId);
                              });
                            }
                          },
                    child: const Text('Tester et connecter'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      cameraId.dispose();
      name.dispose();
      baseUrl.dispose();
      token.dispose();
    }
  }

  static String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Champ obligatoire' : null;
}

/// Evict decoded previews as well as clearing encoded bytes in the provider.
class _TransientPreview extends StatefulWidget {
  final Uint8List bytes;
  const _TransientPreview({required this.bytes});
  @override
  State<_TransientPreview> createState() => _TransientPreviewState();
}

class _TransientPreviewState extends State<_TransientPreview> {
  late ImageProvider _image;
  void _replace() {
    _image = ResizeImage.resizeIfNeeded(1200, null, MemoryImage(widget.bytes));
  }

  @override
  void initState() {
    super.initState();
    _replace();
  }

  @override
  void didUpdateWidget(covariant _TransientPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes)) {
      _image.evict();
      _replace();
    }
  }

  @override
  void dispose() {
    _image.evict();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Image(
      image: _image,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) =>
          const Center(child: Text('Photo illisible')));
}
