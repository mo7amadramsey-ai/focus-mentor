import '../models.dart';

const moodleBase = 'https://moodle.ucas.edu.ps/';

bool isMoodleHost(String host) {
  final h = host.toLowerCase();
  return h == 'moodle.ucas.edu.ps' || h.endsWith('.ucas.edu.ps');
}

const _videoExt = {'mp4', 'webm', 'mov', 'mkv', 'm4v', 'avi', 'wmv'};
const _docExt = {'doc', 'docx', 'ppt', 'pptx', 'pps', 'ppsx', 'xls', 'xlsx', 'csv', 'txt', 'rtf', 'odt', 'odp'};
const _fileExt = {'zip', 'rar', '7z', 'apk', 'mp3', 'wav', 'm4a', 'exe'};

String extOf(String path) {
  final i = path.lastIndexOf('.');
  if (i < 0 || i == path.length - 1) return '';
  final e = path.substring(i + 1).toLowerCase();
  return e.length > 6 || e.contains('/') ? '' : e;
}

bool isYoutube(String host) {
  final h = host.toLowerCase();
  return h == 'youtu.be' || h == 'youtube.com' || h.endsWith('.youtube.com') || h == 'youtube-nocookie.com' || h.endsWith('.youtube-nocookie.com');
}

/// Decides the kind of an item from its URL alone.
ItemKind classifyUrl(String url) {
  final u = Uri.tryParse(url);
  if (u == null) return ItemKind.other;
  final host = u.host.toLowerCase();
  String path;
  try {
    path = Uri.decodeFull(u.path).toLowerCase();
  } catch (_) {
    path = u.path.toLowerCase();
  }

  if (isYoutube(host) || host == 'vimeo.com' || host.endsWith('.vimeo.com')) return ItemKind.video;

  final ext = extOf(path);
  if (ext == 'pdf') return ItemKind.pdf;
  if (_videoExt.contains(ext)) return ItemKind.video;
  if (_docExt.contains(ext)) return ItemKind.document;
  if (_fileExt.contains(ext)) return ItemKind.file;

  if (isMoodleHost(host)) {
    if (path.contains('/mod/assign/')) return ItemKind.assignment;
    if (path.contains('/mod/quiz/')) return ItemKind.quiz;
    if (path.contains('/mod/folder/')) return ItemKind.folder;
    if (path.contains('/mod/page/')) return ItemKind.page;
    if (path.contains('/mod/book/')) return ItemKind.book;
    if (path.contains('/mod/forum/')) return ItemKind.forum;
    if (path.contains('/mod/resource/')) return ItemKind.file;
    if (path.contains('/mod/url/')) return ItemKind.link;
    if (path.contains('/mod/videotime/') || path.contains('/mod/kalvidres/') || path.contains('/mod/mediagallery/')) {
      return ItemKind.video;
    }
    if (path.contains('pluginfile.php')) return ItemKind.file;
    return ItemKind.other;
  }
  return ItemKind.link;
}
