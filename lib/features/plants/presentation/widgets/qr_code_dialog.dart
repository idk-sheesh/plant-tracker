import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/services/qr_stl_export_service.dart';
import '../../../../core/utils/app_utils.dart';
import '../../domain/entities/plant.dart';

class QrCodeDialog extends StatefulWidget {
  final Plant plant;

  const QrCodeDialog({super.key, required this.plant});

  @override
  State<QrCodeDialog> createState() => _QrCodeDialogState();
}

class _QrCodeDialogState extends State<QrCodeDialog> {
  final GlobalKey _qrKey = GlobalKey();
  bool _isBusy = false;

  String get _qrData => widget.plant.qrCode;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const Icon(Icons.qr_code_2, color: Color(0xFF2E7D32), size: 24),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Code QR Plante',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
          ]),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(children: [
              Icon(Icons.info_outline, size: 13, color: Color(0xFF2E7D32)),
              SizedBox(width: 4),
              Expanded(
                child: Text(
                  'QR lisible sur tout appareil',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Color(0xFF2E7D32)),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          RepaintBoundary(key: _qrKey, child: _qrCard()),
          const SizedBox(height: 12),
          const Text(
            'STL: QR court en relief, plus fiable en impression 3D.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF757575), fontSize: 12),
          ),
          const SizedBox(height: 18),
          LayoutBuilder(builder: (context, constraints) {
            final useVerticalActions = constraints.maxWidth < 320 ||
                MediaQuery.textScalerOf(context).scale(14) > 18;
            final copyButton = OutlinedButton.icon(
              onPressed: _isBusy ? null : _copyId,
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copier'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF2E7D32),
                side: const BorderSide(color: Color(0xFF2E7D32)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            );
            final pngButton = ElevatedButton.icon(
              onPressed: _isBusy ? null : _sharePng,
              icon: const Icon(Icons.share, size: 18),
              label: const Text('PNG'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            );
            if (useVerticalActions) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  copyButton,
                  const SizedBox(height: 10),
                  pngButton,
                ],
              );
            }
            return Row(children: [
              Expanded(child: copyButton),
              const SizedBox(width: 12),
              Expanded(child: pngButton),
            ]);
          }),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isBusy ? null : _shareStl,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF455A64),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.view_in_ar, size: 18),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Exporter STL impression 3D',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _qrCard() => Container(
        padding: const EdgeInsets.all(16),
        color: Colors.white,
        child: Column(children: [
          QrImageView(
            data: _qrData,
            version: QrVersions.auto,
            size: 180,
            backgroundColor: Colors.white,
            eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: Color(0xFF2E7D32),
            ),
            dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: Color(0xFF1B5E20),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            widget.plant.name,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          if (widget.plant.variety != null && widget.plant.variety!.isNotEmpty)
            Text(
              widget.plant.variety!,
              style: const TextStyle(color: Color(0xFF757575), fontSize: 13),
            ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${widget.plant.locationEmoji} ${widget.plant.cultureType} - ${AppUtils.formatDate(widget.plant.pottingDate)}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF2E7D32),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ]),
      );

  void _copyId() {
    Clipboard.setData(ClipboardData(text: widget.plant.qrCode));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('ID copie'),
      backgroundColor: Color(0xFF2E7D32),
    ));
  }

  Future<void> _sharePng() async {
    setState(() => _isBusy = true);
    try {
      final boundary =
          _qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/qr_${widget.plant.id}.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'QR Code - ${widget.plant.name}',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur: $e'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _shareStl() async {
    setState(() => _isBusy = true);
    try {
      await QrStlExportService.shareQrStl(
        data: _qrData,
        fileName: 'gardenjournal_qr_${widget.plant.name}_${widget.plant.id}',
        text: 'QR STL - ${widget.plant.name}',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur STL: $e'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }
}
