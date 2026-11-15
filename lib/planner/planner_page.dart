// Study planner screens: Today / Plan / Courses, plus sheets for adding items and settings.
import 'package:flutter/material.dart';
import '../docs.dart' show DocsPage;
import '../library_page.dart' show LibraryPage;
import '../moodle_page.dart' show MoodlePage;
import '../theme.dart' show kAccent, kSurface2, kOutline, cardBox;
import 'models.dart';
import 'planner_store.dart';
import 'scheduler.dart';

const _dayNames = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
String _dayLabel(DateTime d) => '${_dayNames[d.weekday - 1]} ${d.day}/${d.month}';

class PlannerPage extends StatefulWidget {
  const PlannerPage({super.key});
  @override
  State<PlannerPage> createState() => _PlannerPageState();
}

class _PlannerPageState extends State<PlannerPage> {
  int tab = 0;

  @override
  void initState() {
    super.initState();
    if (!plannerStore.loaded) plannerStore.load();
  }

  Future<void> _addItem() async {
    if (plannerStore.courses.isEmpty) {
      await _courseDialog(context);
      if (plannerStore.courses.isEmpty) return;
    }
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const ItemSheet(),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: plannerStore,
        builder: (context, _) {
          final plan = buildPlan(courses: plannerStore.courses, items: plannerStore.items, settings: plannerStore.settings);
          final pages = [_TodayTab(plan: plan), _PlanTab(plan: plan), _CoursesTab(plan: plan)];
          return Scaffold(
            appBar: AppBar(
              title: const Text('المرشد الدراسي'),
              actions: [
                IconButton(
                  tooltip: 'الإعدادات',
                  icon: const Icon(Icons.tune),
                  onPressed: () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => const SettingsSheet(),
                  ),
                ),
              ],
            ),
            body: plannerStore.loaded ? pages[tab] : const Center(child: CircularProgressIndicator(color: kAccent)),
            floatingActionButton: FloatingActionButton.extended(
              onPressed: _addItem,
              icon: const Icon(Icons.add),
              label: const Text('إضافة مادة'),
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: tab,
              onDestinationSelected: (i) => setState(() => tab = i),
              destinations: const [
                NavigationDestination(icon: Icon(Icons.today), label: 'اليوم'),
                NavigationDestination(icon: Icon(Icons.calendar_month), label: 'الخطة'),
                NavigationDestination(icon: Icon(Icons.menu_book), label: 'المواد'),
              ],
            ),
          );
        },
      );
}

// ───────────────────────── Today ─────────────────────────
class _TodayTab extends StatelessWidget {
  final Plan plan;
  const _TodayTab({required this.plan});

