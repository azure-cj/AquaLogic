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
      final slide = find.byKey(const ValueKey('soft-floating-dock-slide'));
      final homeScroll = find.byType(CustomScrollView).first;

      expect(dock, findsOneWidget);
      expect(tester.widget<AnimatedOpacity>(fade).opacity, 1);
      expect(tester.getSize(dock), const Size(362, 70));
      expect(tester.widget<AnimatedSlide>(slide).offset, Offset.zero);

      await tester.fling(homeScroll, const Offset(0, -140), 1000);
      await tester.pump();
      expect(tester.widget<AnimatedSlide>(slide).offset, const Offset(0, 1.25));
      await tester.pump(const Duration(milliseconds: 240));
      expect(tester.widget<AnimatedSlide>(slide).offset, const Offset(0, 1.25));
      expect(tester.widget<AnimatedOpacity>(fade).opacity, 0);

      await tester.fling(homeScroll, const Offset(0, 80), 1000);
      await tester.pump();
      expect(tester.widget<AnimatedSlide>(slide).offset, Offset.zero);
      expect(tester.widget<AnimatedOpacity>(fade).opacity, 1);

      await tester.drag(homeScroll, const Offset(0, -100));
      await tester.pump(const Duration(milliseconds: 240));
      expect(tester.widget<AnimatedSlide>(slide).offset, const Offset(0, 1.25));

      await tester.tap(find.text('View all').first);
      await tester.pumpAndSettle();
      expect(find.text('Your tanks'), findsOneWidget);
      expect(tester.widget<AnimatedSlide>(slide).offset, Offset.zero);

      await tester.drag(find.text('Needs attention'), const Offset(-80, 0));
      await tester.pumpAndSettle();
      expect(tester.widget<AnimatedSlide>(slide).offset, Offset.zero);
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
