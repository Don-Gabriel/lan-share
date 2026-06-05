import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const LanShareApp());
}

class LanShareApp extends StatelessWidget {
  const LanShareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LAN Share',
      home: const HomeScreen(),
    );
  }
}