  // Opens the right screen for the item; afterwards asks whether it was finished
  Future<void> _open(BuildContext c, StudyItem it) async {
    Widget page;
    switch (it.type) {
      case ItemType.video:
        page = const LibraryPage();
        break;
      case ItemType.pdf:
      case ItemType.reading:
        page = const DocsPage();
        break;
      default:
        page = const MoodlePage();
    }
    await Navigator.push(c, MaterialPageRoute(builder: (_) => page));
    if (!c.mounted) return;
    final ok = await showDialog<bool>(
      context: c,
      builder: (ctx) => AlertDialog(
        title: const Text('أنهيت المهمة؟'),
        content: Text(it.title),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('لا، لاحقاً')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('نعم، تمت')),
        ],
      ),
    );
    if (ok == true) await plannerStore.setDone(it, true);
  }

  Future<void> _check(BuildContext c, Slot s) async {
    if (s.partial) {
      final ok = await showDialog<bool>(
        context: c,
        builder: (ctx) => AlertDialog(
          title: const Text('هذه المهمة موزعة على أيام'),
          content: Text('هل أنهيت «${s.item.title}» بالكامل؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('لا')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('نعم، كاملة')),
          ],
        ),
      );
      if (ok != true) return;
    }
    await plannerStore.setDone(s.item, true);
  }

  @override
  Widget build(BuildContext context) {
    final r = plan.report;
    final today = plan.today;
    final now = dOnly(DateTime.now());
    final doneToday = plannerStore.items.where((i) => i.done && i.doneAt != null && dOnly(i.doneAt!) == now).toList();
    final ok = r.feasible && plannerStore.items.isNotEmpty;
    final col = plannerStore.items.isEmpty ? Colors.white60 : (ok ? Colors.greenAccent : Colors.orangeAccent);

    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
      // feasibility card
      Container(
        padding: const EdgeInsets.all(16),
        decoration: cardBox(22),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(ok ? Icons.check_circle : Icons.info, color: col),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                plannerStore.items.isEmpty
                    ? 'أضف موادك لتبني الخطة'
                    : (ok ? 'الخطة ممكنة قبل ${plannerStore.settings.deadline.day}/${plannerStore.settings.deadline.month}' : 'الوقت لا يكفي'),
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: col),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Text('باقي ${r.daysLeft} يوماً على الموعد النهائي', style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 4),
          Text('المتبقي: ${fmtMin(r.totalMin)}   |   المتاح: ${fmtMin(r.availableMin)}', style: const TextStyle(color: Colors.white70)),
          if (r.shortfallMin > 0) ...[
            const SizedBox(height: 6),
            Text(
              'ناقص ${fmtMin(r.shortfallMin)}. زِد ساعاتك بمقدار ${r.extraHoursPerDay.toStringAsFixed(1)} س يومياً من الإعدادات، أو قلّل المواد.',
              style: const TextStyle(color: Colors.orangeAccent, height: 1.5),
            ),
          ] else if (plannerStore.items.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('تحتاج تقريباً ${r.neededHoursPerDay.toStringAsFixed(1)} س يومياً', style: const TextStyle(color: Colors.white70)),
          ],
          for (final w in r.warnings)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(w.startsWith('!') ? w.substring(1) : w, style: const TextStyle(color: Colors.orangeAccent)),
            ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(value: r.progress, minHeight: 8, color: kAccent, backgroundColor: kSurface2),
          ),
          const SizedBox(height: 4),
          Text('الإنجاز ${(r.progress * 100).round()}%', style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ]),
      ),
      const SizedBox(height: 18),
      Text('خطة اليوم ${today == null ? '' : '(${fmtMin(today.used)})'}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      if (today == null || today.slots.isEmpty)
        Container(
          padding: const EdgeInsets.all(18),
          decoration: cardBox(18),
          child: Text(
            plannerStore.items.isEmpty ? 'لا توجد مهام بعد.' : 'لا مهام متبقية لهذا اليوم 🎉',
            style: const TextStyle(color: Colors.white60),
          ),
        )
      else
        for (final s in today.slots)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: cardBox(18),
            child: ListTile(
              leading: Checkbox(value: false, onChanged: (_) => _check(context, s)),
              title: Text(s.item.title, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                '${plannerStore.courseById(s.item.courseId)?.name ?? ''} • ${s.item.type.label} • ${fmtMin(s.minutes)}'
                '${s.partial ? ' (جزء)' : ''}'
                '${s.item.due != null ? ' • موعده ${s.item.due!.day}/${s.item.due!.month}' : ''}',
                style: const TextStyle(color: Colors.white60, height: 1.4),
              ),
              trailing: IconButton(
                tooltip: 'افتح المادة',
                icon: const Icon(Icons.play_circle_fill, color: kAccent, size: 32),
                onPressed: () => _open(context, s.item),
              ),
            ),
          ),
      if (doneToday.isNotEmpty) ...[
        const SizedBox(height: 16),
        const Text('أنجزتها اليوم ✅', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        for (final it in doneToday)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: cardBox(16),
            child: ListTile(
              dense: true,
              leading: Checkbox(value: true, onChanged: (_) => plannerStore.setDone(it, false)),
              title: Text(it.title, style: const TextStyle(decoration: TextDecoration.lineThrough, color: Colors.white54)),
            ),
          ),
      ],
    ]);
  }
}

