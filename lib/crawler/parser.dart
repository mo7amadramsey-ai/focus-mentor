import 'package:html/dom.dart';
import 'package:html/parser.dart' show parse;
import '../models.dart';
import 'classify.dart';

/// A raw link found in a page
class Found {
  final String title;
  final String url;
  Found(this.title, this.url);
}

class CourseLink {
  final String id;
  final String title;
  final String url;
  CourseLink(this.id, this.title, this.url);
}

class CoursePage {
  final String? title;
  final List<Section> sections;
  final List<String> sectionPageUrls;
  CoursePage(this.title, this.sections, this.sectionPageUrls);
}

String cleanText(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Resolves an href against the page URL: http(s) only, no fragment.
String? normalizeUrl(String? href, Uri base) {
  if (href == null) return null;
  final h = href.trim();
  if (h.isEmpty || h.startsWith('#') || h.startsWith('javascript:') || h.startsWith('mailto:') || h.startsWith('tel:')) {
    return null;
  }
  Uri u;
  try {
    u = base.resolve(h);
  } catch (_) {
    return null;
  }
  if (u.scheme != 'http' && u.scheme != 'https') return null;
  return u.removeFragment().toString();
}

const _skipClasses = {
  'action-menu', 'activity-actions', 'moodle-actionmenu', 'dropdown-menu', 'availabilityinfo',
  'drawer', 'courseindex', 'breadcrumb', 'activity-navigation', 'secondary-navigation',
  'primary-navigation', 'navbar', 'modchooser', 'section-controls', 'course-section-header-controls',
};
const _skipTags = {'nav', 'footer', 'aside', 'header'};
const _ignoredHosts = {
  'moodle.org', 'docs.moodle.org', 'download.moodle.org', 'play.google.com', 'apps.apple.com', 'itunes.apple.com',
};

bool _inSkipped(Element e) {
  Element? c = e;
  while (c != null) {
    if (_skipTags.contains(c.localName)) return true;
    for (final k in c.classes) {
      if (_skipClasses.contains(k)) return true;
    }
    c = c.parent;
  }
  return false;
}

/// Visible title of a link (hidden accessibility text removed)
String anchorTitle(Element a) {
  final inst = a.querySelector('.instancename');
  final src = (inst ?? a).clone(true);
  for (final h in src.querySelectorAll('.accesshide, .sr-only, .visually-hidden')) {
    h.remove();
  }
  var t = cleanText(src.text);
  if (t.isEmpty) t = cleanText(a.attributes['title'] ?? a.attributes['aria-label'] ?? '');
  return t;
}

/// A Moodle /mod/<name>/view.php activity link?
bool isModView(Uri u) => RegExp(r'/mod/[a-z0-9_]+/view\.php$').hasMatch(u.path);

/// Is this link worth keeping as an item? (an activity, a Moodle file, or an external site)
bool _isInteresting(String url) {
  final u = Uri.tryParse(url);
  if (u == null) return false;
  if (isMoodleHost(u.host)) {
    return isModView(u) || u.path.contains('pluginfile.php');
  }
  return !_ignoredHosts.contains(u.host.toLowerCase());
}

String _youtubeWatch(String url) {
  final u = Uri.tryParse(url);
  if (u == null) return url;
  if (isYoutube(u.host) && u.pathSegments.length >= 2 && u.pathSegments.first == 'embed') {
    return 'https://www.youtube.com/watch?v=${u.pathSegments[1]}';
  }
  return url;
}

/// Anchors + embedded media (iframe / video / source) inside [scope]
List<Found> _collect(Element scope, Uri base, {String? exclude}) {
  final out = <String, Found>{};
  void add(String url, String title) {
    if (url == exclude || !_isInteresting(url)) return;
    final old = out[url];
    if (old == null) {
      out[url] = Found(title, url);
    } else if (old.title.length < title.length) {
      out[url] = Found(title, url);
    }
  }

  for (final a in scope.querySelectorAll('a[href]')) {
    if (_inSkipped(a)) continue;
    final url = normalizeUrl(a.attributes['href'], base);
    if (url == null) continue;
    add(url, anchorTitle(a));
  }
  for (final e in scope.querySelectorAll('iframe[src], video[src], source[src], embed[src], object[data]')) {
    if (_inSkipped(e)) continue;
    final raw = e.attributes['src'] ?? e.attributes['data'];
    var url = normalizeUrl(raw, base);
    if (url == null) continue;
    url = _youtubeWatch(url);
    final t = cleanText(e.attributes['title'] ?? '');
    add(url, t);
  }
  return out.values.toList();
}

Item _toItem(Found f) {
  var title = f.title;
  if (title.isEmpty) {
    final u = Uri.tryParse(f.url);
    title = (u != null && u.pathSegments.isNotEmpty) ? Uri.decodeComponent(u.pathSegments.last) : f.url;
  }
  return Item(title: title, url: f.url, kind: classifyUrl(f.url));
}

Element _main(Document doc) => doc.querySelector('#region-main') ?? doc.querySelector('[role=main]') ?? doc.body!;

/// Course links on a page (for the home / my-courses pages), unique by course id
List<CourseLink> parseCourseLinks(String html, Uri base) {
  final doc = parse(html);
  final byId = <String, CourseLink>{};
  for (final a in doc.querySelectorAll('a[href]')) {
    final url = normalizeUrl(a.attributes['href'], base);
    if (url == null) continue;
    final u = Uri.parse(url);
    if (!u.path.endsWith('/course/view.php')) continue;
    final id = u.queryParameters['id'];
    if (id == null || id.isEmpty) continue;
    final t = anchorTitle(a);
    final old = byId[id];
    if (old == null || old.title.length < t.length) {
      byId[id] = CourseLink(id, t.isEmpty ? 'مادة $id' : t, '${u.origin}/course/view.php?id=$id');
    }
  }
  return byId.values.toList();
}

/// Course page -> sections with their items (+ extra section pages for "one section per page" formats)
CoursePage parseCoursePage(String html, Uri base, String courseId) {
  final doc = parse(html);

  String? title;
  final h1 = doc.querySelector('h1');
  if (h1 != null && cleanText(h1.text).isNotEmpty) {
    title = cleanText(h1.text);
  } else {
    final t = doc.querySelector('title')?.text;
    if (t != null && cleanText(t).isNotEmpty) title = cleanText(t.split(RegExp(r'\s[|\-–]\s')).first);
  }

  // Section elements (skip ones nested inside another section element)
  final all = doc.querySelectorAll('li.section, section.course-section, div.course-section').toSet();
  final secEls = all.where((e) {
    Element? p = e.parent;
    while (p != null) {
      if (all.contains(p)) return false;
      p = p.parent;
    }
    return true;
  }).toList();

  final sections = <Section>[];
  if (secEls.isNotEmpty) {
    var n = 0;
    for (final el in secEls) {
      n++;
      var name = cleanText(el.attributes['data-sectionname'] ?? '');
      if (name.isEmpty) {
        final h = el.querySelector('.sectionname') ?? el.querySelector('h3') ?? el.querySelector('h2');
        if (h != null) name = cleanText(h.text);
      }
      if (name.isEmpty) name = 'القسم $n';
      final items = _collect(el, base).map(_toItem).toList();
      if (items.isNotEmpty) sections.add(Section(title: name, items: items));
    }
  } else {
    final items = _collect(_main(doc), base).map(_toItem).toList();
    if (items.isNotEmpty) sections.add(Section(title: 'عام', items: items));
  }

  // Links to other pages of the same course (one section per page)
  final secPages = <String>{};
  for (final a in doc.querySelectorAll('a[href]')) {
    final url = normalizeUrl(a.attributes['href'], base);
    if (url == null) continue;
    final u = Uri.parse(url);
    if (u.path.endsWith('/course/view.php') && u.queryParameters['id'] == courseId && u.queryParameters.containsKey('section')) {
      secPages.add(url);
    }
  }
  secPages.remove(base.removeFragment().toString());
  return CoursePage(title, sections, secPages.take(60).toList());
}

/// Folder page -> files
List<Item> parseFolderPage(String html, Uri base) {
  final doc = parse(html);
  final scope = _main(doc);
  final out = <Item>[];
  final seen = <String>{};
  for (final a in scope.querySelectorAll('a[href*="pluginfile.php"]')) {
    final url = normalizeUrl(a.attributes['href'], base);
    if (url == null || !seen.add(url)) continue;
    out.add(_toItem(Found(anchorTitle(a), url)));
  }
  return out;
}

/// Page / label content -> links, files and embedded videos (except [self])
List<Item> parsePageLinks(String html, Uri base, {String? self}) {
  final doc = parse(html);
  return _collect(_main(doc), base, exclude: self ?? base.removeFragment().toString()).map(_toItem).toList();
}

/// Book -> chapters
List<Item> parseBookChapters(String html, Uri base) {
  final doc = parse(html);
  final out = <Item>[];
  final seen = <String>{};
  for (final a in doc.querySelectorAll('a[href*="/mod/book/view.php"]')) {
    final url = normalizeUrl(a.attributes['href'], base);
    if (url == null || !url.contains('chapterid=') || !seen.add(url)) continue;
    final t = anchorTitle(a);
    out.add(Item(title: t.isEmpty ? 'فصل' : t, url: url, kind: ItemKind.page));
  }
  return out;
}

/// "URL" activity page -> external target (when the page is shown instead of redirecting)
String? parseUrlTarget(String html, Uri base) {
  final doc = parse(html);
  final scopes = <Element>[
    ...doc.querySelectorAll('.urlworkaround'),
    _main(doc),
  ];
  for (final s in scopes) {
    for (final a in s.querySelectorAll('a[href]')) {
      if (_inSkipped(a)) continue;
      final url = normalizeUrl(a.attributes['href'], base);
      if (url == null) continue;
      final u = Uri.parse(url);
      if (!isMoodleHost(u.host) && !_ignoredHosts.contains(u.host.toLowerCase())) return url;
    }
  }
  return null;
}

/// "File" activity page (when it is an HTML page, not a redirect) -> the real file
String? parseResourceTarget(String html, Uri base) {
  final doc = parse(html);
  final scope = _main(doc);
  for (final e in scope.querySelectorAll('object[data], iframe[src], embed[src], video[src], source[src], a[href*="pluginfile.php"]')) {
    final raw = e.attributes['data'] ?? e.attributes['src'] ?? e.attributes['href'];
    final url = normalizeUrl(raw, base);
    if (url != null && url.contains('pluginfile.php')) return url;
  }
  return null;
}
