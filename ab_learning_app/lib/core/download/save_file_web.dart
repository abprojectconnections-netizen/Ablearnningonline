import 'dart:js_interop';
import 'dart:typed_data';

extension type _BlobOptions._(JSObject _) implements JSObject {
  external factory _BlobOptions({JSString type});
}

@JS('Blob')
extension type _Blob._(JSObject _) implements JSObject {
  external factory _Blob(JSArray<JSAny> parts, _BlobOptions options);
}

@JS('URL.createObjectURL')
external JSString _createObjectUrl(_Blob blob);

@JS('URL.revokeObjectURL')
external void _revokeObjectUrl(JSString url);

@JS('document')
external _Document get _document;

extension type _Document._(JSObject _) implements JSObject {
  external _Anchor createElement(JSString tag);
  external _Element get body;
}

extension type _Element._(JSObject _) implements JSObject {
  external void append(JSObject node);
}

extension type _Anchor._(JSObject _) implements JSObject {
  external set href(JSString value);
  external set download(JSString value);
  external void click();
  external void remove();
}

/// Web: a temporary object URL clicked through an `<a download>` element,
/// so the browser saves the file with its own download UI.
Future<bool> saveFile(String filename, Uint8List bytes, String mimeType) async {
  try {
    final blob = _Blob(
      <JSAny>[bytes.toJS].toJS,
      _BlobOptions(type: mimeType.toJS),
    );
    final url = _createObjectUrl(blob);
    final anchor = _document.createElement('a'.toJS)
      ..href = url
      ..download = filename.toJS;
    _document.body.append(anchor);
    anchor.click();
    anchor.remove();
    _revokeObjectUrl(url);
    return true;
  } on Object {
    return false;
  }
}
