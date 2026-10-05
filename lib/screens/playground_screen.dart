// Conditional import: web (js + wasm) gets the real playground, mobile the stub
export 'playground_stub.dart'
    if (dart.library.js_interop) 'playground_web.dart';
