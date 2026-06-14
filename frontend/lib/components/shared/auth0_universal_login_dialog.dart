import 'dart:convert';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';

class Auth0UniversalLoginDialog extends StatefulWidget {
  final String? connection;

  const Auth0UniversalLoginDialog({super.key, this.connection});

  @override
  State<Auth0UniversalLoginDialog> createState() => _Auth0UniversalLoginDialogState();
}

class _Auth0UniversalLoginDialogState extends State<Auth0UniversalLoginDialog> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSignUp = false;

  String _generateMockJwt({
    required String sub,
    required String email,
    required String name,
    String? givenName,
    String? familyName,
  }) {
    final header = {
      "alg": "RS256",
      "typ": "JWT",
      "kid": "mock_kid_123"
    };
    
    final payload = {
      "iss": "https://is-it-open.us.auth0.com/",
      "sub": sub,
      "aud": "https://is-it-open/api",
      "iat": DateTime.now().millisecondsSinceEpoch ~/ 1000,
      "exp": (DateTime.now().millisecondsSinceEpoch ~/ 1000) + 3600,
      "email": email,
      "email_verified": true,
      "name": name,
      "nickname": name.toLowerCase().replaceAll(' ', ''),
      if (givenName != null) "given_name": givenName,
      if (familyName != null) "family_name": familyName,
    };
    
    final headerBase64 = base64Url.encode(utf8.encode(json.encode(header))).replaceAll('=', '');
    final payloadBase64 = base64Url.encode(utf8.encode(json.encode(payload))).replaceAll('=', '');
    final signatureBase64 = base64Url.encode(utf8.encode("mock_signature")).replaceAll('=', '');
    
    return "$headerBase64.$payloadBase64.$signatureBase64";
  }

  void _loginWithSocial(String provider, String name, String email) {
    final cleanProvider = provider.toLowerCase();
    final sub = "$cleanProvider|mock_${cleanProvider}_${email.hashCode.abs()}";
    
    final parts = name.split(' ');
    final givenName = parts.isNotEmpty ? parts.first : name;
    final familyName = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    
    final token = _generateMockJwt(
      sub: sub,
      email: email,
      name: name,
      givenName: givenName,
      familyName: familyName,
    );
    
    Navigator.of(context).pop(token);
  }

  void _submitEmailAuth() {
    if (!_formKey.currentState!.validate()) return;
    
    final email = _emailController.text.trim();
    final name = _isSignUp ? _nameController.text.trim() : email.split('@').first;
    final sub = "auth0|mock_email_${email.hashCode.abs()}";
    
    final token = _generateMockJwt(
      sub: sub,
      email: email,
      name: name,
      givenName: name,
      familyName: '',
    );
    
    Navigator.of(context).pop(token);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Center(
        child: SingleChildScrollView(
          child: Container(
            width: 360,
            margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: AppColors.paperWarm,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.inkWarm.withValues(alpha: 0.1), width: 1.0),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                )
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Auth0 Logo / Title
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.terracotta.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          CupertinoIcons.shield_fill,
                          color: AppColors.terracotta,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'auth0',
                        style: theme.textTheme.displayMedium?.copyWith(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  Text(
                    _isSignUp ? 'Create your account' : 'Welcome',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.displayMedium?.copyWith(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'to continue to Is It Open',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.inkWarmMuted,
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Social Login Section
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildSocialButton(
                        icon: CupertinoIcons.circle_grid_3x3,
                        text: 'Continue with Google',
                        onPressed: () => _loginWithSocial(
                          'google-oauth2',
                          'Brandon Connolly',
                          'brandon.lc.1334@gmail.com',
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildSocialButton(
                        icon: CupertinoIcons.check_mark_circled,
                        text: 'Continue with Apple',
                        onPressed: () => _loginWithSocial(
                          'apple',
                          'Brandon Connolly',
                          'brandon.lc@icloud.com',
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Divider
                  Row(
                    children: [
                      Expanded(child: Divider(color: AppColors.inkWarm.withValues(alpha: 0.1))),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'OR',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.inkWarmMuted,
                          ),
                        ),
                      ),
                      Expanded(child: Divider(color: AppColors.inkWarm.withValues(alpha: 0.1))),
                    ],
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Email/Password Form
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_isSignUp) ...[
                          TextFormField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              labelText: 'Full Name',
                              prefixIcon: Icon(CupertinoIcons.person),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return 'Please enter your name';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                        ],
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Email address',
                            prefixIcon: Icon(CupertinoIcons.mail),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return 'Please enter your email';
                            }
                            if (!val.contains('@')) {
                              return 'Please enter a valid email';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Password',
                            prefixIcon: Icon(CupertinoIcons.lock),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          validator: (val) {
                            if (val == null || val.isEmpty) {
                              return 'Please enter your password';
                            }
                            if (val.length < 6) {
                              return 'Password must be at least 6 characters';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),
                        
                        // Submit Button
                        ElevatedButton(
                          onPressed: _submitEmailAuth,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.terracotta,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text(
                            _isSignUp ? 'SIGN UP' : 'CONTINUE',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Toggle Signup/Login
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _isSignUp ? 'Already have an account?' : 'Don\'t have an account?',
                        style: theme.textTheme.bodyMedium,
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _isSignUp = !_isSignUp;
                          });
                        },
                        child: Text(
                          _isSignUp ? 'Log in' : 'Sign up',
                          style: const TextStyle(
                            color: AppColors.terracotta,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  // Cancel / Close
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: AppColors.inkWarmMuted),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSocialButton({
    required IconData icon,
    required String text,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.inkWarm,
        side: BorderSide(color: AppColors.inkWarm.withValues(alpha: 0.15), width: 1.0),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: AppColors.inkWarm),
          const SizedBox(width: 12),
          Text(
            text,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
