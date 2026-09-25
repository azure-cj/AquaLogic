import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:aqualogic/app/auth/auth_scope.dart';
import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/features/auth/data/mock_auth_service.dart';
import 'package:aqualogic/shared/network/api_failure.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();

  var _isPasswordVisible = false;
  var _isSubmitting = false;
  String? _authError;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  void _clearAuthError() {
    if (_authError != null) setState(() => _authError = null);
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isSubmitting = true;
      _authError = null;
    });

    try {
      final user = await AuthScope.of(context).signIn(
        email: _emailController.text,
        password: _passwordController.text,
      );

      // A successful sign-in changes AuthGate's child and disposes this page.
      if (!mounted || user != null) return;
      setState(() {
        _isSubmitting = false;
        _authError = 'Email or password is incorrect.';
      });
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _authError = _signInError(failure);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _authError = "Can't reach AquaLogic. Try again.";
      });
    }
  }

  String _signInError(ApiFailure failure) => switch (failure.kind) {
    ApiFailureKind.unauthenticated => 'Email or password is incorrect.',
    ApiFailureKind.rateLimited => _rateLimitMessage(failure.retryAfter),
    ApiFailureKind.validation => 'Enter a valid email and password.',
    ApiFailureKind.forbidden => 'This account cannot sign in right now.',
    ApiFailureKind.unknown => failure.message,
    _ => "Can't reach AquaLogic. Try again.",
  };

  String _rateLimitMessage(Duration? retryAfter) {
    if (retryAfter == null || retryAfter == Duration.zero) {
      return 'Sign-in is temporarily limited. Try again shortly.';
    }
    final minutes = (retryAfter.inSeconds / 60).ceil();
    return 'Too many sign-in attempts. Try again in $minutes ${minutes == 1 ? 'minute' : 'minutes'}.';
  }

  void _openDemoAccess() {
    final authService = AuthScope.of(context);
    if (authService is! MockAuthService) return;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return _DemoAccountsSheet(
          accounts: MockAuthService.demoAccounts,
          onSelected: (account) {
            _emailController.text = account.email;
            _passwordController.text = account.password;
            _clearAuthError();
            Navigator.of(context).pop();
            _emailFocusNode.requestFocus();
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final authService = AuthScope.of(context);
    final hasDemoAccess = authService is MockAuthService;
    final screenSize = MediaQuery.sizeOf(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final footerHeight = bottomInset > 0
        ? 104.0
        : (screenSize.height * 0.22).clamp(130.0, 200.0).toDouble();
    final footerOpacity = bottomInset > 0 ? 0.16 : 0.78;

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF5FCFD), AppColors.background],
          ),
        ),
        child: Stack(
          children: [
            const Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _RipplePainter()),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: footerHeight,
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: Opacity(
                    opacity: footerOpacity,
                    child: ClipRect(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: SizedBox(
                          width: screenSize.width,
                          height: screenSize.width * 2 / 3,
                          child: Image.asset(
                            'assets/images/login_underwater_footer.png',
                            fit: BoxFit.fill,
                            alignment: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxHeight < 700;
                  final minHeight = (constraints.maxHeight - 44).clamp(
                    0.0,
                    double.infinity,
                  );

                  return SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(22, 22, 22, 22 + bottomInset),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: minHeight),
                      child: Center(
                        child: Transform.translate(
                          offset: Offset(0, isCompact ? -20 : -34),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 460),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _BrandHeader(compact: isCompact),
                                SizedBox(height: isCompact ? 18 : 28),
                                _LoginContent(
                                  formKey: _formKey,
                                  emailController: _emailController,
                                  passwordController: _passwordController,
                                  emailFocusNode: _emailFocusNode,
                                  passwordFocusNode: _passwordFocusNode,
                                  isPasswordVisible: _isPasswordVisible,
                                  isSubmitting: _isSubmitting,
                                  authError: _authError,
                                  compact: isCompact,
                                  onEmailChanged: (_) => _clearAuthError(),
                                  onPasswordChanged: (_) => _clearAuthError(),
                                  onPasswordVisibilityChanged: () {
                                    final shouldRestoreFocus =
                                        _passwordFocusNode.hasFocus;
                                    setState(
                                      () => _isPasswordVisible =
                                          !_isPasswordVisible,
                                    );
                                    if (shouldRestoreFocus) {
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                            if (mounted) {
                                              _passwordFocusNode.requestFocus();
                                            }
                                          });
                                    }
                                  },
                                  onSubmit: _submit,
                                ),
                                if (hasDemoAccess) ...[
                                  SizedBox(height: isCompact ? 8 : 18),
                                  _DemoAccessAction(onPressed: _openDemoAccess),
                                ],
                                SizedBox(height: isCompact ? 16 : 38),
                                const _LoginFooter(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final logoSize = (MediaQuery.sizeOf(context).width * 0.29)
        .clamp(compact ? 92.0 : 98.0, compact ? 104.0 : 112.0)
        .toDouble();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          image: true,
          label: 'AquaLogic official logo',
          child: Image.asset(
            'assets/images/aqualogic_icon.png',
            width: logoSize,
            height: logoSize,
            fit: BoxFit.contain,
            semanticLabel: 'AquaLogic official logo',
          ),
        ),
        SizedBox(height: compact ? 2 : 3),
        Text(
          'AquaLogic',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.text,
            fontSize: compact ? 28 : 30,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 1),
        const Text(
          'Aquarium operations',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.muted,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.15,
            height: 1.25,
          ),
        ),
      ],
    );
  }
}

