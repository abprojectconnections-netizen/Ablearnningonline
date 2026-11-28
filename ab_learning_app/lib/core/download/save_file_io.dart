import 'dart:typed_data';

/// Mobile and desktop: not supported yet (needs a file picker or share
/// sheet). Callers tell the user to download from the web app instead.
Future<bool> saveFile(String filename, Uint8List bytes, String mimeType) async {
  return false;
}
