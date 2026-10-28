import 'package:flutter/material.dart';

import 'safe_file_image.dart';

class PhotoViewerScreen extends StatefulWidget {
  final List<String> paths;
  final int initialIndex;
  final String semanticLabel;

  const PhotoViewerScreen({
    super.key,
    required this.paths,
    this.initialIndex = 0,
    this.semanticLabel = 'Photo',
  });

  static Future<void> open(
    BuildContext context,
    String path, {
    String semanticLabel = 'Photo',
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PhotoViewerScreen(
          paths: [path],
          semanticLabel: semanticLabel,
        ),
      ),
    );
  }

  static Future<void> openGallery(
    BuildContext context,
    List<String> paths, {
    int initialIndex = 0,
    String semanticLabel = 'Photo',
  }) {
    if (paths.isEmpty) return Future<void>.value();
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PhotoViewerScreen(
          paths: paths,
          initialIndex: initialIndex,
          semanticLabel: semanticLabel,
        ),
      ),
    );
  }

  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.paths.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, widget.paths.length - 1).toInt();
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasGallery = widget.paths.length > 1;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          hasGallery
              ? '${_currentIndex + 1} / ${widget.paths.length}'
              : widget.semanticLabel,
        ),
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.paths.length,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        itemBuilder: (_, index) => InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: SizedBox.expand(
            child: SafeFileImage(
              path: widget.paths[index],
              fit: BoxFit.contain,
              semanticLabel: '${widget.semanticLabel} ${index + 1}',
              enableFullscreen: false,
            ),
          ),
        ),
      ),
    );
  }
}
