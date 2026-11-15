import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'models.dart';

Future<File> _file() async => File('${(await getApplicationDocumentsDirectory()).path}/tree.json');

Future<void> saveTree(Tree t) async => (await _file()).writeAsString(jsonEncode(t.toJson()));

Future<Tree?> loadTree() async {
  try {
    final f = await _file();
    if (!await f.exists()) return null;
    return Tree.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
}
