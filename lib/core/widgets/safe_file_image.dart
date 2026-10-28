import 'dart:io';

import 'package:flutter/material.dart';
import 'photo_viewer_screen.dart';

class SafeFileImage extends StatelessWidget {
  final String path;
  final BoxFit fit;
  final double? width;
  final double? height;
  final String semanticLabel;
  final VoidCallback? onTap;
  final bool enableFullscreen;

  const SafeFileImage({
    super.key,
    required this.path,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.semanticLabel = 'Photo',
    this.onTap,
    this.enableFullscreen = true,
  });

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    final fallback = Semantics(
      label: '$semanticLabel indisponible',
      image: true,
      child: const ColoredBox(
        color: Color(0xFFE0E0E0),
        child: Center(
          child: Icon(
            Icons.broken_image_outlined,
            color: Color(0xFF616161),
          ),
        ),
      ),
    );
    bool exists;
    try {
      exists = file.existsSync();
    } on FileSystemException {
      exists = false;
    }

    final image = SizedBox(
      width: width,
      height: height,
      child: exists
          ? Image.file(
              file,
              fit: fit,
              semanticLabel: semanticLabel,
              errorBuilder: (context, error, stackTrace) => fallback,
            )
          : fallback,
    );

    final tapHandler = onTap ??
        (enableFullscreen
            ? () => PhotoViewerScreen.open(
                  context,
                  path,
                  semanticLabel: semanticLabel,
                )
            : null);
    if (tapHandler == null) return image;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: tapHandler,
      child: Semantics(
        button: true,
        image: true,
        label: semanticLabel,
        onTap: tapHandler,
        child: ExcludeSemantics(child: image),
      ),
    );
  }
}
