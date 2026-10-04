import 'package:aqualogic/app/aqualogic_app.dart';
import 'package:aqualogic/features/auth/data/mock_auth_service.dart';
import 'package:flutter/material.dart';

/// Local UI preview: mock authentication selects the existing mock repositories.
/// No push service is injected and no Railway credentials are used.
class AquaLogicPreviewApp extends StatefulWidget {
  const AquaLogicPreviewApp({super.key});

  @override
  State<AquaLogicPreviewApp> createState() => _AquaLogicPreviewAppState();
}

class _AquaLogicPreviewAppState extends State<AquaLogicPreviewApp> {
  final _authService = MockAuthService();

  @override
  void dispose() {
    _authService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: AquaLogicApp(authService: _authService),
  );
}
