import 'package:aqualogic/app/aqualogic_app.dart';
import 'package:aqualogic/app/preview/aqualogic_preview_app.dart';
import 'package:aqualogic/features/auth/data/mock_auth_service.dart';
import 'package:aqualogic/features/auth/screens/login_screen.dart';
import 'package:aqualogic/features/console/screens/tank_console_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'simulated preview signs in and reaches Tank Console without push',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const AquaLogicPreviewApp());
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      final app = tester.widget<AquaLogicApp>(find.byType(AquaLogicApp));
      expect(app.authService, isA<MockAuthService>());
      expect(app.pushNotificationService, isNull);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(Banner), findsNothing);

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'owner@aqualogic.local');
      await tester.enterText(fields.at(1), 'owner123');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsNothing);

      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('more-tank-console')),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      // Bring the tile above the floating navigation dock before tapping it.
      await tester.drag(
        find.byType(CustomScrollView).last,
        const Offset(0, -180),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('more-tank-console')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('enter-console')));
      await tester.pumpAndSettle();
      expect(find.byType(TankConsoleScreen), findsOneWidget);
      expect(find.text('Simulated data'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
}
