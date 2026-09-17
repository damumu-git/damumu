import 'package:flutter/material.dart';

/// Does not depend on inherited Material/Localizations widgets: the failed
/// subtree might have been responsible for supplying them.
class BuildFailure extends StatelessWidget {
  const BuildFailure({
    required this.title,
    required this.message,
    required this.retryLabel,
    required this.onRetry,
    super.key,
  });

  final String title;
  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: Material(
      color: const Color(0xFFF3F5FA),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_rounded,
                size: 42,
                color: Color(0xFF5B4BDB),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF17162C),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Color(0xFF646477)),
              ),
              const SizedBox(height: 16),
              TextButton(onPressed: onRetry, child: Text(retryLabel)),
            ],
          ),
        ),
      ),
    ),
  );
}
