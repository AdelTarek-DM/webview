import 'package:flutter/material.dart';
import 'login_page.dart';
import 'app_config.dart';

void main() {
  AppConfig.validate();
  runApp(const PortfolioApp());
}

class PortfolioApp extends StatelessWidget {
  const PortfolioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Your Name - Portfolio',
      debugShowCheckedModeBanner: false,
      home: const LoginPage(),
    );
  }
}
