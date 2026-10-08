// Renders the console at the Galaxy Tab A 8.0 (SM-T290) landscape canvas,
// 1280x800 px at density 213, about 960x600 logical pixels.
// Captures PNGs only when AQUALOGIC_CONSOLE_CAPTURE names an output directory.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:aqualogic/features/console/data/console_repository.dart';
import 'package:aqualogic/features/console/data/mock_console_repository.dart';
import 'package:aqualogic/features/console/platform/console_display_session.dart';
import 'package:aqualogic/features/console/screens/tank_console_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Display implements ConsoleDisplaySession {
  @override
  Future<void> enter() async {}
  @override
  Future<void> exit() async {}
}

final _directory = Platform.environment['AQUALOGIC_CONSOLE_CAPTURE'];
const _tabA = Size(960, 600);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (_directory == null) return;
    final text = FontLoader('Geist');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      text.addFont(rootBundle.load('assets/fonts/Geist-$weight.ttf'));
    }
    await text.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  Future<MockConsoleRepository> open(
    WidgetTester tester,
    GlobalKey boundary,
    ConsoleScenario scenario, {
    bool locked = false,
  }) async {
    tester.view.physicalSize = _tabA;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = MockConsoleRepository();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'Geist', useMaterial3: true),
          home: TankConsoleScreen(
            repository: repository,
            displaySession: _Display(),
            initiallyLocked: locked,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() => repository.applyScenario(scenario));
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }
    return repository;
  }

  Future<void> close(WidgetTester tester, MockConsoleRepository repo) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(repo.dispose);
  }

  for (final (name, locked, target) in [
    ('display', true, null),
    ('control', false, null),
    ('light', false, find.byTooltip('Lighting details')),
    ('feeder', false, find.byTooltip('Feeder details')),
    ('pump', false, find.byKey(const ValueKey('console-pump-a'))),
  ]) {
    testWidgets('console renders $name at Tab A size', (tester) async {
      final boundary = GlobalKey();
      final repo = await open(
        tester,
        boundary,
        ConsoleScenario.critical,
        locked: locked,
      );
      if (target != null) {
        await tester.tap(target);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 900));
      }
      expect(tester.takeException(), isNull);
      await _capture(tester, boundary, name);
      await close(tester, repo);
    });
  }
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final directory = _directory;
  if (directory == null) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.333);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(
      '$directory/console-$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
