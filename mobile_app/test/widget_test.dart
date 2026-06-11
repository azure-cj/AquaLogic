import 'package:aqualogic/app/aqualogic_app.dart';
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

      await tester.pump(const Duration(milliseconds: 700));

      expect(find.text('JRed Aquatics'), findsOneWidget);
      expect(find.text('Live readings'), findsOneWidget);
      expect(find.text('pH Level'), findsOneWidget);
      expect(find.text('SYSTEM NORMAL'), findsOneWidget);

      for (final label in ['Home', 'Tanks', 'Control', 'Alerts', 'More']) {
        expect(find.text(label), findsWidgets);
      }

      await tester.tap(find.text('SYSTEM NORMAL'));
      await tester.pumpAndSettle();

      expect(find.text('Alerts'), findsWidgets);
      expect(find.text('Live recommendations'), findsOneWidget);

      await tester.tap(find.text('Tanks').last);
      await tester.pumpAndSettle();

      expect(find.text('Your tanks'), findsOneWidget);
      expect(find.text('Tap a tank for detailed monitoring'), findsOneWidget);
      expect(find.text('Display Reef A'), findsOneWidget);
      expect(find.text('Quarantine B'), findsOneWidget);

      await tester.tap(find.text('Display Reef A'));
      await tester.pumpAndSettle();

      expect(find.text('Mixed reef - 320L'), findsOneWidget);
      expect(find.text('Tank info'), findsOneWidget);
      expect(find.text('320L'), findsWidgets);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
      await tester.pumpAndSettle();

      expect(find.text('Live sensor readings'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Your tanks'), findsOneWidget);

      await tester.tap(find.text('Control').last);
      await tester.pumpAndSettle();

      expect(find.text('Control panel'), findsOneWidget);
      expect(find.text('LED Lighting'), findsOneWidget);

      await tester.tap(find.text('More').last);
      await tester.pumpAndSettle();

      expect(find.text('Fish library'), findsOneWidget);

      await tester.tap(find.text('Fish library'));
      await tester.pumpAndSettle();

      expect(find.text('Care references'), findsOneWidget);
      expect(find.text('Discus'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'tang');
      await tester.pumpAndSettle();

      expect(find.text('Yellow Tang'), findsOneWidget);
      expect(find.text('Discus'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
