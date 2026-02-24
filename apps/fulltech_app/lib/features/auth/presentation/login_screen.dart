import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:validators/validators.dart' as validators;

import '../../../core/auth/auth_provider.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/routing/routes.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../core/widgets/primary_button.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  String? _error;
  bool _rememberMe = false;
  bool _obscurePassword = true;

  static const _rememberEmailKey = 'remember_email';
  static const _rememberPasswordKey = 'remember_password';
  static const _rememberFlagKey = 'remember_flag';

  @override
  void initState() {
    super.initState();
    _loadRememberedCredentials();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRememberedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final remembered = prefs.getBool(_rememberFlagKey) ?? false;
    final email = prefs.getString(_rememberEmailKey) ?? '';
    final password = prefs.getString(_rememberPasswordKey) ?? '';
    if (!mounted) return;
    setState(() {
      _rememberMe = remembered;
      if (remembered) {
        _emailCtrl.text = email;
        _passwordCtrl.text = password;
      }
    });
  }

  Future<void> _persistRememberedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await prefs.setBool(_rememberFlagKey, true);
      await prefs.setString(_rememberEmailKey, _emailCtrl.text.trim());
      await prefs.setString(_rememberPasswordKey, _passwordCtrl.text);
    } else {
      await prefs.remove(_rememberFlagKey);
      await prefs.remove(_rememberEmailKey);
      await prefs.remove(_rememberPasswordKey);
    }
  }

  String _formatLoginError(ApiException error) {
    final code = error.code != null ? 'Código: ${error.code}' : 'Código: N/D';
    final detail = error.message.trim().isEmpty
        ? 'No se recibió detalle del servidor.'
        : error.message.trim();
    return 'No se pudo iniciar sesión.\nCausa exacta: $code\nDetalle: $detail';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!mounted) return;
    setState(() => _error = null);
    try {
      await ref
          .read(authStateProvider.notifier)
          .login(_emailCtrl.text, _passwordCtrl.text);
      await _persistRememberedCredentials();
      if (mounted) {
        context.go(Routes.user);
      }
    } on ApiException catch (e) {
      await ref.read(authStateProvider.notifier).logout();
      if (mounted) {
        setState(() => _error = _formatLoginError(e));
      }
    } catch (e) {
      await ref.read(authStateProvider.notifier).logout();
      if (mounted) {
        setState(
          () => _error =
              'No se pudo iniciar sesión.\nCausa exacta: error inesperado\nDetalle: $e',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading = ref.watch(authStateProvider).loading;
    final size = MediaQuery.of(context).size;
    final cardWidth = (size.width * 0.3).clamp(320.0, 520.0).toDouble();

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0A3D91), Color(0xFF1273D3)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: cardWidth),
            child: Card(
              color: Colors.white,
              elevation: 10,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Colors.black87, width: 1.2),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SingleChildScrollView(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Bienvenido a FullTech',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    color: Colors.black87,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Inicia sesión para continuar.',
                              style: TextStyle(color: Colors.black87),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        TextFormField(
                          controller: _emailCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Email corporativo',
                            prefixIcon: Icon(Icons.alternate_email),
                          ),
                          keyboardType: TextInputType.emailAddress,
                          validator: (v) {
                            final value = v?.trim() ?? '';
                            if (value.isEmpty) return 'Ingresa tu email';
                            if (!validators.isEmail(value)) {
                              return 'Email inválido';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _passwordCtrl,
                          decoration: InputDecoration(
                            labelText: 'Contraseña',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              tooltip: _obscurePassword
                                  ? 'Mostrar contraseña'
                                  : 'Ocultar contraseña',
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          obscureText: _obscurePassword,
                          validator: (v) => (v == null || v.isEmpty)
                              ? 'Ingresa tu contraseña'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Switch(
                              value: _rememberMe,
                              onChanged: (value) {
                                setState(() => _rememberMe = value);
                              },
                              activeThumbColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Recordar contraseña',
                                style: TextStyle(
                                  color: Colors.black87,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          ErrorBanner(message: _error!),
                        ],
                        const SizedBox(height: 16),
                        PrimaryButton(
                          label: 'Iniciar sesión',
                          loading: loading,
                          onPressed: _submit,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
