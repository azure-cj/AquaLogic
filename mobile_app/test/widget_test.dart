import 'package:aqualogic/app/aqualogic_app.dart';
import 'package:aqualogic/features/auth/screens/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'AquaLogic shell renders dashboard, alert shortcut, and tank flow',
    (WidgetTester tester) async {
      await tester.pumpWidget(const AquaLogicApp());

      expect(find.text('AquaLogic'), findsOneWidget);
      expect(find.text('Waking the tank...'), findsOneWidget);
      expect(find.text('JRed Aquatics'), findsNothing);

      await tester.pump(const Duration(milliseconds: 1500));
      expect(find.text('JRed Aquatics'), findsNothing);
      expect(find.byType(LoginScreen), findsNothing);

      await tester.pump(const Duration(milliseconds: 700));
      expect(find.byType(LoginScreen), findsOneWidget);

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'owner@aqualogic.local');
      await tester.enterText(fields.at(1), 'owner123');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('JRed Aquatics'), findsOneWidget);
      expect(find.text('2 tanks need attention'), findsOneWidget);
      expect(find.byKey(const ValueKey('fleet-status-sheet')), findsOneWidget);
      expect(find.text('Fleet overview'), findsOneWidget);
      expect(find.text('Freshwater C'), findsWidgets);
      expect(find.text('Critical'), findsWidgets);
      expect(find.text('Monitoring'), findsOneWidget);
      expect(find.text('Recent activity'), findsOneWidget);
      expect(find.text('Feeding completed'), findsOneWidget);

      for (final label in ['Home', 'Tanks', 'Alerts', 'More']) {
        expect(find.text(label), findsWidgets);
      }
      expect(find.text('Control'), findsNothing);
      expect(find.byKey(const ValueKey('soft-floating-dock')), findsOneWidget);

      await tester.tap(find.text('Freshwater C').first);
      await tester.pumpAndSettle();
      expect(find.text('Alert detail'), findsNothing);

      await tester.tap(find.text('Critical').first);
      await tester.pumpAndSettle();
      expect(find.text('Alert detail'), findsNothing);

      await tester.drag(
        find.byType(CustomScrollView).first,
        const Offset(0, -420),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('soft-floating-dock')), findsOneWidget);

      await tester.tap(find.text('View alert').first);
      await tester.pumpAndSettle();

      expect(find.text('Alert detail'), findsOneWidget);
      expect(find.text('TDS'), findsOneWidget);
      expect(find.text('Freshwater C'), findsWidgets);
      expect(find.text('TDS is outside the configured range.'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Alert detail'), findsNothing);

      await tester.fling(
        find.byType(CustomScrollView).first,
        const Offset(0, 500),
        1000,
      );
      await tester.pumpAndSettle();
      expect(find.text('JRed Owner'), findsWidgets);

      await tester.tap(find.text('Tanks').last);
      await tester.pumpAndSettle();

      expect(find.text('Your tanks'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('soft-floating-dock-destination-1')),
        findsOneWidget,
      );
      expect(find.text('A quick view of every monitored tank'), findsOneWidget);
      expect(find.text('Display Reef A'), findsOneWidget);
      expect(find.text('Quarantine B'), findsOneWidget);

      await tester.tap(find.text('Display Reef A'));
      await tester.pumpAndSettle();

      expect(find.text('Marine display · 320L'), findsOneWidget);
      expect(find.text('Tank information'), findsOneWidget);
      expect(find.text('320L'), findsWidgets);

      await tester.scrollUntilVisible(
        find.text('Current readings'),
        300,
        scrollable: find.byType(Scrollable).last,
      );

      expect(find.text('Current readings'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Your tanks'), findsOneWidget);

      await tester.tap(find.text('More').last);
      await tester.pumpAndSettle();

      expect(find.text('Fish species'), findsOneWidget);

      await tester.tap(find.text('Fish species'));
      await tester.pumpAndSettle();

      expect(
        find.text('Practical care references for your tanks'),
        findsOneWidget,
      );
      expect(find.text('Discus'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'tang');
      await tester.pumpAndSettle();

      expect(find.text('Yellow Tang'), findsOneWidget);
      expect(find.text('Discus'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
