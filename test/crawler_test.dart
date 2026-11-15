import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_mentor/crawler/crawler.dart';
import 'package:focus_mentor/crawler/parser.dart';
import 'package:focus_mentor/models.dart';

const host = 'https://moodle.ucas.edu.ps';

FetchResult html(String url, String body) =>
    FetchResult(status: 200, finalUrl: url, contentType: 'text/html; charset=utf-8', body: body);

/// Fake Moodle: serves [site]; unknown URLs are 404. Tracks every request and the peak concurrency.
class FakeSite {
  final Map<String, FetchResult> site;
  final log = <String>[];
  int inFlight = 0;
  int peak = 0;
  FakeSite(this.site);

  Future<FetchResult> fetch(String url) async {
    log.add(url);
    inFlight++;
    peak = max(peak, inFlight);
    await Future.delayed(const Duration(milliseconds: 4));
    inFlight--;
    return site[url] ?? FetchResult(status: 404, finalUrl: url, contentType: 'text/html', body: 'not found');
  }
}

const courseHtml = '''
<html><body><div id="region-main"><h1>Calculus 1</h1><ul>
<li class="section course-section" data-sectionname="Week 1"><ul>
 <li><a href="/mod/resource/view.php?id=21"><span class="instancename">Lecture 1</span></a></li>
 <li><a href="/mod/folder/view.php?id=22"><span class="instancename">Slides</span></a></li>
 <li><a href="/mod/url/view.php?id=23"><span class="instancename">Khan</span></a></li>
 <li><a href="/mod/assign/view.php?id=24"><span class="instancename">HW1</span></a></li>
 <li><a href="/mod/page/view.php?id=25"><span class="instancename">Notes</span></a></li>
 <li><a href="/mod/resource/view.php?id=26"><span class="instancename">Missing</span></a></li>
</ul></li></ul></div></body></html>''';

FakeSite buildSite() => FakeSite({
      '$host/course/view.php?id=5': html('$host/course/view.php?id=5', courseHtml),
      '$host/mod/resource/view.php?id=21': FetchResult(
          status: 200,
          finalUrl: '$host/pluginfile.php/1/mod_resource/content/1/lec1.pdf',
          contentType: 'application/pdf'),
      '$host/mod/folder/view.php?id=22': html('$host/mod/folder/view.php?id=22', '''
        <div id="region-main">
          <a href="$host/pluginfile.php/2/mod_folder/content/0/a.pdf"><span class="fp-filename">a.pdf</span></a>
          <a href="$host/pluginfile.php/2/mod_folder/content/0/b.pptx"><span class="fp-filename">b.pptx</span></a>
        </div>'''),
      '$host/mod/url/view.php?id=23':
          FetchResult(status: 200, finalUrl: 'https://www.youtube.com/watch?v=q', contentType: 'text/html'),
      '$host/mod/page/view.php?id=25': html('$host/mod/page/view.php?id=25', '''
        <div id="region-main">
          <iframe src="https://www.youtube.com/embed/abc"></iframe>
          <a href="/pluginfile.php/1/mod_page/content/vid.mp4">video</a>
        </div>'''),
    });

Item find(Course c, String title) => c.allItems.firstWhere((i) => i.title == title);

