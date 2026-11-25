// Opens a web address in the SAME browser tab (no popup, so Safari on
// iPhone does not block it). Web uses window.location; other platforms
// get a no-op stub because the demo is only built for the web.
export 'open_url_stub.dart' if (dart.library.js_interop) 'open_url_web.dart';
