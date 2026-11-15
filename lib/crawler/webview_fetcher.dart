import 'dart:async';
import 'dart:convert';
import 'package:webview_flutter/webview_flutter.dart';
import 'crawler.dart';

/// Fetches pages by running fetch() INSIDE the logged-in Moodle WebView, so the session cookies
/// (even HttpOnly ones) are used automatically. HTML bodies come back as text; files are never
/// downloaded (the request is aborted after the headers).
class WebViewFetcher {
  final WebViewController controller;
  WebViewFetcher(this.controller);

  static const channelName = 'CRAWL';
  static const _installJs = r'''
window.__cf = async function(id, url) {
  var send = function(o) { CRAWL.postMessage(JSON.stringify(o)); };
  try {
    var ctl = new AbortController();
    var r = await fetch(url, {credentials: 'include', redirect: 'follow', signal: ctl.signal});
    var ct = r.headers.get('content-type') || '';
    var body = null;
    if (ct.indexOf('html') > -1) { body = await r.text(); } else { ctl.abort(); }
    send({id: id, s: r.status, u: r.url, c: ct, b: body});
  } catch (e) {
    send({id: id, s: 0, u: url, c: '', b: null, e: String(e)});
  }
};
''';

  final _waiting = <int, Completer<FetchResult>>{};
  int _next = 1;

  /// Add this to the WebViewController BEFORE loading a page
  void attachChannel() {
    controller.addJavaScriptChannel(channelName, onMessageReceived: (m) {
      try {
        final j = jsonDecode(m.message) as Map<String, dynamic>;
        final c = _waiting.remove(j['id'] as int);
        c?.complete(FetchResult(
          status: (j['s'] as num).toInt(),
          finalUrl: j['u'] as String,
          contentType: (j['c'] as String?) ?? '',
          body: j['b'] as String?,
          error: j['e'] as String?,
        ));
      } catch (_) {}
    });
  }

  /// Call after a Moodle page has loaded (the JS function lives in that page)
  Future<void> install() => controller.runJavaScript(_installJs);

  Future<FetchResult> fetch(String url) {
    final id = _next++;
    final c = Completer<FetchResult>();
    _waiting[id] = c;
    controller.runJavaScript('window.__cf($id, ${jsonEncode(url)});');
    return c.future.timeout(const Duration(seconds: 30), onTimeout: () {
      _waiting.remove(id);
      return FetchResult(status: 0, finalUrl: url, error: 'timeout');
    });
  }
}