class _LoginContent extends StatelessWidget {
  const _LoginContent({
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.emailFocusNode,
    required this.passwordFocusNode,
    required this.isPasswordVisible,
    required this.isSubmitting,
    required this.authError,
    required this.compact,
    required this.onEmailChanged,
    required this.onPasswordChanged,
    required this.onPasswordVisibilityChanged,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final FocusNode emailFocusNode;
  final FocusNode passwordFocusNode;
  final bool isPasswordVisible;
  final bool isSubmitting;
  final String? authError;
  final bool compact;
  final ValueChanged<String> onEmailChanged;
  final ValueChanged<String> onPasswordChanged;
  final VoidCallback onPasswordVisibilityChanged;
  final VoidCallback onSubmit;

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Enter your email.';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Enter your password.';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _LoginFields(
                emailController: emailController,
                passwordController: passwordController,
                emailFocusNode: emailFocusNode,
                passwordFocusNode: passwordFocusNode,
                isPasswordVisible: isPasswordVisible,
                isSubmitting: isSubmitting,
                compact: compact,
                validateEmail: _validateEmail,
                validatePassword: _validatePassword,
                onEmailChanged: onEmailChanged,
                onPasswordChanged: onPasswordChanged,
                onPasswordVisibilityChanged: onPasswordVisibilityChanged,
                onPasswordSubmitted: onSubmit,
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: authError == null
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: 7, left: 2),
                        child: Semantics(
                          liveRegion: true,
                          container: true,
                          label: authError,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 1),
                                child: Icon(
                                  LucideIcons.circleAlert,
                                  color: AppColors.critical,
                                  size: 14,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  authError!,
                                  style: const TextStyle(
                                    color: AppColors.critical,
                                    fontSize: 12,
                                    height: 1.25,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
              SizedBox(height: compact ? 10 : 14),
              SizedBox(
                height: compact ? 52 : 54,
                child: FilledButton(
                  onPressed: isSubmitting ? null : onSubmit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.tealDark,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.tealDark.withValues(
                      alpha: 0.58,
                    ),
                    disabledForegroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: isSubmitting
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(width: 10),
                            Text('Signing in…'),
                          ],
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('Sign in'),
                            SizedBox(width: 7),
                            Icon(LucideIcons.arrowRight, size: 19),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LoginFields extends StatelessWidget {
  const _LoginFields({
    required this.emailController,
    required this.passwordController,
    required this.emailFocusNode,
    required this.passwordFocusNode,
    required this.isPasswordVisible,
    required this.isSubmitting,
    required this.compact,
    required this.validateEmail,
    required this.validatePassword,
    required this.onEmailChanged,
    required this.onPasswordChanged,
    required this.onPasswordVisibilityChanged,
    required this.onPasswordSubmitted,
  });

  final TextEditingController emailController;
  final TextEditingController passwordController;
  final FocusNode emailFocusNode;
  final FocusNode passwordFocusNode;
  final bool isPasswordVisible;
  final bool isSubmitting;
  final bool compact;
  final String? Function(String?) validateEmail;
  final String? Function(String?) validatePassword;
  final ValueChanged<String> onEmailChanged;
  final ValueChanged<String> onPasswordChanged;
  final VoidCallback onPasswordVisibilityChanged;
  final VoidCallback onPasswordSubmitted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LoginField(
          label: 'Email',
          hintText: 'you@example.com',
          icon: LucideIcons.mail,
          controller: emailController,
          focusNode: emailFocusNode,
          enabled: !isSubmitting,
          validator: validateEmail,
          onChanged: onEmailChanged,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          onFieldSubmitted: () => passwordFocusNode.requestFocus(),
          autofillHints: const [AutofillHints.username, AutofillHints.email],
        ),
        SizedBox(height: compact ? 10 : 12),
        _LoginField(
          label: 'Password',
          hintText: 'Enter your password',
          icon: LucideIcons.lockKeyhole,
          controller: passwordController,
          focusNode: passwordFocusNode,
          enabled: !isSubmitting,
          validator: validatePassword,
          onChanged: onPasswordChanged,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: onPasswordSubmitted,
          obscureText: !isPasswordVisible,
          autofillHints: const [AutofillHints.password],
          trailing: Semantics(
            button: true,
            label: isPasswordVisible ? 'Hide password' : 'Show password',
            child: IconButton(
              tooltip: isPasswordVisible ? 'Hide password' : 'Show password',
              onPressed: isSubmitting ? null : onPasswordVisibilityChanged,
              style: IconButton.styleFrom(
                foregroundColor: AppColors.tealDark.withValues(alpha: 0.72),
                backgroundColor: Colors.transparent,
                overlayColor: Colors.transparent,
                minimumSize: const Size(48, 48),
                padding: EdgeInsets.zero,
              ),
              icon: Icon(
                isPasswordVisible ? LucideIcons.eyeOff : LucideIcons.eye,
                size: 19,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LoginField extends StatefulWidget {
  const _LoginField({
    required this.label,
    required this.hintText,
    required this.icon,
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.validator,
    required this.onChanged,
    required this.textInputAction,
    required this.onFieldSubmitted,
    this.keyboardType,
    this.obscureText = false,
    this.autofillHints,
    this.trailing,
  });

  final String label;
  final String hintText;
  final IconData icon;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final String? Function(String?) validator;
  final ValueChanged<String> onChanged;
  final TextInputAction textInputAction;
  final VoidCallback onFieldSubmitted;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Iterable<String>? autofillHints;
  final Widget? trailing;

  @override
  State<_LoginField> createState() => _LoginFieldState();
}

class _LoginFieldState extends State<_LoginField> {
  String? _errorText;

  String? _validate(String? value) {
    final nextError = widget.validator(value);
    if (nextError != _errorText) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _errorText == nextError) return;
        setState(() => _errorText = nextError);
      });
    }
    return nextError;
  }

  InputDecoration _inputDecoration() {
    return InputDecoration(
      hintText: widget.hintText,
      filled: false,
      fillColor: Colors.transparent,
      hintStyle: const TextStyle(
        color: AppColors.muted,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.2,
      ),
      isDense: true,
      contentPadding: EdgeInsets.zero,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      focusedErrorBorder: InputBorder.none,
      errorStyle: const TextStyle(
        color: Colors.transparent,
        fontSize: 0,
        height: 0,
      ),
      errorMaxLines: 2,
    );
  }

  Widget _fieldError() {
    final errorText = _errorText;
    if (errorText == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 5, left: 2, right: 2),
      child: Semantics(
        liveRegion: true,
        container: true,
        label: errorText,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(
                LucideIcons.circleAlert,
                color: AppColors.critical,
                size: 13,
              ),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                errorText,
                style: const TextStyle(
                  color: AppColors.critical,
                  fontSize: 11.5,
                  height: 1.2,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(14);

    return AnimatedBuilder(
      animation: widget.focusNode,
      builder: (context, _) {
        final hasFocus = widget.focusNode.hasFocus;
        final hasError = _errorText != null;
        final accentColor = hasError
            ? AppColors.critical
            : hasFocus
            ? const Color(0xFF13A9B8)
            : Colors.transparent;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExcludeSemantics(
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 160),
                style: TextStyle(
                  color: hasError
                      ? AppColors.critical
                      : hasFocus
                      ? AppColors.tealDark
                      : AppColors.text,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
                child: Text(widget.label),
              ),
            ),
            const SizedBox(height: 6),
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              constraints: const BoxConstraints(minHeight: 54),
              decoration: BoxDecoration(
                color: hasError
                    ? AppColors.critical.withValues(alpha: 0.04)
                    : hasFocus
                    ? Colors.white
                    : const Color(0xFFF8FBFB),
                borderRadius: radius,
                border: Border.all(
                  color: hasError
                      ? AppColors.critical.withValues(alpha: 0.5)
                      : hasFocus
                      ? const Color(0xFF7ACFD7)
                      : const Color(0xFFD8E6E8),
                  width: hasFocus ? 1.2 : 1,
                ),
                boxShadow: hasFocus
                    ? [
                        const BoxShadow(
                          color: Color(0x2413A9B8),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: ClipRRect(
                borderRadius: radius,
                child: Stack(
                  children: [
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 160),
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: hasError || hasFocus ? 3 : 0,
                      child: ColoredBox(color: accentColor),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 3,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(
                              widget.icon,
                              size: 18,
                              color: hasError
                                  ? AppColors.critical
                                  : hasFocus
                                  ? AppColors.tealDark
                                  : AppColors.tealDark.withValues(alpha: 0.72),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Semantics(
                                label: widget.label,
                                hint: widget.hintText,
                                child: TextFormField(
                                  controller: widget.controller,
                                  focusNode: widget.focusNode,
                                  enabled: widget.enabled,
                                  autovalidateMode:
                                      AutovalidateMode.onUserInteraction,
                                  keyboardType: widget.keyboardType,
                                  textInputAction: widget.textInputAction,
                                  textAlignVertical: TextAlignVertical.center,
                                  autofillHints: widget.autofillHints,
                                  obscureText: widget.obscureText,
                                  onChanged: widget.onChanged,
                                  onFieldSubmitted: (_) =>
                                      widget.onFieldSubmitted(),
                                  style: const TextStyle(
                                    color: AppColors.text,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    height: 1.2,
                                  ),
                                  cursorColor: AppColors.tealDark,
                                  decoration: _inputDecoration(),
                                  validator: _validate,
                                ),
                              ),
                            ),
                            if (widget.trailing != null) ...[
                              const SizedBox(width: 2),
                              SizedBox(
                                width: 48,
                                height: 48,
                                child: widget.trailing,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _fieldError(),
          ],
        );
      },
    );
  }
}

class _DemoAccessAction extends StatelessWidget {
  const _DemoAccessAction({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: AppColors.tealDark,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Demo access'),
          const SizedBox(width: 7),
          const Icon(LucideIcons.arrowRight, size: 16),
        ],
      ),
    );
  }
}

class _LoginFooter extends StatelessWidget {
  const _LoginFooter();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text(
          'AquaLogic · JRed Aquatics',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.muted,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.25,
          ),
        ),
      ],
    );
  }
}

class _DemoAccountsSheet extends StatelessWidget {
  const _DemoAccountsSheet({required this.accounts, required this.onSelected});

  final List<MockAuthAccount> accounts;
  final ValueChanged<MockAuthAccount> onSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Demo access',
              style: TextStyle(
                color: AppColors.text,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Choose a local prototype experience.',
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 14),
            for (final account in accounts) ...[
              _DemoAccountOption(account: account, onPressed: onSelected),
              if (account != accounts.last) const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _DemoAccountOption extends StatelessWidget {
  const _DemoAccountOption({required this.account, required this.onPressed});

  final MockAuthAccount account;
  final ValueChanged<MockAuthAccount> onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: () => onPressed(account),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        alignment: Alignment.centerLeft,
        foregroundColor: AppColors.text,
        side: const BorderSide(color: AppColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Row(
        children: [
          const Icon(
            LucideIcons.userRound,
            color: AppColors.tealDark,
            size: 19,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.role.displayLabel,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  account.email,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            LucideIcons.arrowRight,
            color: AppColors.tealDark,
            size: 17,
          ),
        ],
      ),
    );
  }
}

class _RipplePainter extends CustomPainter {
  const _RipplePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final shortSide = size.shortestSide;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = AppColors.teal.withValues(alpha: 0.025);

    final center = Offset(size.width * 0.5, size.height * 0.13);
    for (final scale in [0.18, 0.28]) {
      canvas.drawCircle(center, shortSide * scale, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
