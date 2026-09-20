import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Enforces the dependency rule: presentation -> domain <- data.
void main() {
  const forbiddenInDomain = [
    'package:flutter/',
    'package:flutter_riverpod/',
    'package:go_router/',
    'package:firebase_core/',
    'package:firebase_auth/',
    'package:cloud_firestore/',
    'package:google_sign_in/',
    'package:geolocator/',
    'package:flutter_timezone/',
    'dart:ui',
    '/data/',
    '/presentation/',
  ];

  List<File> dartFiles(String root) {
    final dir = Directory(root);
    if (!dir.existsSync()) return [];
    return dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
  }

  List<String> imports(File file) => file
      .readAsLinesSync()
      .where((line) => line.startsWith('import ') || line.startsWith('export '))
      .toList();

  List<String> violations(Iterable<File> files, List<String> forbidden) => [
        for (final file in files)
          for (final line in imports(file))
            if (forbidden.any(line.contains)) '${file.path}: $line',
      ];

  test('domain code imports no framework, data or presentation code', () {
    final domain = [
      ...dartFiles('lib/features').where((f) => f.path.contains('/domain/')),
      for (final name in ['failure', 'result', 'geo', 'random_codes', 'location_provider', 'rating'])
        File('lib/core/$name.dart'),
    ].where((f) => f.existsSync());
    expect(violations(domain, forbiddenInDomain), isEmpty);
  });

  test('data code never imports presentation code', () {
    final data = dartFiles('lib/features').where((f) => f.path.contains('/data/'));
    expect(violations(data, ['/presentation/']), isEmpty);
  });

  test('presentation code never imports data code', () {
    final presentation = dartFiles('lib/features').where((f) => f.path.contains('/presentation/'));
    expect(violations(presentation, ['/data/']), isEmpty);
  });
}
