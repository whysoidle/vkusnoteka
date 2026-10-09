import 'dart:convert';
import 'package:flutter/material.dart';

class RecipePhoto extends StatelessWidget {
  // Reuse the same MemoryImage key across rebuilds and lazy list remounts.
  // Flutter keeps decoded frames; this bounded cache holds only compressed bytes.
  static final _images = <String, MemoryImage>{};
  static int _cachedBytes = 0;
  static MemoryImage _imageFor(String photo) {
    final cached = _images.remove(photo);
    if (cached != null) {
      _images[photo] = cached;
      return cached;
    }
    final image = MemoryImage(base64Decode(photo));
    _images[photo] = image;
    _cachedBytes += image.bytes.length;
    while (_images.length > 64 || _cachedBytes > 8 * 1024 * 1024) {
      _cachedBytes -= _images.remove(_images.keys.first)!.bytes.length;
    }
    return image;
  }

  final String photo;
  final double height;
  const RecipePhoto({super.key, required this.photo, this.height = 150});
  @override
  Widget build(BuildContext context) {
    Widget placeholder() => SizedBox(
      height: height,
      child: Center(
        child: Icon(
          Icons.restaurant,
          color: Theme.of(context).colorScheme.primary,
          size: 40,
        ),
      ),
    );
    try {
      if (photo.length > 200000) return placeholder();
      return ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Image(
          image: _imageFor(photo),
          gaplessPlayback: true,
          width: double.infinity,
          height: height,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => placeholder(),
        ),
      );
    } catch (_) {
      return placeholder();
    }
  }
}
