import 'dart:typed_data';

import 'save_file_io.dart'
    if (dart.library.js_interop) 'save_file_web.dart' as impl;

/// Hands [bytes] to the user as a file named [filename]. Returns false when
/// this platform cannot save files from the app yet.
Future<bool> saveFile(String filename, Uint8List bytes, String mimeType) =>
    impl.saveFile(filename, bytes, mimeType);
