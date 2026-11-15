// The planning algorithm. Pure Dart: same input -> same plan, runs offline, costs nothing.
//
// 1) Items with a hard date (exam / assignment) are placed first, earliest day first.
// 2) The remaining items are spread over the regular days: each day's time is split between
//    courses in proportion to (course priority x minutes still to do), so all courses finish together.
// 3) Leftovers go to the last "buffer" days. Anything that still does not fit is reported as a shortfall.
// The plan is rebuilt from today every time, so a missed day is redistributed automatically.
import 'models.dart';

class Slot {
  final StudyItem item;
  int minutes;
  bool partial = false; // the item is split across several days
  Slot(this.item, this.minutes);
}

class DayPlan {
  final DateTime date;
  final int capacity; // minutes available that day
  final bool buffer; // reserved safety day
  final List<Slot> slots = [];
  DayPlan(this.date, this.capacity, this.buffer);
  int get used => slots.fold(0, (a, s) => a + s.minutes);
  int get free => capacity - used;
}

class PlanReport {
  int daysLeft = 0; // calendar days from today to the deadline
  int totalMin = 0; // minutes still to study
  int doneMin = 0; // minutes already finished
  int availableMin = 0; // all capacity from today to the deadline
  int shortfallMin = 0; // minutes that do not fit before the deadline
  int bufferUsedMin = 0;
  double neededHoursPerDay = 0;
  double extraHoursPerDay = 0; // how much more per day would make it fit
  final List<String> warnings = [];
  bool get feasible => shortfallMin == 0 && warnings.where((w) => w.startsWith('!')).isEmpty;
  double get progress => (doneMin + totalMin) == 0 ? 0 : doneMin / (doneMin + totalMin);
}

class Plan {
  final List<DayPlan> days;
  final PlanReport report;
  Plan(this.days, this.report);
  DayPlan? get today => days.isEmpty ? null : days.first;
}

