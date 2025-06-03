import 'package:example/views/receipt_recognition_view.dart';
import 'package:flutter/material.dart';

/// Entry point of the Receipt Recognition example app.
void main() {
  runApp(const ExampleApp());
}

/// The root widget of the Receipt Recognition example application.
///
/// Sets up a basic [MaterialApp] with theming and launches the
/// [ReceiptRecognitionView] as the home screen.
class ExampleApp extends StatelessWidget {
  /// Creates an instance of [ExampleApp].
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Receipt Recognition',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.lightGreen),
      ),
      home: const ReceiptRecognitionView(),
    );
  }
}
