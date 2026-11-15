import 'package:flutter_test/flutter_test.dart';
import 'package:focus_mentor/crawler/classify.dart';
import 'package:focus_mentor/crawler/parser.dart';
import 'package:focus_mentor/models.dart';

final base = Uri.parse('https://moodle.ucas.edu.ps/course/view.php?id=5');

const courseHtml = '''
<html><head><title>Calculus 1: Course | UCAS</title></head><body>
<nav><a href="/my/">Dashboard</a><a href="/mod/forum/view.php?id=77">nav forum</a></nav>
<div id="region-main"><h1>Calculus 1</h1>
<ul>
<li id="section-0" class="section course-section" data-sectionname="General">
  <ul><li class="activity forum"><a class="aalink" href="https://moodle.ucas.edu.ps/mod/forum/view.php?id=11"><span class="instancename">Announcements <span class="accesshide"> Forum</span></span></a></li></ul>
</li>
<li id="section-1" class="section course-section" data-sectionname="Week 1">
  <ul>
    <li class="activity resource">
      <a href="https://moodle.ucas.edu.ps/mod/resource/view.php?id=21"><span class="instancename">Lecture 1 <span class="accesshide"> File</span></span></a>
      <div class="action-menu"><a href="https://moodle.ucas.edu.ps/course/mod.php?sesskey=x&amp;delete=21">Delete</a></div>
    </li>
    <li class="activity folder"><a href="/mod/folder/view.php?id=22"><span class="instancename">Slides</span></a></li>
    <li class="activity url"><a href="/mod/url/view.php?id=23"><span class="instancename">Khan Academy</span></a></li>
    <li class="activity assign">
      <a href="/mod/assign/view.php?id=24"><img alt="" src="x.png"></a>
      <a href="/mod/assign/view.php?id=24"><span class="instancename">Homework 1</span></a>
    </li>
    <li class="activity label"><div class="summarytext">
      <a href="https://www.youtube.com/watch?v=abc123">Intro video</a>
      <iframe src="https://www.youtube.com/embed/xyz789" title="Embedded"></iframe>
    </div></li>
  </ul>
</li>
<li id="section-2" class="section course-section" data-sectionname="Week 2">
  <div class="availabilityinfo"><a href="/mod/quiz/view.php?id=99">Restriction quiz</a></div>
  <ul><li class="activity quiz"><a href="/mod/quiz/view.php?id=31"><span class="instancename">Quiz 1</span></a></li></ul>
</li>
</ul></div>
<footer><a href="https://moodle.org">Moodle</a></footer>
</body></html>''';

