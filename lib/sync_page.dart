import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'crawler/classify.dart';
import 'crawler/crawler.dart';
import 'crawler/parser.dart';
import 'crawler/webview_fetcher.dart';
import 'storage.dart';
import 'theme.dart';
import 'tree_page.dart';

enum _Phase { login, discover, crawl, error }

// Logged in when Moodle shows a logout link (it is in the user menu of every page)
const _loggedInJs = '''(function(){return !!document.querySelector('a[href*="logout.php"]');})()''';

// Course links from the RENDERED page (the course list is filled in by JavaScript)
const _courseLinksJs = r'''
(function(){
  var m = {};
  document.querySelectorAll('a[href*="/course/view.php?id="]').forEach(function(a){
    var id = (a.href.match(/[?&]id=(\d+)/) || [])[1];
    if (!id) return;
    var t = (a.innerText || a.textContent || '').replace(/\s+/g, ' ').trim();
    if (!m[id] || t.length > m[id].length) m[id] = t;
  });
  return JSON.stringify(Object.keys(m).map(function(k){ return {id: k, title: m[k]}; }));
})()
''';

dynamic _decode(Object r) {
  final s = r.toString();
  if (s == 'null') return null;
  dynamic d = jsonDecode(s);
  if (d is String) d = jsonDecode(d);
  return d;
}

/// Login (once) -> find the courses -> parallel crawl -> save -> show the tree
class SyncPage extends StatefulWidget {
  const SyncPage({super.key});
  @override
  State<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends State<SyncPage> {
  late final WebViewController web;
  late final WebViewFetcher fetcher;
  _Phase phase = _Phase.login;
  bool _busy = false;
  CrawlProgress? progress;
  String? message;

  @override
  void initState() {
    super.initState();
    web = WebViewController();
    fetcher = WebViewFetcher(web)..attachChannel();
    web
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (r) {
          final u = Uri.tryParse(r.url);
          final ok = u == null || !u.scheme.startsWith('http') || isMoodleHost(u.host);
          return ok ? NavigationDecision.navigate : NavigationDecision.prevent;
        },
        onPageFinished: _onFinished,
      ))
      ..loadRequest(Uri.parse('${moodleBase}login/index.php'));
  }

  Future<void> _onFinished(String url) async {
    if (!isMoodleHost(Uri.tryParse(url)?.host ?? '')) return;
    await fetcher.install();
    if (phase == _Phase.login) {
      final r = await web.runJavaScriptReturningResult(_loggedInJs);
      if (r.toString() == 'true') {
        if (!mounted) return;
        setState(() => phase = _Phase.discover);
        web.loadRequest(Uri.parse('${moodleBase}my/courses.php'));
      }
    } else if (phase == _Phase.discover && !_busy) {
      _discoverAndCrawl();
    }
  }

  Future<List<CourseLink>> _linksFromPage() async {
    try {
      final d = _decode(await web.runJavaScriptReturningResult(_courseLinksJs));
      if (d is! List) return [];
      return [
        for (final e in d)
          CourseLink(
            '${e['id']}',
            (e['title'] as String).isEmpty ? 'مادة ${e['id']}' : e['title'] as String,
            '${moodleBase}course/view.php?id=${e['id']}',
          ),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> _discoverAndCrawl() async {
    if (_busy) return;
    _busy = true;
    setState(() {
      phase = _Phase.discover;
      message = null;
    });
    var links = <CourseLink>[];
    for (var i = 0; i < 12 && links.isEmpty; i++) {
      links = await _linksFromPage();
      if (links.isEmpty) await Future.delayed(const Duration(seconds: 1));
    }
    if (!mounted) return;
    if (links.isEmpty) {
      setState(() {
        phase = _Phase.error;
        message = 'لم أجد روابط مواد في هذه الصفحة. افتح صفحة «مقرراتي» ثم اضغط «استخراج المواد».';
      });
      _busy = false;
      return;
    }
    setState(() => phase = _Phase.crawl);
    try {
      final tree = await Crawler(fetcher.fetch).crawl(links, onProgress: (p) {
        if (mounted) setState(() => progress = p);
      });
      await saveTree(tree);
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => TreePage(tree: tree)));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        phase = _Phase.error;
        message = 'تعطّل الزحف: $e';
      });
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final showWeb = phase != _Phase.crawl;
    return Scaffold(
      appBar: AppBar(title: Text(showWeb ? 'تسجيل الدخول إلى مودل' : 'جارٍ قراءة المواد')),
      body: Stack(children: [
        // The WebView stays alive during the crawl (it carries the login session), shrunk to 2x2 px
        Positioned(
          left: 0,
          top: 0,
          right: showWeb ? 0 : null,
          bottom: showWeb ? 0 : null,
          width: showWeb ? null : 2,
          height: showWeb ? null : 2,
          child: WebViewWidget(key: const ValueKey('moodle-web'), controller: web),
        ),
        if (showWeb)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: cardBox(),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  message ??
                      (phase == _Phase.discover
                          ? 'جارٍ البحث عن موادك…'
                          : 'سجّل دخولك. بعد نجاح الدخول سيبدأ الاستيراد تلقائياً.'),
                  style: const TextStyle(height: 1.4),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy && phase == _Phase.discover ? null : _discoverAndCrawl,
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('استخراج المواد من هذه الصفحة'),
                ),
              ]),
            ),
          ),
        if (!showWeb) Positioned.fill(child: Container(color: kBg, child: _progressView())),
      ]),
    );
  }

  Widget _progressView() {
    final p = progress;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const LinearProgressIndicator(color: kOlive, backgroundColor: kSurface2),
        const SizedBox(height: 22),
        Text('تمت قراءة ${p?.fetched ?? 0} صفحة', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text('قيد الانتظار: ${p?.pending ?? 0}   ·   أخطاء: ${p?.failed ?? 0}'),
        const SizedBox(height: 14),
        Text(
          p?.last ?? '',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textDirection: TextDirection.ltr,
          style: const TextStyle(fontSize: 11.5, color: kBrown),
        ),
      ]),
    );
  }
}
