import 'dart:convert';
import 'dart:io';

import 'package:grumpy_context/grumpy_context.dart';

Future<void> main() async {
  final context = await analyzeProject(Directory.current.path);
  print(const JsonEncoder.withIndent('  ').convert(context.toJson()));
}