void main() {
  group('classifyUrl', () {
    test('by extension', () {
      expect(classifyUrl('https://moodle.ucas.edu.ps/pluginfile.php/1/a/b/lec.pdf'), ItemKind.pdf);
      expect(classifyUrl('https://moodle.ucas.edu.ps/pluginfile.php/1/a/b/vid.MP4?forcedownload=1'), ItemKind.video);
      expect(classifyUrl('https://moodle.ucas.edu.ps/pluginfile.php/1/a/b/s.pptx'), ItemKind.document);
      expect(classifyUrl('https://moodle.ucas.edu.ps/pluginfile.php/1/a/b/all.zip'), ItemKind.file);
      expect(classifyUrl('https://moodle.ucas.edu.ps/pluginfile.php/1/a/b/noext'), ItemKind.file);
    });
    test('by Moodle module', () {
      expect(classifyUrl('https://moodle.ucas.edu.ps/mod/assign/view.php?id=1'), ItemKind.assignment);
      expect(classifyUrl('https://moodle.ucas.edu.ps/mod/quiz/view.php?id=1'), ItemKind.quiz);
      expect(classifyUrl('https://moodle.ucas.edu.ps/mod/folder/view.php?id=1'), ItemKind.folder);
      expect(classifyUrl('https://moodle.ucas.edu.ps/mod/page/view.php?id=1'), ItemKind.page);
      expect(classifyUrl('https://moodle.ucas.edu.ps/mod/book/view.php?id=1'), ItemKind.book);
      expect(classifyUrl('https://moodle.ucas.edu.ps/mod/forum/view.php?id=1'), ItemKind.forum);
      expect(classifyUrl('https://moodle.ucas.edu.ps/mod/resource/view.php?id=1'), ItemKind.file);
      expect(classifyUrl('https://moodle.ucas.edu.ps/mod/url/view.php?id=1'), ItemKind.link);
    });
    test('external', () {
      expect(classifyUrl('https://www.youtube.com/watch?v=abc'), ItemKind.video);
      expect(classifyUrl('https://youtu.be/abc'), ItemKind.video);
      expect(classifyUrl('https://example.com/page'), ItemKind.link);
    });
  });

  group('normalizeUrl', () {
    test('resolves, drops fragments, rejects non-http', () {
      expect(normalizeUrl('/mod/page/view.php?id=2#x', base), 'https://moodle.ucas.edu.ps/mod/page/view.php?id=2');
      expect(normalizeUrl('javascript:void(0)', base), isNull);
      expect(normalizeUrl('#section-3', base), isNull);
      expect(normalizeUrl('mailto:a@b.c', base), isNull);
    });
  });

  group('parseCourseLinks', () {
    test('unique by id, longest title wins', () {
      const html = '''
        <a href="/course/view.php?id=5"><img alt=""></a>
        <a href="https://moodle.ucas.edu.ps/course/view.php?id=5">Calculus 1</a>
        <a href="/course/view.php?id=7&amp;foo=1">Physics</a>
        <a href="/user/profile.php?id=5">Me</a>''';
      final l = parseCourseLinks(html, Uri.parse('https://moodle.ucas.edu.ps/my/courses.php'));
      expect(l.map((c) => c.id).toList(), ['5', '7']);
      expect(l[0].title, 'Calculus 1');
      expect(l[1].url, 'https://moodle.ucas.edu.ps/course/view.php?id=7');
    });
  });

  group('parseCoursePage', () {
    final page = parseCoursePage(courseHtml, base, '5');

    test('title and sections', () {
      expect(page.title, 'Calculus 1');
      expect(page.sections.map((s) => s.title).toList(), ['General', 'Week 1', 'Week 2']);
    });

    test('activity names have hidden text removed', () {
      expect(page.sections[0].items.single.title, 'Announcements');
      expect(page.sections[0].items.single.kind, ItemKind.forum);
    });

    test('week 1 items', () {
      final items = page.sections[1].items;
      final byTitle = {for (final i in items) i.title: i};
      expect(byTitle['Lecture 1']!.kind, ItemKind.file);
      expect(byTitle['Slides']!.kind, ItemKind.folder);
      expect(byTitle['Slides']!.url, 'https://moodle.ucas.edu.ps/mod/folder/view.php?id=22');
      expect(byTitle['Khan Academy']!.kind, ItemKind.link);
      expect(byTitle['Homework 1']!.kind, ItemKind.assignment);
      expect(byTitle['Intro video']!.kind, ItemKind.video);
      expect(items.where((i) => i.url == 'https://www.youtube.com/watch?v=xyz789').length, 1);
      // delete link inside the action menu is ignored; the assignment appears once
      expect(items.length, 6);
    });

    test('nav, availability restrictions and footer links are ignored', () {
      final week2 = page.sections[2].items;
      expect(week2.length, 1);
      expect(week2.single.title, 'Quiz 1');
      final all = page.sections.expand((s) => s.items).map((i) => i.url);
      expect(all.any((u) => u.contains('moodle.org')), isFalse);
      expect(all.any((u) => u.contains('id=77') || u.contains('id=99')), isFalse);
    });

    test('section pages of the same course are detected', () {
      const html = '''
        <div id="region-main"><h1>X</h1>
          <a href="/course/view.php?id=5&section=2">Two</a>
          <a href="/course/view.php?id=5&section=3">Three</a>
          <a href="/course/view.php?id=5#section-4">Four</a>
          <a href="/course/view.php?id=8&section=1">Other course</a>
        </div>''';
      final p = parseCoursePage(html, base, '5');
      expect(p.sectionPageUrls, [
        'https://moodle.ucas.edu.ps/course/view.php?id=5&section=2',
        'https://moodle.ucas.edu.ps/course/view.php?id=5&section=3',
      ]);
    });

    test('page without section markup still yields one section', () {
      const html = '<div id="region-main"><a href="/mod/page/view.php?id=3">Notes</a></div>';
      final p = parseCoursePage(html, base, '5');
      expect(p.sections.single.title, 'عام');
      expect(p.sections.single.items.single.kind, ItemKind.page);
    });
  });

  group('other pages', () {
    final fbase = Uri.parse('https://moodle.ucas.edu.ps/mod/folder/view.php?id=22');

    test('folder files', () {
      const html = '''
        <div id="region-main"><div class="foldertree"><ul>
          <li><a href="https://moodle.ucas.edu.ps/pluginfile.php/2/mod_folder/content/0/a.pdf?forcedownload=1"><span class="fp-filename">a.pdf</span></a></li>
          <li><a href="/pluginfile.php/2/mod_folder/content/0/b.pptx"><span class="fp-filename">b.pptx</span></a></li>
          <li><a href="/mod/folder/download_folder.php?id=22">Download folder</a></li>
        </ul></div></div>''';
      final l = parseFolderPage(html, fbase);
      expect(l.map((i) => i.title).toList(), ['a.pdf', 'b.pptx']);
      expect(l.map((i) => i.kind).toList(), [ItemKind.pdf, ItemKind.document]);
    });

    test('page links include embedded media but not the page itself', () {
      const html = '''
        <div id="region-main">
          <a href="/mod/page/view.php?id=25">self</a>
          <iframe src="https://www.youtube.com/embed/abc"></iframe>
          <video><source src="/pluginfile.php/1/mod_page/content/v.mp4"></video>
          <a href="https://example.com/read">Reading</a>
        </div>''';
      final l = parsePageLinks(html, Uri.parse('https://moodle.ucas.edu.ps/mod/page/view.php?id=25'));
      expect(l.map((i) => i.url).toSet(), {
        'https://www.youtube.com/watch?v=abc',
        'https://moodle.ucas.edu.ps/pluginfile.php/1/mod_page/content/v.mp4',
        'https://example.com/read',
      });
    });

    test('book chapters', () {
      const html = '''
        <div class="book_toc"><ul>
          <li><a href="/mod/book/view.php?id=7&amp;chapterid=1">Intro</a></li>
          <li><a href="/mod/book/view.php?id=7&amp;chapterid=2">Limits</a></li>
          <li><a href="/mod/book/view.php?id=7">Book</a></li>
        </ul></div>''';
      final l = parseBookChapters(html, Uri.parse('https://moodle.ucas.edu.ps/mod/book/view.php?id=7'));
      expect(l.map((i) => i.title).toList(), ['Intro', 'Limits']);
    });

    test('URL activity target and resource target', () {
      final u = Uri.parse('https://moodle.ucas.edu.ps/mod/url/view.php?id=23');
      expect(parseUrlTarget('<div class="urlworkaround"><a href="https://khanacademy.org/x">link</a></div>', u),
          'https://khanacademy.org/x');
      expect(parseUrlTarget('<div id="region-main"><a href="/my/">home</a></div>', u), isNull);
      final r = Uri.parse('https://moodle.ucas.edu.ps/mod/resource/view.php?id=21');
      expect(
          parseResourceTarget(
              '<div id="region-main"><object data="https://moodle.ucas.edu.ps/pluginfile.php/1/mod_resource/content/1/x.pdf"></object></div>', r),
          'https://moodle.ucas.edu.ps/pluginfile.php/1/mod_resource/content/1/x.pdf');
    });
  });

  group('model json', () {
    test('tree round-trips', () {
      final t = Tree(fetchedAt: DateTime.utc(2026, 11, 15), courses: [
        Course(id: '5', title: 'C', url: 'u', sections: [
          Section(title: 'S', items: [
            Item(title: 'F', url: 'f', kind: ItemKind.folder, children: [Item(title: 'a', url: 'a', kind: ItemKind.pdf)]),
          ]),
        ]),
      ], errors: [CrawlError('x', 'boom')]);
      final back = Tree.fromJson(t.toJson());
      expect(back.courses.single.allItems.length, 2);
      expect(back.errors.single.reason, 'boom');
      expect(back.countByKind()[ItemKind.pdf], 1);
      expect(back.toText(), contains('[PDF] a'));
    });
  });
}
