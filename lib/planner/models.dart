// Study planner data models (plain Dart, no AI, no network).
// Time estimates are rules: video = length x factor, PDF = pages x minutes/page, others = minutes typed by the user.

DateTime dOnly(DateTime d) => DateTime(d.year, d.month, d.day);

enum ItemType { video, pdf, reading, assignment, exam }

extension ItemTypeX on ItemType {
  String get label {
    switch (this) {
      case ItemType.video:
        return 'فيديو / محاضرة';
      case ItemType.pdf:
        return 'ملف PDF';
      case ItemType.reading:
        return 'قراءة / مراجعة';
      case ItemType.assignment:
        return 'تكليف';
      case ItemType.exam:
        return 'اختبار';
    }
  }

  // What the number typed by the user means for this type
  String get amountLabel {
    switch (this) {
      case ItemType.video:
        return 'مدة الفيديو الواحد (بالدقائق)';
      case ItemType.pdf:
        return 'عدد صفحات الملف الواحد';
      default:
        return 'الوقت المقدّر (بالدقائق)';
    }
  }
}

class Course {
  final String id;
  String name;
  int priority; // 1 low, 2 normal, 3 high
  Course({required this.id, required this.name, this.priority = 2});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'priority': priority};
  factory Course.fromJson(Map<String, dynamic> j) =>
      Course(id: j['id'] as String, name: j['name'] as String, priority: (j['priority'] as num?)?.toInt() ?? 2);
}

class StudyItem {
  final String id;
  String courseId;
  String title;
  ItemType type;
  double amount; // minutes (video / others) or pages (pdf)
  DateTime? due; // optional hard date (assignment / exam)
  bool done;
  DateTime? doneAt;
  int order; // keeps the order the user entered inside a course

  StudyItem({
    required this.id,
    required this.courseId,
    required this.title,
    required this.type,
    required this.amount,
    this.due,
    this.done = false,
    this.doneAt,
    this.order = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'courseId': courseId,
        'title': title,
        'type': type.name,
        'amount': amount,
        'due': due?.toIso8601String(),
        'done': done,
        'doneAt': doneAt?.toIso8601String(),
        'order': order,
      };

  factory StudyItem.fromJson(Map<String, dynamic> j) => StudyItem(
        id: j['id'] as String,
        courseId: j['courseId'] as String,
        title: j['title'] as String,
        type: ItemType.values.firstWhere((t) => t.name == j['type'], orElse: () => ItemType.reading),
        amount: (j['amount'] as num).toDouble(),
        due: j['due'] == null ? null : DateTime.parse(j['due'] as String),
        done: j['done'] == true,
        doneAt: j['doneAt'] == null ? null : DateTime.parse(j['doneAt'] as String),
        order: (j['order'] as num?)?.toInt() ?? 0,
      );
}

class PlannerSettings {
  DateTime deadline; // everything must be finished by this day (inclusive)
  List<double> hoursByWeekday; // index 0 = Monday ... 6 = Sunday (DateTime.weekday - 1)
  int bufferDays; // last days kept only for leftovers / review
  double videoFactor; // video minutes x factor (pauses, notes)
  double minPerPage; // minutes per PDF page

  PlannerSettings({
    required this.deadline,
    required this.hoursByWeekday,
    this.bufferDays = 2,
    this.videoFactor = 1.25,
    this.minPerPage = 3,
  });

  factory PlannerSettings.defaults() => PlannerSettings(
        deadline: DateTime(2026, 12, 2),
        hoursByWeekday: List<double>.filled(7, 4),
      );

  Map<String, dynamic> toJson() => {
        'deadline': deadline.toIso8601String(),
        'hours': hoursByWeekday,
        'buffer': bufferDays,
        'videoFactor': videoFactor,
        'minPerPage': minPerPage,
      };

  factory PlannerSettings.fromJson(Map<String, dynamic> j) {
    final d = PlannerSettings.defaults();
    final h = (j['hours'] as List?)?.map((e) => (e as num).toDouble()).toList();
    return PlannerSettings(
      deadline: j['deadline'] == null ? d.deadline : DateTime.parse(j['deadline'] as String),
      hoursByWeekday: (h != null && h.length == 7) ? h : d.hoursByWeekday,
      bufferDays: (j['buffer'] as num?)?.toInt() ?? d.bufferDays,
      videoFactor: (j['videoFactor'] as num?)?.toDouble() ?? d.videoFactor,
      minPerPage: (j['minPerPage'] as num?)?.toDouble() ?? d.minPerPage,
    );
  }
}

// Estimated study minutes for one item (rounded up to 5)
int estimateMinutes(StudyItem it, PlannerSettings s) {
  double m;
  switch (it.type) {
    case ItemType.video:
      m = it.amount * s.videoFactor;
      break;
    case ItemType.pdf:
      m = it.amount * s.minPerPage;
      break;
    default:
      m = it.amount;
  }
  final r = (m / 5).ceil() * 5;
  return r < 5 ? 5 : r;
}

String fmtMin(int m) {
  if (m <= 0) return '0د';
  final h = m ~/ 60, r = m % 60;
  if (h == 0) return '$rد';
  return r == 0 ? '$hس' : '$hس $rد';
}
