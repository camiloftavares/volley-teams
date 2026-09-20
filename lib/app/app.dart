import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';

class VolleyApp extends ConsumerWidget {
  const VolleyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
        title: 'Volley Teams',
        routerConfig: ref.watch(routerProvider),
        theme: ThemeData(colorSchemeSeed: Colors.orange, useMaterial3: true),
        darkTheme: ThemeData(
          colorSchemeSeed: Colors.orange,
          brightness: Brightness.dark,
          useMaterial3: true,
        ),
      );
}
