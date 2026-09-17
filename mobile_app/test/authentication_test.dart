import 'package:aqualogic/app/aqualogic_app.dart';
import 'package:aqualogic/features/auth/data/mock_auth_service.dart';
import 'package:aqualogic/features/auth/screens/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpToLogin(WidgetTester tester) async {
  await tester.pumpWidget(AquaLogicApp(authService: MockAuthService()));
  await tester.pump(const Duration(milliseconds: 1600));
  await tester.pumpAndSettle();
  expect(find.byType(LoginScreen), findsOneWidget);
}

Future<void> _signIn(
  WidgetTester tester, {
  required String email,
  required String password,
}) async {
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), email);
  await tester.enterText(fields.at(1), password);
  await tester.tap(find.text('Sign in'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('startup reaches Login without showing the dashboard first', (
    tester,
  ) async {
    await tester.pumpWidget(AquaLogicApp(authService: MockAuthService()));

    expect(find.text('Waking the tank...'), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.text('Live readings'), findsNothing);

    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Live readings'), findsNothing);

    final loginContext = tester.element(find.byType(LoginScreen));
    expect(Theme.of(loginContext).textTheme.bodyMedium?.fontFamily, 'Geist');
    expect(find.text('Welcome back'), findsNothing);
  });

  testWidgets('invalid credentials remain on Login with a generic error', (
    tester,
  ) async {
    await _pumpToLogin(tester);

    await _signIn(
      tester,
      email: 'unknown@aqualogic.local',
      password: 'not-the-password',
    );

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Email or password is incorrect.'), findsOneWidget);
    expect(find.text('Live readings'), findsNothing);
  });

  testWidgets('Owner credentials enter the Owner-labelled shell', (
    tester,
  ) async {
    await _pumpToLogin(tester);

    await _signIn(
      tester,
      email: ' OWNER@AQUALOGIC.LOCAL ',
      password: 'owner123',
    );

    expect(find.byType(LoginScreen), findsNothing);
    expect(find.text('JRed Owner'), findsWidgets);
    expect(find.text('OWNER'), findsWidgets);
    expect(find.text('JRed Aquatics'), findsOneWidget);
    expect(find.text('2 tanks need attention'), findsOneWidget);
    expect(find.byKey(const ValueKey('fleet-status-sheet')), findsOneWidget);
    expect(find.text('Fleet overview'), findsOneWidget);
  });

  testWidgets('Staff credentials enter the Staff-labelled shell', (
    tester,
  ) async {
    await _pumpToLogin(tester);

    await _signIn(tester, email: 'staff@aqualogic.local', password: 'staff123');

    expect(find.byType(LoginScreen), findsNothing);
    expect(find.text('AquaLogic Staff'), findsWidgets);
    expect(find.text('STAFF'), findsWidgets);
    expect(find.text('Operations'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home-hero-illustration')),
      findsOneWidget,
    );
    expect(find.text('JRed Aquatics'), findsNothing);
    expect(find.text('Needs attention'), findsOneWidget);
    expect(find.text('Tank rounds'), findsOneWidget);
    expect(find.text('Aquarium status'), findsNothing);
  });

  testWidgets('sign out clears the shell and returns to Login', (tester) async {
    await _pumpToLogin(tester);
    await _signIn(tester, email: 'owner@aqualogic.local', password: 'owner123');

    await tester.tap(find.text('More').last);
    await tester.pumpAndSettle();
    expect(find.text('JRed Owner'), findsWidgets);
    expect(find.text('owner@aqualogic.local'), findsOneWidget);
    expect(find.text('OWNER'), findsWidgets);
    expect(find.text('Sign out'), findsOneWidget);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('JRed Owner'), findsNothing);
    expect(find.text('2 tanks need attention'), findsNothing);
  });

  testWidgets('sign out remains available from the existing Account route', (
    tester,
  ) async {
    await _pumpToLogin(tester);
    await _signIn(tester, email: 'owner@aqualogic.local', password: 'owner123');

    await tester.tap(find.text('More').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('account-profile-panel')));
    await tester.pumpAndSettle();

    expect(find.text('Your local prototype identity'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('account-sign-out-button')));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
  });

  test('mock authentication returns backend-compatible roles', () async {
    final service = MockAuthService();

    final owner = await service.signIn(
      email: 'owner@aqualogic.local',
      password: 'owner123',
    );
    expect(owner?.role.backendValue, 'admin');
    expect(owner?.roleLabel, 'Owner');

    service.signOut();
    final staff = await service.signIn(
      email: 'staff@aqualogic.local',
      password: 'staff123',
    );
    expect(staff?.role.backendValue, 'staff');
    expect(staff?.roleLabel, 'Staff');
  });
}