// ───────────────────────── Plan (all days) ─────────────────────────
class _PlanTab extends StatelessWidget {
  final Plan plan;
  const _PlanTab({required this.plan});

  @override
  Widget build(BuildContext context) {
    if (plan.days.isEmpty) {
      return const Center(child: Text('الموعد النهائي انتهى. غيّره من الإعدادات.', style: TextStyle(color: Colors.white60)));
    }
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
      for (var i = 0; i < plan.days.length; i++) _dayCard(plan.days[i], i == 0),
    ]);
  }

  Widget _dayCard(DayPlan d, bool isToday) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: cardBox(18).copyWith(border: Border.all(color: isToday ? kAccent : kOutline)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('${_dayLabel(d.date)}${isToday ? '  (اليوم)' : ''}', style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            if (d.buffer)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Text('هامش أمان', style: TextStyle(color: Colors.amberAccent, fontSize: 12)),
              ),
            Text('${fmtMin(d.used)} / ${fmtMin(d.capacity)}', style: const TextStyle(color: Colors.white60, fontSize: 12.5)),
          ]),
          if (d.slots.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('—', style: TextStyle(color: Colors.white38)),
            ),
          for (final s in d.slots)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '• ${s.item.title} (${plannerStore.courseById(s.item.courseId)?.name ?? ''}) — ${fmtMin(s.minutes)}${s.partial ? ' جزء' : ''}',
                style: const TextStyle(color: Colors.white70, height: 1.4),
              ),
            ),
        ]),
      );
}

// ───────────────────────── Courses ─────────────────────────
Future<void> _courseDialog(BuildContext context, {Course? edit}) async {
  final name = TextEditingController(text: edit?.name ?? '');
  var prio = edit?.priority ?? 2;
  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text(edit == null ? 'مادة جديدة' : 'تعديل المادة'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم المادة')),
          const SizedBox(height: 14),
          const Text('الأولوية'),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            for (final p in [1, 2, 3])
              ChoiceChip(
                label: Text(p == 1 ? 'منخفضة' : (p == 2 ? 'عادية' : 'عالية')),
                selected: prio == p,
                onSelected: (_) => setS(() => prio = p),
              ),
          ]),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty) return;
              if (edit == null) {
                await plannerStore.addCourse(name.text, prio);
              } else {
                await plannerStore.updateCourse(edit, name.text, prio);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    ),
  );
}

class _CoursesTab extends StatelessWidget {
  final Plan plan;
  const _CoursesTab({required this.plan});

  @override
  Widget build(BuildContext context) {
    final s = plannerStore.settings;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
      OutlinedButton.icon(
        onPressed: () => _courseDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('مادة جديدة'),
      ),
      const SizedBox(height: 12),
      if (plannerStore.courses.isEmpty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text('أضف موادك الدراسية أولاً، ثم محاضراتها وملفاتها.', style: TextStyle(color: Colors.white60)),
        ),
      for (final c in plannerStore.courses) _courseCard(context, c, s),
    ]);
  }

  Widget _courseCard(BuildContext context, Course c, PlannerSettings s) {
    final its = plannerStore.items.where((i) => i.courseId == c.id).toList()..sort((a, b) => a.order.compareTo(b.order));
    final total = its.fold<int>(0, (a, i) => a + estimateMinutes(i, s));
    final done = its.where((i) => i.done).fold<int>(0, (a, i) => a + estimateMinutes(i, s));
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: cardBox(20),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(value: total == 0 ? 0 : done / total, minHeight: 6, color: kAccent, backgroundColor: kSurface2),
              ),
              const SizedBox(height: 4),
              Text('${its.where((i) => i.done).length}/${its.length} عنصر • ${fmtMin(total - done)} متبقي', style: const TextStyle(fontSize: 12, color: Colors.white54)),
            ]),
          ),
          children: [
            for (final it in its)
              ListTile(
                dense: true,
                leading: Checkbox(value: it.done, onChanged: (v) => plannerStore.setDone(it, v ?? false)),
                title: Text(it.title, style: TextStyle(decoration: it.done ? TextDecoration.lineThrough : null)),
                subtitle: Text(
                  '${it.type.label} • ${fmtMin(estimateMinutes(it, s))}${it.due != null ? ' • موعده ${it.due!.day}/${it.due!.month}' : ''}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'edit') {
                      showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => ItemSheet(edit: it));
                    } else {
                      plannerStore.deleteItem(it);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('تعديل')),
                    PopupMenuItem(value: 'del', child: Text('حذف')),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(children: [
                TextButton.icon(
                  onPressed: () => showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => ItemSheet(courseId: c.id)),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('عنصر'),
                ),
                TextButton(onPressed: () => _courseDialog(context, edit: c), child: const Text('تعديل المادة')),
                TextButton(
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text('حذف «${c.name}»؟'),
                        content: const Text('سيُحذف معها كل عناصرها.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
                        ],
                      ),
                    );
                    if (ok == true) await plannerStore.deleteCourse(c);
                  },
                  child: const Text('حذف', style: TextStyle(color: Colors.redAccent)),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── Add / edit item ─────────────────────────
