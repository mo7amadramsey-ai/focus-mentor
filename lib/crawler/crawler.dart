import 'dart:async';
import '../models.dart';
import 'classify.dart';
import 'parser.dart';

/// What a fetch returns. [body] is null for non-HTML responses (files are never downloaded).
class FetchResult {
  final int status;
  final String finalUrl;
  final String contentType;
  final String? body;
  final String? error;
  FetchResult({required this.status, required this.finalUrl, this.contentType = '', this.body, this.error});
  bool get ok => status >= 200 && status < 400 && error == null;
  bool get isHtml => contentType.toLowerCase().contains('html');
}

typedef Fetcher = Future<FetchResult> Function(String url);

class CrawlProgress {
  int fetched = 0;
  int pending = 0;
  int failed = 0;
  int items = 0;
  String last = '';
}

/// Limits how many tasks run at the same time
class Pool {
  final int limit;
  int _running = 0;
  final _queue = <Completer<void>>[];
  Pool(this.limit);

  Future<T> run<T>(Future<T> Function() task) async {
    if (_running >= limit) {
      final c = Completer<void>();
      _queue.add(c);
      await c.future;
    } else {
      _running++;
    }
    try {
      return await task();
    } finally {
      if (_queue.isNotEmpty) {
        _queue.removeAt(0).complete(); // hand the slot to the next waiter
      } else {
        _running--;
      }
    }
  }
}

/// Parallel breadth-first crawler: every course starts at once, and each page spawns its children
/// immediately; the shared [Pool] keeps the number of simultaneous requests low.
class Crawler {
  final Fetcher fetch;
  final int concurrency;
  final int maxPages;
  final int maxDepth;
  Crawler(this.fetch, {this.concurrency = 6, this.maxPages = 3000, this.maxDepth = 4});

  late Pool _pool;
  final _visited = <String>{};
  final _errors = <CrawlError>[];
  final _progress = CrawlProgress();
  void Function(CrawlProgress)? _onProgress;

  Future<Tree> crawl(List<CourseLink> links, {void Function(CrawlProgress)? onProgress}) async {
    _pool = Pool(concurrency);
    _visited.clear();
    _errors.clear();
    _onProgress = onProgress;
    final courses = [for (final l in links) Course(id: l.id, title: l.title, url: l.url)];
    await Future.wait(courses.map(_crawlCourse));
    return Tree(fetchedAt: DateTime.now(), courses: courses, errors: List.of(_errors));
  }

  void _tick({String? last}) {
    if (last != null) _progress.last = last;
    _onProgress?.call(_progress);
  }

  /// One request through the pool with a single retry; null when it failed (the error is recorded)
  Future<FetchResult?> _get(String url) async {
    if (_visited.length >= maxPages) {
      _errors.add(CrawlError(url, 'تجاوز حد الصفحات'));
      return null;
    }
    _progress.pending++;
    _tick();
    FetchResult? r;
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        final res = await _pool.run<FetchResult>(() => fetch(url));
        r = res;
        if (res.ok) break;
      }
    } catch (e) {
      r = FetchResult(status: 0, finalUrl: url, error: '$e');
    }
    _progress.pending--;
    _progress.fetched++;
    if (r == null || !r.ok) {
      _progress.failed++;
      _errors.add(CrawlError(url, r?.error ?? 'HTTP ${r?.status}'));
      _tick(last: url);
      return null;
    }
    _tick(last: url);
    return r;
  }

  Future<void> _crawlCourse(Course course) async {
    _visited.add(course.url);
    final r = await _get(course.url);
    if (r == null || r.body == null) return;
    final base = Uri.parse(r.finalUrl);
    final page = parseCoursePage(r.body!, base, course.id);
    if (page.title != null && page.title!.isNotEmpty) course.title = page.title!;
    course.sections.addAll(page.sections);

    // other section pages of the same course, fetched in parallel
    await Future.wait(page.sectionPageUrls.where(_visited.add).map((u) async {
      final sr = await _get(u);
      if (sr == null || sr.body == null) return;
      final sp = parseCoursePage(sr.body!, Uri.parse(sr.finalUrl), course.id);
      _merge(course.sections, sp.sections);
    }));

    // resolve every item that needs another request, all at once
    final jobs = <Future<void>>[];
    for (final s in course.sections) {
      for (final i in s.items) {
        jobs.add(_resolve(i, 1));
      }
    }
    await Future.wait(jobs);
    _progress.items += course.allItems.length;
    _tick();
  }

  void _merge(List<Section> into, List<Section> from) {
    for (final s in from) {
      final i = into.indexWhere((x) => x.title == s.title);
      if (i < 0) {
        into.add(s);
        continue;
      }
      final have = into[i].items.map((e) => e.url).toSet();
      into[i].items.addAll(s.items.where((e) => !have.contains(e.url)));
    }
  }

  /// Follows one item according to its kind (folders list files, pages list links, "file"/"url"
  /// activities are resolved to their real target). Other kinds are leaves.
  Future<void> _resolve(Item item, int depth) async {
    if (depth > maxDepth) return;
    switch (item.kind) {
      case ItemKind.folder:
      case ItemKind.page:
      case ItemKind.book:
      case ItemKind.file:
      case ItemKind.link:
        break;
      default:
        return;
    }
    final u = Uri.tryParse(item.url);
    if (u == null || !isMoodleHost(u.host)) return; // never request other sites
    if (u.path.contains('pluginfile.php') && item.kind == ItemKind.file) return; // already a real file
    if (!_visited.add(item.url)) return;

    final r = await _get(item.url);
    if (r == null) return;
    final base = Uri.parse(r.finalUrl);

    if (item.kind == ItemKind.file) {
      if (!r.isHtml || r.body == null) {
        // redirected straight to the file (the body was not downloaded)
        final k = classifyUrl(r.finalUrl);
        item.kind = k == ItemKind.link || k == ItemKind.other ? ItemKind.file : k;
        item.url = r.finalUrl;
      } else {
        final t = parseResourceTarget(r.body!, base);
        if (t != null) {
          item.url = t;
          final k = classifyUrl(t);
          if (k != ItemKind.other) item.kind = k;
        }
      }
      return;
    }

    if (item.kind == ItemKind.link) {
      final host = base.host;
      if (!isMoodleHost(host)) {
        // Moodle redirected to the external site
        item.url = r.finalUrl;
        item.kind = classifyUrl(r.finalUrl);
      } else if (r.body != null) {
        final t = parseUrlTarget(r.body!, base);
        if (t != null) {
          item.url = t;
          item.kind = classifyUrl(t);
        }
      }
      return;
    }

    if (r.body == null) return;
    List<Item> kids;
    switch (item.kind) {
      case ItemKind.folder:
        kids = parseFolderPage(r.body!, base);
        break;
      case ItemKind.book:
        kids = parseBookChapters(r.body!, base);
        break;
      default:
        kids = parsePageLinks(r.body!, base, self: item.url);
    }
    item.children.addAll(kids);
    await Future.wait(kids.map((k) => _resolve(k, depth + 1)));
  }
}
