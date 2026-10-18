import 'dart:io';
import 'package:path_provider/path_provider.dart';

Future<File> _file(String user) async {
  final folder = await getApplicationSupportDirectory();
  await folder.create(recursive: true);
  return File(
    '${folder.path}/execution-outbox-${Uri.encodeComponent(user)}.json',
  );
}

Future<String?> readOutbox(String user) async {
  final file = await _file(user);
  return await file.exists() ? file.readAsString() : null;
}

Future<void> writeOutbox(String user, String value) async {
  final file = await _file(user);
  final temporary = File('${file.path}.tmp');
  await temporary.writeAsString(value, flush: true);
  await temporary.rename(file.path);
}