class ItemSheet extends StatefulWidget {
  final StudyItem? edit;
  final String? courseId;
  const ItemSheet({super.key, this.edit, this.courseId});
  @override
  State<ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<ItemSheet> {
  late String courseId = widget.edit?.courseId ?? widget.courseId ?? plannerStore.courses.first.id;
  late final title = TextEditingController(text: widget.edit?.title ?? '');
  late ItemType type = widget.edit?.type ?? ItemType.video;
  late final amount = TextEditingController(text: widget.edit == null ? '' : widget.edit!.amount.toStringAsFixed(widget.edit!.amount % 1 == 0 ? 0 : 1));
  final count = TextEditingController(text: '1');
  late DateTime? due = widget.edit?.due;

  double? get _amount => double.tryParse(amount.text.trim().replaceAll(',', '.'));

  int get _preview {
    final a = _amount;
    if (a == null || a <= 0) return 0;
    final n = widget.edit == null ? (int.tryParse(count.text.trim()) ?? 1) : 1;
    final one = estimateMinutes(StudyItem(id: 'x', courseId: courseId, title: '', type: type, amount: a), plannerStore.settings);
    return one * (n < 1 ? 1 : n);
  }

  Future<void> _save() async {
    final a = _amount;
    if (title.text.trim().isEmpty || a == null || a <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اكتب الاسم والمقدار')));
      return;
    }
    if (widget.edit != null) {
      final it = widget.edit!;
      it.courseId = courseId;
      it.title = title.text.trim();
      it.type = type;
      it.amount = a;
      it.due = due;
      await plannerStore.saveItem(it);
    } else {
      final n = (int.tryParse(count.text.trim()) ?? 1).clamp(1, 60).toInt();
      await plannerStore.addItems(courseId: courseId, title: title.text.trim(), type: type, amount: a, count: n, due: due);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.edit == null ? 'إضافة عناصر' : 'تعديل العنصر', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: courseId,
              decoration: const InputDecoration(labelText: 'المادة'),
              items: [for (final c in plannerStore.courses) DropdownMenuItem(value: c.id, child: Text(c.name))],
              onChanged: (v) => setState(() => courseId = v ?? courseId),
            ),
            const SizedBox(height: 12),
            TextField(controller: title, decoration: const InputDecoration(labelText: 'الاسم (مثال: محاضرة)')),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              for (final t in ItemType.values)
                ChoiceChip(label: Text(t.label), selected: type == t, onSelected: (_) => setState(() => type = t)),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: type.amountLabel),
              onChanged: (_) => setState(() {}),
            ),
            if (widget.edit == null) ...[
              const SizedBox(height: 12),
              TextField(
                controller: count,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'العدد (يُرقَّم تلقائياً: محاضرة 1، 2، 3...)'),
                onChanged: (_) => setState(() {}),
              ),
            ],
            const SizedBox(height: 12),
            Row(children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final now = DateTime.now();
                  final d = await showDatePicker(
                    context: context,
                    initialDate: due ?? now,
                    firstDate: DateTime(now.year - 1),
                    lastDate: DateTime(now.year + 2),
                  );
                  if (d != null) setState(() => due = d);
                },
                icon: const Icon(Icons.event, size: 18),
                label: Text(due == null ? 'موعد ثابت (اختياري)' : '${due!.day}/${due!.month}/${due!.year}'),
              ),
              if (due != null) IconButton(onPressed: () => setState(() => due = null), icon: const Icon(Icons.close)),
            ]),
            const SizedBox(height: 10),
            if (_preview > 0) Text('الوقت المقدّر: ${fmtMin(_preview)}', style: const TextStyle(color: Colors.white60)),
            const SizedBox(height: 14),
            SizedBox(width: double.infinity, child: FilledButton(onPressed: _save, child: const Text('حفظ'))),
          ]),
        ),
      );
}

