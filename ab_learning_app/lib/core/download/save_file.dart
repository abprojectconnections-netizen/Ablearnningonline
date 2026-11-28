/// `saveFile(filename, bytes, mimeType)` hands bytes to the user as a file
/// and returns false when this platform cannot save files from the app yet.
library;

export 'save_file_io.dart' if (dart.library.js_interop) 'save_file_web.dart';
