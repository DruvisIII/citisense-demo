import 'dart:js_interop';

@JS('window.location.assign')
external void _assign(JSString url);

/// Navigates this tab to [url] (the browser Back button returns here).
void openUrlSameTab(String url) => _assign(url.toJS);
