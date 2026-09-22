import 'package:aqualogic/app/auth/auth_scope.dart';
import 'package:aqualogic/app/startup/splash_screen.dart';
import 'package:aqualogic/app/startup/widgets/startup_bubbles.dart';
import 'package:aqualogic/app/startup/widgets/startup_waterline.dart';
import 'package:aqualogic/features/auth/data/mock_auth_service.dart';
import 'package:aqualogic/features/auth/models/auth_user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestAuthService extends AuthService {
  _TestAuthService({AuthStatus initialStatus = AuthStatus.unauthenticated})
    : _status = initialStatus;

  AuthStatus _status;

  @override
  AuthStatus get status => _status;

  @override
  AuthUser? get currentUser => null;

  void resolve(AuthStatus status) {
    _status = status;
    notifyListeners();
  }

  @override
  Future<AuthUser?> signIn({
    required String email,
    required String password,
  }) async => null;

  @override
  void signOut() => resolve(AuthStatus.unauthenticated);
}

Widget _app(
  _TestAuthService authService, {
  bool reducedMotion = false,
  Widget next = const Text('Destination'),
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reducedMotion),
      child: AuthScope(
        authService: authService,
        child: SplashScreen(next: next),
      ),
    ),
  );
}

Future<void> _finishStartup(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 280));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows calm AquaLogic branding without fake progress', (
    tester,
  ) async {
    final authService = _TestAuthService();
    await tester.pumpWidget(_app(authService));

    expect(find.text('AquaLogic'), findsOneWidget);
    expect(find.text('Preparing AquaLogic'), findsOneWidget);
    expect(find.byKey(const ValueKey('startup-brand-mark')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('startup-background-illustration')),
      findsOneWidget,
    );
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Waking the tank...'), findsNothing);
    expect(find.text('Destination'), findsNothing);

    await _finishStartup(tester);
    expect(find.text('Destination'), findsOneWidget);
    authService.dispose();
  });

  testWidgets('keeps the minimum display window before handing off', (
    tester,
  ) async {
    final authService = _TestAuthService();
    await tester.pumpWidget(_app(authService));

    await tester.pump(const Duration(milliseconds: 599));
    expect(find.text('Preparing AquaLogic'), findsOneWidget);
    expect(find.text('Destination'), findsNothing);

    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 280));
    await tester.pumpAndSettle();

    expect(find.text('Destination'), findsOneWidget);
    authService.dispose();
  });

  testWidgets('waits for auth destination resolution without fake progress', (
    tester,
  ) async {
    final authService = _TestAuthService(initialStatus: AuthStatus.checking);
    await tester.pumpWidget(_app(authService));

    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.text('Preparing AquaLogic'), findsOneWidget);
    expect(find.text('Destination'), findsNothing);

    authService.resolve(AuthStatus.unauthenticated);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 280));
    await tester.pumpAndSettle();

    expect(find.text('Destination'), findsOneWidget);
    authService.dispose();
  });

  testWidgets('uses the reduced-motion waterline and omits moving bubbles', (
    tester,
  ) async {
    final authService = _TestAuthService(initialStatus: AuthStatus.checking);
    await tester.pumpWidget(_app(authService, reducedMotion: true));

    expect(
      tester
          .widget<StartupWaterline>(
            find.byKey(const ValueKey('startup-waterline')),
          )
          .reducedMotion,
      isTrue,
    );
    expect(
      tester
          .widget<StartupBubbles>(find.byKey(const ValueKey('startup-bubbles')))
          .reducedMotion,
      isTrue,
    );

    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.text('Preparing AquaLogic'), findsOneWidget);

    authService.resolve(AuthStatus.unauthenticated);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 140));
    await tester.pumpAndSettle();

    expect(find.text('Destination'), findsOneWidget);
    authService.dispose();
  });

  testWidgets('fits small and tall phone viewports without overflow', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;

    for (final size in const [Size(320, 568), Size(360, 960)]) {
      tester.view.physicalSize = size;
      final authService = _TestAuthService(initialStatus: AuthStatus.checking);
      await tester.pumpWidget(_app(authService));

      expect(find.text('Preparing AquaLogic'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      authService.dispose();
    }
  });

  testWidgets('can be disposed quickly while ambient animation is active', (
    tester,
  ) async {
    final authService = _TestAuthService(initialStatus: AuthStatus.checking);
    await tester.pumpWidget(_app(authService));
    await tester.pump(const Duration(milliseconds: 80));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    authService.dispose();
  });
}