Plan buildPlan({
  required List<Course> courses,
  required List<StudyItem> items,
  required PlannerSettings settings,
  DateTime? now,
}) {
  final today = dOnly(now ?? DateTime.now());
  final last = dOnly(settings.deadline);
  final report = PlanReport();

  // ---- days from today to the deadline (inclusive) ----
  final dates = <DateTime>[];
  for (var d = today; !d.isAfter(last); d = DateTime(d.year, d.month, d.day + 1)) {
    dates.add(d);
  }
  report.daysLeft = dates.isEmpty ? 0 : dates.length - 1;

  // minutes already finished today are taken out of today's capacity
  int doneTodayMin = 0;
  int doneMin = 0;
  for (final it in items) {
    if (!it.done) continue;
    final m = estimateMinutes(it, settings);
    doneMin += m;
    if (it.doneAt != null && dOnly(it.doneAt!) == today) doneTodayMin += m;
  }
  report.doneMin = doneMin;

  final n = dates.length;
  final bufferCount = n > 1 ? (settings.bufferDays < n - 1 ? settings.bufferDays : n - 1) : 0;
  final days = <DayPlan>[];
  for (var i = 0; i < n; i++) {
    var cap = ((settings.hoursByWeekday[dates[i].weekday - 1] * 60) / 5).floor() * 5;
    if (i == 0) cap = (cap - doneTodayMin) < 0 ? 0 : cap - doneTodayMin;
    days.add(DayPlan(dates[i], cap, i >= n - bufferCount));
  }
  report.availableMin = days.fold(0, (a, d) => a + d.capacity);

  if (n == 0) {
    report.warnings.add('!انتهى الموعد النهائي (${settings.deadline.day}/${settings.deadline.month}). غيّره من الإعدادات.');
  }

  // ---- what is left to do ----
  final prio = <String, int>{for (final c in courses) c.id: c.priority};
  final corder = <String, int>{for (var i = 0; i < courses.length; i++) courses[i].id: i};
  final todo = items.where((i) => !i.done && corder.containsKey(i.courseId)).toList();
  final rem = <String, int>{for (final i in todo) i.id: estimateMinutes(i, settings)};
  report.totalMin = rem.values.fold(0, (a, b) => a + b);

  int itemCmp(StudyItem a, StudyItem b) {
    final pa = prio[a.courseId] ?? 2, pb = prio[b.courseId] ?? 2;
    if (pa != pb) return pb.compareTo(pa); // higher priority first
    final ca = corder[a.courseId] ?? 0, cb = corder[b.courseId] ?? 0;
    if (ca != cb) return ca.compareTo(cb);
    return a.order.compareTo(b.order);
  }

  // puts up to `want` minutes of an item into a day; returns the minutes placed
  int place(DayPlan day, StudyItem it, int want) {
    final left = rem[it.id] ?? 0;
    if (left <= 0) return 0;
    var fit = day.free < want ? day.free : want;
    if (fit > left) fit = left;
    if (fit <= 0) return 0;
    if (fit < 10 && fit < left) return 0; // no tiny fragments
    final existing = day.slots.where((s) => s.item.id == it.id);
    if (existing.isNotEmpty) {
      existing.first.minutes += fit;
    } else {
      day.slots.add(Slot(it, fit));
    }
    rem[it.id] = left - fit;
    return fit;
  }

  // ---- pass 1: items with a hard date ----
  final dated = todo.where((i) => i.due != null).toList()
    ..sort((a, b) {
      final c = dOnly(a.due!).compareTo(dOnly(b.due!));
      return c != 0 ? c : itemCmp(a, b);
    });
  for (final it in dated) {
    final dueDay = dOnly(it.due!);
    for (final day in days) {
      if (day.date.isAfter(dueDay) && !dueDay.isBefore(today)) break;
      if ((rem[it.id] ?? 0) <= 0) break;
      place(day, it, rem[it.id]!);
    }
  }

  // ---- pass 2: undated items, weighted by course ----
  final regular = days.where((d) => !d.buffer).toList();
  final undated = todo.where((i) => i.due == null).toList()..sort(itemCmp);
  for (final day in regular) {
    if (day.free < 5) continue;
    final byCourse = <String, List<StudyItem>>{};
    for (final it in undated) {
      if ((rem[it.id] ?? 0) > 0) byCourse.putIfAbsent(it.courseId, () => []).add(it);
    }
    if (byCourse.isEmpty) break;
    final weight = <String, double>{};
    byCourse.forEach((cid, list) {
      final minutes = list.fold<int>(0, (a, i) => a + rem[i.id]!);
      weight[cid] = (prio[cid] ?? 2) * minutes.toDouble();
    });
    final totalW = weight.values.fold<double>(0, (a, b) => a + b);
    final ids = byCourse.keys.toList()..sort((a, b) => weight[b]!.compareTo(weight[a]!));
    final startFree = day.free;
    for (final cid in ids) {
      var quota = (startFree * weight[cid]! / totalW).floor();
      quota -= quota % 5;
      for (final it in byCourse[cid]!) {
        if (quota <= 0) break;
        final want = quota < rem[it.id]! ? quota : rem[it.id]!;
        quota -= place(day, it, want);
      }
    }
    // whatever is still free that day goes to the most important items
    for (final it in undated) {
      if (day.free < 5) break;
      if ((rem[it.id] ?? 0) > 0) place(day, it, rem[it.id]!);
    }
  }

  // ---- pass 3: leftovers into any free time (regular days first, then buffer days) ----
  final rest = todo.where((i) => (rem[i.id] ?? 0) > 0).toList()
    ..sort((a, b) {
      final da = a.due == null ? 1 : 0, db = b.due == null ? 1 : 0;
      return da != db ? da.compareTo(db) : itemCmp(a, b);
    });
  for (final it in rest) {
    for (final day in days) {
      if ((rem[it.id] ?? 0) <= 0) break;
      place(day, it, rem[it.id]!);
    }
  }

  // ---- bookkeeping ----
  report.shortfallMin = rem.values.fold(0, (a, b) => a + b);
  report.bufferUsedMin = days.where((d) => d.buffer).fold(0, (a, d) => a + d.used);
  final withCap = days.where((d) => d.capacity > 0).length;
  if (withCap > 0) {
    report.neededHoursPerDay = report.totalMin / withCap / 60;
    report.extraHoursPerDay = report.shortfallMin / withCap / 60;
  }

  // mark items that are split over several days
  final counts = <String, int>{};
  for (final d in days) {
    for (final s in d.slots) {
      counts[s.item.id] = (counts[s.item.id] ?? 0) + 1;
    }
  }
  for (final d in days) {
    for (final s in d.slots) {
      s.partial = (counts[s.item.id] ?? 0) > 1 || (rem[s.item.id] ?? 0) > 0;
    }
    d.slots.sort((a, b) {
      final da = a.item.due == null ? 1 : 0, db = b.item.due == null ? 1 : 0;
      return da != db ? da.compareTo(db) : itemCmp(a.item, b.item);
    });
  }

  // hard-date items that end up after their date
  for (final it in dated) {
    final dueDay = dOnly(it.due!);
    DateTime? lastDay;
    for (final d in days) {
      if (d.slots.any((s) => s.item.id == it.id)) lastDay = d.date;
    }
    final unfinished = (rem[it.id] ?? 0) > 0;
    if (dueDay.isBefore(today)) {
      report.warnings.add('!«${it.title}» موعده فات.');
    } else if (unfinished || (lastDay != null && lastDay.isAfter(dueDay))) {
      report.warnings.add('!«${it.title}» لا يكفي الوقت قبل موعده (${it.due!.day}/${it.due!.month}).');
    }
  }
  if (todo.isEmpty && items.where((i) => !i.done).isEmpty && items.isEmpty) {
    report.warnings.add('أضف موادك لتبني الخطة.');
  }
  return Plan(days, report);
}
