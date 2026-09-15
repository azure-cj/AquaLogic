import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:aqualogic/app/auth/auth_scope.dart';
import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/features/auth/data/mock_auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  var _isPasswordVisible = false;
  var _isSubmitting = false;
  String? _authError;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isSubmitting = true;
      _authError = null;
    });

    final authService = AuthScope.of(context);
    final user = await authService.signIn(
      email: _emailController.text,
      password: _passwordController.text,
    );

    if (!mounted || user != null) return;
    setState(() {
      _isSubmitting = false;
      _authError = 'Incorrect email or password.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final authService = AuthScope.of(context);
    final mockService = authService is MockAuthService ? authService : null;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                22,
                28,
                22,
                24 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 52,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _BrandHeader(),
                    const SizedBox(height: 32),
                    _LoginFormCard(
                      formKey: _formKey,
                      emailController: _emailController,
                      passwordController: _passwordController,
                      isPasswordVisible: _isPasswordVisible,
                      isSubmitting: _isSubmitting,
                      authError: _authError,
                      onPasswordVisibilityChanged: () {
                        setState(
                          () => _isPasswordVisible = !_isPasswordVisible,
                        );
                      },
                      onSubmit: _submit,
                    ),
                    if (mockService != null) ...[
                      const SizedBox(height: 14),
                      const _DemoAccountsCard(
                        accounts: MockAuthService.demoAccounts,
                      ),
                    ],
                    const SizedBox(height: 28),
                    Text(
                      'Local prototype access · No backend connection',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 62,
          height: 62,
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.line),
            boxShadow: [
              BoxShadow(
                color: AppColors.tealDark.withValues(alpha: 0.1),
                blurRadius: 16,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Image.asset(
            'assets/images/aqualogic_icon.png',
            fit: BoxFit.contain,
            semanticLabel: 'AquaLogic app icon',
          ),
        ),
        const SizedBox(width: 14),
        const Text(
          'AquaLogic',
          style: TextStyle(
            color: AppColors.text,
            fontSize: 25,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _LoginFormCard extends StatelessWidget {
  const _LoginFormCard({
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.isPasswordVisible,
    required this.isSubmitting,
    required this.authError,
    required this.onPasswordVisibilityChanged,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool isPasswordVisible;
  final bool isSubmitting;
  final String? authError;
  final VoidCallback onPasswordVisibilityChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.line),
        boxShadow: [
          BoxShadow(
            color: AppColors.tealDark.withValues(alpha: 0.08),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Welcome back',
              style: TextStyle(
                color: AppColors.text,
                fontSize: 27,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Sign in to monitor and manage your aquariums.',
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: emailController,
              enabled: !isSubmitting,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [
                AutofillHints.username,
                AutofillHints.email,
              ],
              decoration: const InputDecoration(
                labelText: 'Email',
                hintText: 'you@example.com',
                prefixIcon: Icon(LucideIcons.mail),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Enter your email';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: passwordController,
              enabled: !isSubmitting,
              obscureText: !isPasswordVisible,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              onFieldSubmitted: (_) => onSubmit(),
              decoration: InputDecoration(
                labelText: 'Password',
                hintText: 'Enter your password',
                prefixIcon: const Icon(LucideIcons.lockKeyhole),
                suffixIcon: IconButton(
                  tooltip: isPasswordVisible
                      ? 'Hide password'
                      : 'Show password',
                  onPressed: isSubmitting ? null : onPasswordVisibilityChanged,
                  icon: Icon(
                    isPasswordVisible ? LucideIcons.eyeOff : LucideIcons.eye,
                  ),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Enter your password';
                }
                return null;
              },
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: authError == null
                  ? const SizedBox(height: 14)
                  : Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Semantics(
                        liveRegion: true,
                        container: true,
                        label: authError,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              LucideIcons.circleAlert,
                              color: AppColors.critical,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                authError!,
                                style: const TextStyle(
                                  color: AppColors.critical,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: isSubmitting ? null : onSubmit,
                icon: isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(LucideIcons.arrowRight, size: 19),
                label: Text(isSubmitting ? 'Signing in...' : 'Sign in'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DemoAccountsCard extends StatelessWidget {
  const _DemoAccountsCard({required this.accounts});

  final List<MockAuthAccount> accounts;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
      ),
      child: Material(
        color: Colors.transparent,
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          leading: const Icon(LucideIcons.info, color: AppColors.tealDark),
          title: const Text(
            'Development access',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          subtitle: const Text(
            'Owner and Staff demo accounts available',
            style: TextStyle(color: AppColors.muted, fontSize: 11),
          ),
          children: [
            for (final account in accounts) ...[
              _DemoAccountRow(account: account),
              if (account != accounts.last) const Divider(height: 18),
            ],
          ],
        ),
      ),
    );
  }
}

class _DemoAccountRow extends StatelessWidget {
  const _DemoAccountRow({required this.account});

  final MockAuthAccount account;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                account.role.displayLabel,
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                account.email,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                account.password,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.mint,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            account.role.badgeLabel,
            style: const TextStyle(
              color: AppColors.tealDark,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ],
    );
  }
}
