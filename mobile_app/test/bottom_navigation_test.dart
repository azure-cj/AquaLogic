import 'package:aqualogic/app/navigation/aqualogic_shell.dart';
import 'package:aqualogic/features/auth/models/auth_user.dart';
import 'package:aqualogic/features/auth/models/user_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const owner = AuthUser(
    id: 'owner',
    name: 'JRed Owner',
    email: 'owner@aqualogic.local',
    role: UserRole.admin,
  );

  testWidgets(
    'soft floating dock hides and restores without resizing the page',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpWidget(
        const MaterialApp(home: AquaLogicShell(user: owner)),
      );
      await tester.pumpAndSettle();

      final dock = find.byKey(const ValueKey('soft-floating-dock'));
      final fade = find.byKey(const ValueKey('soft-floating-dock-fade'));
      final position = find.byKey(
        const ValueKey('soft-floating-dock-position'),
      );
      final homeScroll = find.byType(CustomScrollView).first;

      expect(dock, findsOneWidget);
      expect(tester.widget<AnimatedOpacity>(fade).opacity, 1);
      expect(tester.getSize(dock), const Size(362, 70));
      expect(tester.widget<AnimatedPositioned>(position).bottom, 0);

      await tester.fling(homeScroll, const Offset(0, -140), 1000);
      await tester.pump();
      expect(tester.widget<AnimatedPositioned>(position).bottom, -80);
      await tester.pump(const Duration(milliseconds: 280));
      expect(tester.widget<AnimatedPositioned>(position).bottom, -80);
      expect(tester.widget<AnimatedOpacity>(fade).opacity, 0);

      await tester.fling(homeScroll, const Offset(0, 80), 1000);
      await tester.pump();
      expect(tester.widget<AnimatedPositioned>(position).bottom, 0);
      expect(tester.widget<AnimatedOpacity>(fade).opacity, 1);

      await tester.drag(homeScroll, const Offset(0, -100));
      await tester.pump(const Duration(milliseconds: 280));
      expect(tester.widget<AnimatedPositioned>(position).bottom, -80);

      await tester.tap(find.text('View all').first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tanks-page-title')), findsOneWidget);
      expect(tester.widget<AnimatedPositioned>(position).bottom, 0);

      await tester.tap(find.byKey(const ValueKey('tank-filter-attention')));
      await tester.pumpAndSettle();
      expect(tester.widget<AnimatedPositioned>(position).bottom, 0);
    },
  );

  testWidgets('floating dock exposes the current four destinations', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: AquaLogicShell(user: owner)),
    );
    await tester.pumpAndSettle();

    for (final label in ['Home', 'Tanks', 'Alerts', 'More']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Control'), findsNothing);
    expect(find.byKey(const ValueKey('soft-floating-dock')), findsOneWidget);
  });
}
