import 'dart:io';
import 'package:image/image.dart' as img;

class ImageOptimizer {
  /// Compresses an image file from the given path.
  /// If width is greater than 1024px, it resizes it down to 1024px (maintaining aspect ratio).
  /// Encodes the output as JPEG with 80% quality.
  static Future<List<int>> compressImage(String filePath) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return bytes;
      
      img.Image resized = decoded;
      if (decoded.width > 1024) {
        resized = img.copyResize(decoded, width: 1024);
      }
      
      return img.encodeJpg(resized, quality: 80);
    } catch (e) {
      // Return original bytes on error to prevent blocking user upload flow
      return bytes;
    }
  }
}
