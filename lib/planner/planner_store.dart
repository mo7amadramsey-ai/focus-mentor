// Local storage for the planner: one JSON file in the app's private folder (same approach as the rest of the app).
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'models.dart';

class PlannerStore extends ChangeNotifier {
  List<Course> courses = [];
  List<StudyItem> items = [];
  PlannerSettings settings = PlannerSettings.defaults();
  bool loaded = false;
  int _seq = 0;

  String _newId() => '${DateTime.now().microsecondsSinceEpoch}_${_seq++}';

  Future<File> _file() async => File('${(await getApplicationSupportDirectory()).path}/planner.json');

  Future<void> load() async {
    try {
      final f = await _file();
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        courses = (j['courses'] as List? ?? []).map((e) => Course.fromJson(e as Map<String, dynamic>)).toList();
        items = (j['items'] as List? ?? []).map((e) => StudyItem.fromJson(e as Map<String, dynamic>)).toList();
        if (j['settings'] != null) settings = PlannerSettings.fromJson(j['settings'] as Map<String, dynamic>);
      }
    } catch (_) {
      // corrupted file: start empty instead of crashing
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    notifyListeners();
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode({
        'courses': courses.map((c) => c.toJson()).toList(),
        'items': items.map((i) => i.toJson()).toList(),
        'settings': settings.toJson(),
      }));
    } catch (_) {}
  }

  Course? courseById(String id) {
    for (final c in courses) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<Course> addCourse(String name, int priority) async {
    final c = Course(id: _newId(), name: name.trim(), priority: priority);
    courses.add(c);
    await _save();
    return c;
  }

  Future<void> updateCourse(Course c, String name, int priority) async {
    c.name = name.trim();
    c.priority = priority;
    await _save();
  }

  Future<void> deleteCourse(Course c) async {
    courses.removeWhere((x) => x.id == c.id);
    items.removeWhere((i) => i.courseId == c.id);
    await _save();
  }

  // adds `count` items; when count > 1 the titles are numbered (محاضرة 1, محاضرة 2 ...)
  Future<void> addItems({
    required String courseId,
    required String title,
    required ItemType type,
    required double amount,
    required int count,
    DateTime? due,
  }) async {
    var order = items.where((i) => i.courseId == courseId).fold<int>(0, (a, i) => i.order >= a ? i.order + 1 : a);
    for (var k = 1; k <= count; k++) {
      items.add(StudyItem(
        id: _newId(),
        courseId: courseId,
        title: count > 1 ? '$title $k' : title,
        type: type,
        amount: amount,
        due: due,
        order: order++,
      ));
    }
    await _save();
  }

  Future<void> saveItem(StudyItem it) => _save(); // after the caller edited its fields

  Future<void> deleteItem(StudyItem it) async {
    items.removeWhere((x) => x.id == it.id);
    await _save();
  }

  Future<void> setDone(StudyItem it, bool done) async {
    it.done = done;
    it.doneAt = done ? DateTime.now() : null;
    await _save();
  }

  Future<void> setSettings(PlannerSettings s) async {
    settings = s;
    await _save();
  }
}

final plannerStore = PlannerStore();
