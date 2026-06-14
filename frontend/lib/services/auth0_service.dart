import 'package:flutter/material.dart';
import '../components/shared/auth0_universal_login_dialog.dart';

class Auth0Service {
  Future<String?> login(BuildContext context, {String? connection}) async {
    // Show the customized glassmorphic Auth0 Universal Login Dialog
    final String? token = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (context) => Auth0UniversalLoginDialog(connection: connection),
    );
    return token;
  }
}