void main() {
  test('Pool never exceeds its limit and finishes everything', () async {
    final pool = Pool(3);
    var running = 0, peak = 0, done = 0;
    await Future.wait(List.generate(25, (_) => pool.run(() async {
          running++;
          peak = max(peak, running);
          await Future.delayed(const Duration(milliseconds: 3));
          running--;
          done++;
        })));
    expect(done, 25);
    expect(peak, lessThanOrEqualTo(3));
  });

  test('crawls a course tree, resolving files, folders, urls and pages', () async {
    final site = buildSite();
    final tree = await Crawler(site.fetch).crawl([CourseLink('5', 'مادة 5', '$host/course/view.php?id=5')]);
    final c = tree.courses.single;

    expect(c.title, 'Calculus 1');
    expect(c.sections.single.title, 'Week 1');

    final lec = find(c, 'Lecture 1');
    expect(lec.kind, ItemKind.pdf);
    expect(lec.url, endsWith('lec1.pdf'));

    final slides = find(c, 'Slides');
    expect(slides.children.map((i) => i.kind).toList(), [ItemKind.pdf, ItemKind.document]);

    expect(find(c, 'Khan').kind, ItemKind.video);
    expect(find(c, 'Khan').url, 'https://www.youtube.com/watch?v=q');

    final notes = find(c, 'Notes');
    expect(notes.children.length, 2);
    expect(notes.children.every((i) => i.kind == ItemKind.video), isTrue);

    // leaves are not requested
    expect(find(c, 'HW1').kind, ItemKind.assignment);
    expect(site.log.any((u) => u.contains('/mod/assign/')), isFalse);
  });

  test('a failing page is retried once, recorded, and does not stop the crawl', () async {
    final site = buildSite();
    final tree = await Crawler(site.fetch).crawl([CourseLink('5', 'x', '$host/course/view.php?id=5')]);
    expect(tree.errors.length, 1);
    expect(tree.errors.single.url, contains('id=26'));
    expect(tree.errors.single.reason, 'HTTP 404');
    expect(site.log.where((u) => u.contains('id=26')).length, 2);
    expect(find(tree.courses.single, 'Missing').kind, ItemKind.file);
  });

  test('never requests other sites', () async {
    final site = buildSite();
    await Crawler(site.fetch).crawl([CourseLink('5', 'x', '$host/course/view.php?id=5')]);
    expect(site.log.every((u) => u.startsWith(host)), isTrue);
  });

  test('every page is requested at most once per attempt (no duplicates)', () async {
    final site = buildSite();
    await Crawler(site.fetch).crawl([CourseLink('5', 'x', '$host/course/view.php?id=5')]);
    final counts = <String, int>{};
    for (final u in site.log) {
      counts[u] = (counts[u] ?? 0) + 1;
    }
    counts.forEach((u, n) {
      expect(n, u.contains('id=26') ? 2 : 1, reason: u);
    });
  });

  test('requests run in parallel but stay under the concurrency limit', () async {
    final items = [for (var i = 0; i < 30; i++) '<li><a href="/mod/folder/view.php?id=${100 + i}"><span class="instancename">F$i</span></a></li>'];
    final site = FakeSite({
      '$host/course/view.php?id=9': html('$host/course/view.php?id=9',
          '<div id="region-main"><li class="section course-section" data-sectionname="S"><ul>${items.join()}</ul></li></div>'),
      for (var i = 0; i < 30; i++)
        '$host/mod/folder/view.php?id=${100 + i}': html('$host/mod/folder/view.php?id=${100 + i}',
            '<div id="region-main"><a href="/pluginfile.php/1/f/$i.pdf">$i.pdf</a></div>'),
    });
    final tree = await Crawler(site.fetch, concurrency: 4).crawl([CourseLink('9', 'x', '$host/course/view.php?id=9')]);
    expect(site.peak, greaterThan(1));
    expect(site.peak, lessThanOrEqualTo(4));
    expect(tree.courses.single.allItems.where((i) => i.kind == ItemKind.pdf).length, 30);
    expect(tree.errors, isEmpty);
  });

  test('several courses are crawled at the same time', () async {
    final site = FakeSite({
      for (final id in ['1', '2', '3'])
        '$host/course/view.php?id=$id': html('$host/course/view.php?id=$id',
            '<div id="region-main"><h1>C$id</h1><li class="section course-section" data-sectionname="S"><a href="/mod/page/view.php?id=${id}0">p</a></li></div>'),
    });
    final tree = await Crawler(site.fetch).crawl([
      for (final id in ['1', '2', '3']) CourseLink(id, 'x', '$host/course/view.php?id=$id'),
    ]);
    expect(tree.courses.map((c) => c.title).toList(), ['C1', 'C2', 'C3']);
    expect(site.peak, greaterThan(1));
  });

  test('section pages are merged into the course', () async {
    final site = FakeSite({
      '$host/course/view.php?id=4': html('$host/course/view.php?id=4', '''
        <div id="region-main"><h1>C4</h1>
        <a href="/course/view.php?id=4&section=1">One</a>
        <li class="section course-section" data-sectionname="Intro"><a href="/mod/assign/view.php?id=1">A</a></li></div>'''),
      '$host/course/view.php?id=4&section=1': html('$host/course/view.php?id=4&section=1', '''
        <div id="region-main"><h1>C4</h1>
        <li class="section course-section" data-sectionname="Topic 1"><a href="/mod/quiz/view.php?id=2">Q</a></li></div>'''),
    });
    final tree = await Crawler(site.fetch).crawl([CourseLink('4', 'x', '$host/course/view.php?id=4')]);
    expect(tree.courses.single.sections.map((s) => s.title).toList(), ['Intro', 'Topic 1']);
  });
}
