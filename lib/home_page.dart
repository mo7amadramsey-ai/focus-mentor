import 'package:flutter/material.dart';
import 'models.dart';
import 'storage.dart';
import 'sync_page.dart';
import 'theme.dart';
import 'tree_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Tree? tree;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final t = await loadTree();
    if (!mounted) return;
    setState(() {
      tree = t;
      loading = false;
    });
  }

  Future<void> _sync() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const SyncPage()));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = tree;
    final items = t == null ? 0 : t.courses.fold<int>(0, (n, c) => n + c.allItems.length);
    return Scaffold(
      appBar: AppBar(title: const Text('المرشد الدراسي')),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: kOlive))
          : ListView(padding: const EdgeInsets.all(18), children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: cardBox(24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.school_outlined, size: 40, color: kOlive),
                  const SizedBox(height: 12),
                  Text(
                    t == null ? 'ابدأ باستيراد موادك من مودل' : 'آخر استيراد: ${_fmt(t.fetchedAt)}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    t == null
                        ? 'سجّل دخولك مرة واحدة، وسيقرأ التطبيق كل المواد ومحتوياتها ويحفظها على هاتفك.'
                        : '${t.courses.length} مواد · $items عنصر${t.errors.isEmpty ? '' : ' · ${t.errors.length} أخطاء'}',
                    style: const TextStyle(height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  Wrap(spacing: 10, runSpacing: 10, children: [
                    FilledButton.icon(
                      onPressed: _sync,
                      icon: const Icon(Icons.sync),
                      label: Text(t == null ? 'استيراد من مودل' : 'إعادة الاستيراد'),
                    ),
                    if (t != null)
                      OutlinedButton.icon(
                        onPressed: () => Navigator.push(
                            context, MaterialPageRoute(builder: (_) => TreePage(tree: t))),
                        icon: const Icon(Icons.account_tree_outlined),
                        label: const Text('عرض الشجرة'),
                      ),
                  ]),
                ]),
              ),
            ]),
    );
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
