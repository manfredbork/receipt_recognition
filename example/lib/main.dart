import 'package:example/features/info/info_screen.dart';
import 'package:example/features/result/result_screen.dart';
import 'package:example/features/scan/scan_screen.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

/// Entry point that bootstraps the example Flutter application.
void main() {
  runApp(const ExampleApp());
}

/// Global router for app navigation between info, scan, and result screens.
final _router = GoRouter(
  initialLocation: '/info',
  routes: [
    GoRoute(
      name: 'info',
      path: '/info',
      builder: (ctx, state) => const InfoScreen(),
    ),
    GoRoute(
      name: 'scan',
      path: '/scan',
      builder: (ctx, state) => const ScanScreen(),
    ),
    GoRoute(
      name: 'result',
      path: '/result',
      builder:
          (ctx, state) =>
              ResultScreen(receipt: state.extra as RecognizedReceipt),
    ),
  ],
);

/// Root widget that configures routing and app theme.
class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Receipt Recognition',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.lightGreen),
      ),
      routerConfig: _router,
    );
  }
}
