import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

class ImageOptimizer {
  /// Compresses an image file from the given path.
  /// If width is greater than 1024px, it resizes it down to 1024px (maintaining aspect ratio).
  /// Encodes the output as JPEG with 80% quality.
  static Future<List<int>> compressImage(String filePath) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    return compressBytes(bytes);
  }

  /// Web-safe variant: compress already-loaded image bytes (no dart:io File).
  /// Use with `XFile.readAsBytes()` so it works on web AND mobile.
  static Future<List<int>> compressBytes(List<int> bytes) async {
    final Uint8List input = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    try {
      final decoded = img.decodeImage(input);
      if (decoded == null) return input;

      img.Image resized = decoded;
      if (decoded.width > 1024) {
        resized = img.copyResize(decoded, width: 1024);
      }

      return img.encodeJpg(resized, quality: 80);
    } catch (e) {
      // Return original bytes on error to prevent blocking user upload flow
      return input;
    }
  }
}
