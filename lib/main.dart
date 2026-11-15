import 'package:flutter/material.dart';
import 'home_page.dart';
import 'theme.dart';

void main() => runApp(const MurshidApp());

class MurshidApp extends StatelessWidget {
  const MurshidApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'المرشد الدراسي',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        // Arabic-first app: force right-to-left layout
        builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
        home: const HomePage(),
      );
}
