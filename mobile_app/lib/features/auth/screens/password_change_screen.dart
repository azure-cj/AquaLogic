import 'package:aqualogic/app/auth/auth_scope.dart';
import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/shared/network/api_failure.dart';
import 'package:flutter/material.dart';

/// Focused first-login password flow shown instead of the authenticated shell.
class PasswordChangeScreen extends StatefulWidget {
  const PasswordChangeScreen({super.key});

  @override
  State<PasswordChangeScreen> createState() => _PasswordChangeScreenState();
}

class _PasswordChangeScreenState extends State<PasswordChangeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  var _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _currentPassword.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      await AuthScope.of(context).changePassword(
        currentPassword: _currentPassword.text,
        newPassword: _newPassword.text,
      );
      _currentPassword.clear();
      _newPassword.clear();
      _confirmPassword.clear();
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = switch (failure.kind) {
          ApiFailureKind.business || ApiFailureKind.validation =>
            'Check your current password and choose a new password you have not used before.',
          ApiFailureKind.forbidden =>
            'You do not have access to change this password.',
          _ => "Can't connect to AquaLogic. Try again.",
        };
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = 'The password could not be changed. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF5FCFD), AppColors.background],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.lock_reset_rounded,
                      color: AppColors.tealDark,
                      size: 38,
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Set a new password',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Choose a password with 12–128 characters to continue to AquaLogic.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _passwordField(
                            label: 'Current password',
                            controller: _currentPassword,
                            validator: (value) => value == null || value.isEmpty
                                ? 'Enter your current password.'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          _passwordField(
                            label: 'New password',
                            controller: _newPassword,
                            validator: (value) {
                              final password = value ?? '';
                              if (password.length < 12) {
                                return 'Use at least 12 characters.';
                              }
                              if (password.length > 128) {
                                return 'Use no more than 128 characters.';
                              }
                              if (password == _currentPassword.text) {
                                return 'Choose a password different from your current one.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          _passwordField(
                            label: 'Confirm new password',
                            controller: _confirmPassword,
                            validator: (value) => value != _newPassword.text
                                ? 'Passwords do not match.'
                                : null,
                          ),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            child: _error == null
                                ? const SizedBox.shrink()
                                : Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: Semantics(
                                      liveRegion: true,
                                      child: Text(
                                        _error!,
                                        style: const TextStyle(
                                          color: AppColors.critical,
                                          fontSize: 12,
                                          height: 1.35,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            height: 52,
                            child: FilledButton(
                              key: const ValueKey('change-password-submit'),
                              onPressed: _isSubmitting ? null : _submit,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.tealDark,
                                foregroundColor: Colors.white,
                              ),
                              child: _isSubmitting
                                  ? const SizedBox(
                                      width: 19,
                                      height: 19,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Update password'),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextButton(
                            onPressed: _isSubmitting
                                ? null
                                : () async {
                                    await AuthScope.of(context).signOut();
                                  },
                            child: const Text('Sign out instead'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _passwordField({
    required String label,
    required TextEditingController controller,
    required String? Function(String?) validator,
  }) => TextFormField(
    controller: controller,
    enabled: !_isSubmitting,
    obscureText: true,
    maxLength: 128,
    autocorrect: false,
    enableSuggestions: false,
    validator: validator,
    textInputAction: TextInputAction.next,
    decoration: InputDecoration(labelText: label),
  );
}