// ───────────────────────── Settings ─────────────────────────
class SettingsSheet extends StatefulWidget {
  const SettingsSheet({super.key});
  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  late DateTime deadline = plannerStore.settings.deadline;
  late List<double> hours = List<double>.from(plannerStore.settings.hoursByWeekday);
  late int buffer = plannerStore.settings.bufferDays;
  late double videoFactor = plannerStore.settings.videoFactor;
  late double minPerPage = plannerStore.settings.minPerPage;

  Future<void> _save() async {
    await plannerStore.setSettings(PlannerSettings(
      deadline: dOnly(deadline),
      hoursByWeekday: hours,
      bufferDays: buffer,
      videoFactor: videoFactor,
      minPerPage: minPerPage,
    ));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('إعدادات الخطة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: deadline,
                  firstDate: DateTime.now().subtract(const Duration(days: 1)),
                  lastDate: DateTime(DateTime.now().year + 2),
                );
                if (d != null) setState(() => deadline = d);
              },
              icon: const Icon(Icons.flag, size: 18),
              label: Text('الموعد النهائي: ${deadline.day}/${deadline.month}/${deadline.year}'),
            ),
            const SizedBox(height: 14),
            const Text('ساعات المذاكرة المتاحة في كل يوم'),
            for (var i = 0; i < 7; i++)
              Row(children: [
                SizedBox(width: 70, child: Text(_dayNames[i], style: const TextStyle(fontSize: 13))),
                Expanded(
                  child: Slider(
                    value: hours[i],
                    min: 0,
                    max: 10,
                    divisions: 20,
                    activeColor: kAccent,
                    onChanged: (v) => setState(() => hours[i] = v),
                  ),
                ),
                SizedBox(width: 38, child: Text('${hours[i]}', textAlign: TextAlign.end)),
              ]),
            const SizedBox(height: 8),
            Text('أيام الهامش الأخيرة (للمتأخرات والمراجعة فقط): $buffer'),
            Slider(value: buffer.toDouble(), min: 0, max: 4, divisions: 4, activeColor: kAccent, onChanged: (v) => setState(() => buffer = v.round())),
            Text('وقت الفيديو الفعلي = مدته × ${videoFactor.toStringAsFixed(2)}'),
            Slider(value: videoFactor, min: 1, max: 2, divisions: 20, activeColor: kAccent, onChanged: (v) => setState(() => videoFactor = v)),
            Text('دقائق الصفحة الواحدة من الـ PDF: ${minPerPage.toStringAsFixed(1)}'),
            Slider(value: minPerPage, min: 1, max: 8, divisions: 14, activeColor: kAccent, onChanged: (v) => setState(() => minPerPage = v)),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: FilledButton(onPressed: _save, child: const Text('حفظ'))),
          ]),
        ),
      );
}
