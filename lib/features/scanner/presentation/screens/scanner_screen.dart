import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../../../plants/presentation/providers/plant_provider.dart';
import '../../../plants/presentation/screens/plant_detail_screen.dart';
import '../../../sensors/presentation/providers/sensor_provider.dart';
import '../../../sensors/presentation/screens/device_health_screen.dart';
import '../../../sensors/presentation/screens/device_provisioning_screen.dart';
import '../../domain/qr_payload_parser.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen>
    with WidgetsBindingObserver {
  MobileScannerController? _ctrl;
  bool _processing = false;
  bool _torch = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ctrl =
        MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused)
      _ctrl?.stop();
    else if (state == AppLifecycleState.resumed) _ctrl?.start();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scanner QR'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_torch ? Icons.flash_on : Icons.flash_off),
            onPressed: () {
              setState(() => _torch = !_torch);
              _ctrl?.toggleTorch();
            },
          ),
        ],
      ),
      body: Stack(children: [
        MobileScanner(controller: _ctrl!, onDetect: _onDetect),
        _overlay(),
        if (_error != null)
          Positioned(
              bottom: 120,
              left: 32,
              right: 32,
              child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(14)),
                  child: Text(_error!,
                      textAlign: TextAlign.center,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 14)))),
        if (_processing)
          Container(
              color: Colors.black54,
              child: const Center(
                  child: CircularProgressIndicator(color: Color(0xFF4CAF50)))),
      ]),
    );
  }

  Widget _overlay() {
    return Stack(children: [
      ColorFiltered(
        colorFilter: ColorFilter.mode(
            Colors.black.withValues(alpha: 0.6), BlendMode.srcOut),
        child: Stack(children: [
          Container(
              decoration: const BoxDecoration(
                  color: Colors.black, backgroundBlendMode: BlendMode.dstOut)),
          Center(
              child: Container(
                  width: 250,
                  height: 250,
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24)))),
        ]),
      ),
      Center(child: _frame()),
      Positioned(
          bottom: 80,
          left: 0,
          right: 0,
          child: Column(children: [
            const Text('Pointez la caméra vers le QR code',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            Text("Le profil s'ouvrira automatiquement",
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7), fontSize: 13)),
          ])),
    ]);
  }

  Widget _frame() {
    const s = 250.0, cs = 30.0, t = 4.0;
    final c = const Color(0xFF4CAF50);
    return SizedBox(
        width: s,
        height: s,
        child: Stack(children: [
          Positioned(top: 0, left: 0, child: _corner(c, cs, t, true, true)),
          Positioned(top: 0, right: 0, child: _corner(c, cs, t, true, false)),
          Positioned(bottom: 0, left: 0, child: _corner(c, cs, t, false, true)),
          Positioned(
              bottom: 0, right: 0, child: _corner(c, cs, t, false, false)),
        ]));
  }

  Widget _corner(
          Color color, double size, double thickness, bool top, bool left) =>
      SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
              painter: _CornerPainter(
                  color: color, thickness: thickness, top: top, left: left)));

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.isEmpty) return;
    setState(() {
      _processing = true;
      _error = null;
    });
    try {
      await _ctrl?.stop();
      final payload = QrPayloadParser.parse(raw);
      if (!mounted) return;
      if (payload.entityType != QrEntityType.plant) {
        await _openDevice(payload);
        return;
      }
      final plant =
          await context.read<PlantProvider>().getPlantById(payload.plantId);
      if (plant != null && mounted) {
        await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => PlantDetailScreen(plantId: plant.id)));
      } else if (mounted && payload.isLegacyProfile) {
        _showExternal(payload);
      } else {
        _showTemporaryError('Plante introuvable ou supprimée');
      }
    } on FormatException {
      if (mounted) _showTemporaryError('QR code non reconnu');
    } catch (error, stackTrace) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'gardenjournal scanner',
        context: ErrorDescription('recherche d’une plante par QR'),
      ));
      if (mounted) _showTemporaryError('Lecture impossible, réessayez');
    } finally {
      if (mounted) {
        setState(() => _processing = false);
        _ctrl?.start();
      }
    }
  }

  Future<void> _openDevice(QrPayload payload) async {
    final sensors = context.read<SensorProvider>();
    await sensors.initialize();
    if (!mounted) return;
    final existing = sensors.deviceByUid(payload.deviceId);
    if (existing != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DeviceHealthScreen(initialDeviceId: existing.id),
        ),
      );
      return;
    }
    if (!payload.canProvision) {
      _showTemporaryError(
        'Appareil inconnu : QR d’association temporaire requis',
      );
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DeviceProvisioningScreen(identity: payload),
      ),
    );
  }

  void _showExternal(QrPayload payload) {
    final profile = payload.legacyProfile!;
    showDialog(
        context: context,
        builder: (_) => AlertDialog(
              scrollable: true,
              title: Row(children: [
                const Text('🌿 ', style: TextStyle(fontSize: 20)),
                Expanded(
                    child: Text(profile['name']!,
                        style: const TextStyle(fontSize: 17)))
              ]),
              content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (profile['variety']!.isNotEmpty)
                      _infoRow('Variété', profile['variety']!),
                    _infoRow('Culture', profile['culture']!),
                    _infoRow('Mise en pot', profile['pottingDate']!),
                    if (profile['pot']!.isNotEmpty)
                      _infoRow('Pot', profile['pot']!),
                    const SizedBox(height: 12),
                    Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: const Color(0xFFFFF3E0),
                            borderRadius: BorderRadius.circular(8)),
                        child: const Text(
                            'Plante d\'un autre appareil. Importez-la pour la suivre.',
                            style: TextStyle(
                                fontSize: 12, color: Color(0xFF795548)))),
                  ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Fermer'))
              ],
            ));
  }

  void _showTemporaryError(String message) {
    setState(() => _error = message);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _error == message) setState(() => _error = null);
    });
  }

  Widget _infoRow(String l, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Text('$l : ',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        Expanded(child: Text(v, style: const TextStyle(fontSize: 13)))
      ]));
}

class _CornerPainter extends CustomPainter {
  final Color color;
  final double thickness;
  final bool top, left;
  _CornerPainter(
      {required this.color,
      required this.thickness,
      required this.top,
      required this.left});
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path();
    if (top && left) {
      path.moveTo(0, size.height);
      path.lineTo(0, 0);
      path.lineTo(size.width, 0);
    } else if (top && !left) {
      path.moveTo(0, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width, size.height);
    } else if (!top && left) {
      path.moveTo(0, 0);
      path.lineTo(0, size.height);
      path.lineTo(size.width, size.height);
    } else {
      path.moveTo(0, size.height);
      path.lineTo(size.width, size.height);
      path.lineTo(size.width, 0);
    }
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_CornerPainter o) => false;
}
