// Data model of the crawled Moodle tree: Tree > Course > Section > Item (> children)

enum ItemKind { video, pdf, document, file, link, assignment, quiz, folder, page, book, forum, other }

const kindLabels = <ItemKind, String>{
  ItemKind.video: 'فيديو',
  ItemKind.pdf: 'PDF',
  ItemKind.document: 'مستند',
  ItemKind.file: 'ملف',
  ItemKind.link: 'رابط',
  ItemKind.assignment: 'تكليف',
  ItemKind.quiz: 'اختبار',
  ItemKind.folder: 'مجلد',
  ItemKind.page: 'صفحة',
  ItemKind.book: 'كتاب',
  ItemKind.forum: 'منتدى',
  ItemKind.other: 'أخرى',
};

class Item {
  String title;
  String url;
  ItemKind kind;
  final List<Item> children;
  Item({required this.title, required this.url, required this.kind, List<Item>? children})
      : children = children ?? [];

  Map<String, dynamic> toJson() => {
        'title': title,
        'url': url,
        'kind': kind.name,
        if (children.isNotEmpty) 'children': children.map((c) => c.toJson()).toList(),
      };

  factory Item.fromJson(Map<String, dynamic> j) => Item(
        title: j['title'] as String,
        url: j['url'] as String,
        kind: ItemKind.values.firstWhere((k) => k.name == j['kind'], orElse: () => ItemKind.other),
        children: ((j['children'] as List?) ?? []).map((c) => Item.fromJson(c as Map<String, dynamic>)).toList(),
      );

  /// This item and all descendants
  Iterable<Item> flatten() sync* {
    yield this;
    for (final c in children) {
      yield* c.flatten();
    }
  }
}

class Section {
  String title;
  final List<Item> items;
  Section({required this.title, List<Item>? items}) : items = items ?? [];

  Map<String, dynamic> toJson() => {'title': title, 'items': items.map((i) => i.toJson()).toList()};

  factory Section.fromJson(Map<String, dynamic> j) => Section(
        title: j['title'] as String,
        items: ((j['items'] as List?) ?? []).map((i) => Item.fromJson(i as Map<String, dynamic>)).toList(),
      );
}

class Course {
  final String id;
  String title;
  final String url;
  final List<Section> sections;
  Course({required this.id, required this.title, required this.url, List<Section>? sections})
      : sections = sections ?? [];

  Iterable<Item> get allItems sync* {
    for (final s in sections) {
      for (final i in s.items) {
        yield* i.flatten();
      }
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'url': url,
        'sections': sections.map((s) => s.toJson()).toList(),
      };

  factory Course.fromJson(Map<String, dynamic> j) => Course(
        id: j['id'] as String,
        title: j['title'] as String,
        url: j['url'] as String,
        sections: ((j['sections'] as List?) ?? []).map((s) => Section.fromJson(s as Map<String, dynamic>)).toList(),
      );
}

class CrawlError {
  final String url;
  final String reason;
  CrawlError(this.url, this.reason);
  Map<String, dynamic> toJson() => {'url': url, 'reason': reason};
  factory CrawlError.fromJson(Map<String, dynamic> j) => CrawlError(j['url'] as String, j['reason'] as String);
}

class Tree {
  final DateTime fetchedAt;
  final List<Course> courses;
  final List<CrawlError> errors;
  Tree({required this.fetchedAt, required this.courses, List<CrawlError>? errors}) : errors = errors ?? [];

  Map<String, dynamic> toJson() => {
        'fetchedAt': fetchedAt.toIso8601String(),
        'courses': courses.map((c) => c.toJson()).toList(),
        'errors': errors.map((e) => e.toJson()).toList(),
      };

  factory Tree.fromJson(Map<String, dynamic> j) => Tree(
        fetchedAt: DateTime.parse(j['fetchedAt'] as String),
        courses: ((j['courses'] as List?) ?? []).map((c) => Course.fromJson(c as Map<String, dynamic>)).toList(),
        errors: ((j['errors'] as List?) ?? []).map((e) => CrawlError.fromJson(e as Map<String, dynamic>)).toList(),
      );

  /// Count of items per kind across the whole tree
  Map<ItemKind, int> countByKind() {
    final m = <ItemKind, int>{};
    for (final c in courses) {
      for (final i in c.allItems) {
        m[i.kind] = (m[i.kind] ?? 0) + 1;
      }
    }
    return m;
  }

  /// Plain-text rendering (for copying / debugging on the phone)
  String toText() {
    final b = StringBuffer();
    for (final c in courses) {
      b.writeln('■ ${c.title}  [${c.id}]');
      for (final s in c.sections) {
        b.writeln('  ▸ ${s.title}');
        for (final i in s.items) {
          _writeItem(b, i, 2);
        }
      }
    }
    if (errors.isNotEmpty) {
      b.writeln('\n! أخطاء (${errors.length}):');
      for (final e in errors) {
        b.writeln('  ${e.reason}  ${e.url}');
      }
    }
    return b.toString();
  }

  void _writeItem(StringBuffer b, Item i, int depth) {
    b.writeln('${'  ' * (depth + 1)}• [${kindLabels[i.kind]}] ${i.title}');
    for (final c in i.children) {
      _writeItem(b, c, depth + 1);
    }
  }
}
