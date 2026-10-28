import 'dart:io';
import 'dart:math' as math;

import 'package:path_provider/path_provider.dart';
import 'package:qr/qr.dart';
import 'package:share_plus/share_plus.dart';

class QrStlExportService {
  static const double moduleSizeMm = 1.6;
  static const double baseHeightMm = 1.2;
  static const double reliefHeightMm = 0.9;
  static const int quietZoneModules = 4;

  static Future<File> exportQrStl({
    required String data,
    required String fileName,
  }) async {
    final qrCode = QrCode.fromData(
      data: data,
      errorCorrectLevel: QrErrorCorrectLevel.M,
    );
    final qrImage = QrImage(qrCode);
    final stl = _buildStl(qrImage);
    final dir = await getTemporaryDirectory();
    final safeName = _safeFileName(fileName);
    final file = File('${dir.path}/$safeName.stl');
    await file.writeAsString(stl);
    return file;
  }

  static Future<void> shareQrStl({
    required String data,
    required String fileName,
    String? text,
  }) async {
    final file = await exportQrStl(data: data, fileName: fileName);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'model/stl')],
        text: text ?? 'QR STL',
        subject: fileName,
      ),
    );
  }

  static String _buildStl(QrImage qrImage) {
    final buffer = StringBuffer('solid gardenjournal_qr\n');
    final modules = qrImage.moduleCount;
    final totalModules = modules + quietZoneModules * 2;
    final plateSize = totalModules * moduleSizeMm;

    _addBox(
      buffer,
      x: 0,
      y: 0,
      z: 0,
      width: plateSize,
      depth: plateSize,
      height: baseHeightMm,
    );

    for (var row = 0; row < modules; row++) {
      for (var col = 0; col < modules; col++) {
        if (!qrImage.isDark(row, col)) continue;
        _addBox(
          buffer,
          x: (col + quietZoneModules) * moduleSizeMm,
          y: (row + quietZoneModules) * moduleSizeMm,
          z: baseHeightMm,
          width: moduleSizeMm,
          depth: moduleSizeMm,
          height: reliefHeightMm,
        );
      }
    }

    buffer.write('endsolid gardenjournal_qr\n');
    return buffer.toString();
  }

  static void _addBox(
    StringBuffer buffer, {
    required double x,
    required double y,
    required double z,
    required double width,
    required double depth,
    required double height,
  }) {
    final x1 = x + width;
    final y1 = y + depth;
    final z1 = z + height;

    final p000 = _Point(x, y, z);
    final p100 = _Point(x1, y, z);
    final p110 = _Point(x1, y1, z);
    final p010 = _Point(x, y1, z);
    final p001 = _Point(x, y, z1);
    final p101 = _Point(x1, y, z1);
    final p111 = _Point(x1, y1, z1);
    final p011 = _Point(x, y1, z1);

    _face(buffer, _Point(0, 0, -1), p000, p010, p110, p100);
    _face(buffer, _Point(0, 0, 1), p001, p101, p111, p011);
    _face(buffer, _Point(0, -1, 0), p000, p100, p101, p001);
    _face(buffer, _Point(1, 0, 0), p100, p110, p111, p101);
    _face(buffer, _Point(0, 1, 0), p110, p010, p011, p111);
    _face(buffer, _Point(-1, 0, 0), p010, p000, p001, p011);
  }

  static void _face(
    StringBuffer buffer,
    _Point normal,
    _Point a,
    _Point b,
    _Point c,
    _Point d,
  ) {
    _triangle(buffer, normal, a, b, c);
    _triangle(buffer, normal, a, c, d);
  }

  static void _triangle(
    StringBuffer buffer,
    _Point normal,
    _Point a,
    _Point b,
    _Point c,
  ) {
    buffer
      ..writeln(
          '  facet normal ${_n(normal.x)} ${_n(normal.y)} ${_n(normal.z)}')
      ..writeln('    outer loop')
      ..writeln('      vertex ${_n(a.x)} ${_n(a.y)} ${_n(a.z)}')
      ..writeln('      vertex ${_n(b.x)} ${_n(b.y)} ${_n(b.z)}')
      ..writeln('      vertex ${_n(c.x)} ${_n(c.y)} ${_n(c.z)}')
      ..writeln('    endloop')
      ..writeln('  endfacet');
  }

  static String _safeFileName(String name) {
    final cleaned = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    return cleaned.isEmpty ? 'gardenjournal_qr' : cleaned;
  }

  static String _n(double value) {
    if (value == 0) return '0';
    if (value == value.roundToDouble()) return value.toInt().toString();
    return math.max(-9999, math.min(9999, value)).toStringAsFixed(3);
  }
}

class _Point {
  final double x;
  final double y;
  final double z;

  const _Point(this.x, this.y, this.z);
}
