import 'package:aqualogic/app/theme/app_tokens.dart';
import 'package:aqualogic/shared/formatters/freshness_labels.dart';
import 'package:aqualogic/shared/widgets/app_page.dart';
import 'package:aqualogic/shared/widgets/light_page_header.dart';
import 'package:aqualogic/shared/widgets/soft_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('freshness labels use one short current-reading vocabulary', () {
    expect(formatFreshnessLabel('Updated just now'), 'Just now');
    expect(formatFreshnessLabel('Last report 45 sec ago'), '45 sec ago');
    expect(formatFreshnessLabel('No recent report'), 'No recent report');
    expect(formatFreshnessLabel('Started 18 min ago'), 'Started 18 min ago');
  });

  testWidgets(
    'shared page shell applies the common gutter and dock clearance',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
        home: AppPage(
          header: SizedBox(height: 80),
          bottomClearance: AppSpacing.bottomDockClearance,
          children: [Text('Content')],
        ),
        ),
      );

      final padding = tester.widget<SliverPadding>(find.byType(SliverPadding));
      expect(
        padding.padding,
        const EdgeInsets.fromLTRB(
          AppSpacing.pageGutter,
          AppSpacing.pageTop,
          AppSpacing.pageGutter,
          AppSpacing.pageBottom + AppSpacing.bottomDockClearance,
        ),
      );
    },
  );

  testWidgets(
    'light secondary headers share branding and accessible back action',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LightPageHeader(
              title: 'Secondary page',
              subtitle: 'Supporting context',
              onBack: () {},
            ),
          ),
        ),
      );

      expect(find.text('AquaLogic'), findsOneWidget);
      expect(find.text('Secondary page'), findsOneWidget);
      final back = tester.widget<IconButton>(find.byType(IconButton));
      expect(back.tooltip, 'Back');
      expect(back.style?.minimumSize, isNotNull);
    },
  );

  testWidgets('generic soft cards stay border-led without elevation', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: SoftCard(child: Text('Surface'))),
    );

    final card = tester.widget<Container>(find.byType(Container).first);
    final decoration = card.decoration! as BoxDecoration;
    expect(decoration.boxShadow, isNull);
  });
}
