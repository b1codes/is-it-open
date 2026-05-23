import 'package:flutter/material.dart';
import '../../components/shared/glass_card.dart';
import '../../components/shared/thermal_button.dart';
import '../../utils/app_theme.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSubmitted = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: AppColors.paperWarm,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.inkWarm),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Industrial Header
                Text(
                  'IS IT OPEN?',
                  style: theme.textTheme.displayLarge?.copyWith(
                    letterSpacing: 2.0,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Reset your access',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: AppColors.inkWarmMuted,
                  ),
                ),
                const SizedBox(height: 64),

                // Auth Form
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: GlassCard(
                    child: _isSubmitted ? _buildSuccessState(theme) : _buildFormState(theme),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormState(ThemeData theme) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'RECOVER',
            style: theme.textTheme.displayMedium,
          ),
          const SizedBox(height: 16),
          Text(
            'Enter your email and we\'ll send you instructions to reset your password.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 32),
          
          // Email Field
          TextFormField(
            controller: _emailController,
            decoration: const InputDecoration(
              labelText: 'Email Address',
              prefixIcon: Icon(Icons.email_outlined),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Enter your email';
              }
              return null;
            },
          ),
          const SizedBox(height: 32),
          
          // Primary Action
          ThermalButton(
            onPressed: () {
              if (_formKey.currentState!.validate()) {
                setState(() {
                  _isSubmitted = true;
                });
                // In a real app, this would trigger a BLoC event
              }
            },
            child: const Text('SEND RESET LINK'),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessState(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(
          Icons.mark_email_read_outlined,
          size: 64,
          color: AppColors.openGreen,
        ),
        const SizedBox(height: 24),
        Text(
          'CHECK YOUR EMAIL',
          style: theme.textTheme.displayMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Text(
          'If an account exists for ${_emailController.text}, you will receive a reset link shortly.',
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Back to login',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.terracotta,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}
