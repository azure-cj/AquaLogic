import 'package:aqualogic/app/preview/aqualogic_preview_app.dart';
import 'package:flutter/widgets.dart';

/// Explicit UI-only entry point. The normal main.dart remains API-backed.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AquaLogicPreviewApp());
}
