import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _loginFormKey = GlobalKey<FormState>();
  final _signupFormKey = GlobalKey<FormState>();

  final _loginEmailController = TextEditingController();
  final _loginPasswordController = TextEditingController();

  final _signupNameController = TextEditingController();
  final _signupEmailController = TextEditingController();
  final _signupPasswordController = TextEditingController();
  final _signupConfirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _obscureLoginPassword = true;
  bool _obscureSignupPassword = true;
  bool _obscureSignupConfirmPassword = true;
  String _passwordStrength = '';
  Color _passwordStrengthColor = Colors.grey;
  double _passwordStrengthPercent = 0.0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _signupPasswordController.addListener(_checkPasswordStrength);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _loginEmailController.dispose();
    _loginPasswordController.dispose();
    _signupNameController.dispose();
    _signupEmailController.dispose();
    _signupPasswordController.dispose();
    _signupConfirmPasswordController.dispose();
    super.dispose();
  }

  void _checkPasswordStrength() {
    final password = _signupPasswordController.text;
    if (password.isEmpty) {
      setState(() {
        _passwordStrength = '';
        _passwordStrengthPercent = 0.0;
        _passwordStrengthColor = Colors.grey;
      });
      return;
    }

    if (password.length < 6) {
      setState(() {
        _passwordStrength = 'Weak';
        _passwordStrengthPercent = 0.33;
        _passwordStrengthColor = const Color(0xFFEF4444); // red
      });
    } else if (password.length < 10) {
      setState(() {
        _passwordStrength = 'Medium';
        _passwordStrengthPercent = 0.66;
        _passwordStrengthColor = const Color(0xFFF59E0B); // amber
      });
    } else {
      setState(() {
        _passwordStrength = 'Strong';
        _passwordStrengthPercent = 1.0;
        _passwordStrengthColor = const Color(0xFF22C55E); // green
      });
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w500)),
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w500)),
        backgroundColor: const Color(0xFFE65C00),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _handleLogin() async {
    if (!_loginFormKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;
      final response = await supabase.auth.signInWithPassword(
        email: _loginEmailController.text.trim(),
        password: _loginPasswordController.text,
      );

      if (response.user != null) {
        _showSuccessSnackBar('Welcome back!');
        if (!mounted) return;

        // Fetch user record to check role
        final userData = await supabase
            .from('users')
            .select()
            .eq('id', response.user!.id)
            .maybeSingle();

        if (!mounted) return;

        if (userData == null || userData['role'] == null) {
          Navigator.of(context).pushReplacementNamed('/role-select');
        } else {
          final String role = userData['role'];
          if (role == 'admin') {
            Navigator.of(context).pushReplacementNamed('/admin/home');
          } else {
            Navigator.of(context).pushReplacementNamed('/member/home');
          }
        }
      }
    } on AuthException catch (e) {
      _showErrorSnackBar(e.message);
    } catch (e) {
      _showErrorSnackBar('Login failed. Please check your credentials.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSignup() async {
    if (!_signupFormKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;
      final response = await supabase.auth.signUp(
        email: _signupEmailController.text.trim(),
        password: _signupPasswordController.text,
        data: {
          'full_name': _signupNameController.text.trim(),
        },
      );

      if (response.user != null) {
        // Create user profile record
        try {
          await supabase.from('users').upsert({
            'id': response.user!.id,
            'email': response.user!.email!,
            'full_name': _signupNameController.text.trim(),
            'nickname': _signupNameController.text.trim().split(' ').first,
            'role': null, // role = null as per requirements
          });
        } catch (dbErr) {
          // If upsert fails (e.g. trigger constraints), try updating the record
          try {
            await supabase.from('users').update({
              'full_name': _signupNameController.text.trim(),
              'nickname': _signupNameController.text.trim().split(' ').first,
              'role': null,
            }).eq('id', response.user!.id);
          } catch (updateErr) {
            print('DB user update failed: $updateErr');
          }
        }

        _showSuccessSnackBar('Account created successfully!');
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/role-select');
      }
    } on AuthException catch (e) {
      if (e.message.toLowerCase().contains('already') || e.message.toLowerCase().contains('registered')) {
        _showErrorSnackBar('Email already registered. Please login instead.');
      } else {
        _showErrorSnackBar(e.message);
      }
    } catch (e) {
      final String errStr = e.toString();
      if (errStr.toLowerCase().contains('already') || errStr.toLowerCase().contains('registered')) {
        _showErrorSnackBar('Email already registered. Please login instead.');
      } else {
        _showErrorSnackBar('Signup failed. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleOAuth(String provider) async {
    _showErrorSnackBar('$provider login support is disabled in Milestone 1.');
  }

  Future<void> _handleForgotPassword() async {
    final email = _loginEmailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _showErrorSnackBar('Please enter your email first to request a reset link.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      _showSuccessSnackBar('Password reset link sent to your email.');
    } catch (e) {
      _showErrorSnackBar('Error requesting password reset: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBF5EE),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              // Silence Logo & Heading decoration
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Image.asset(
                    'assets/images/horizontal app logo.png',
                    height: 54,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Interactive Login/Signup Card Container
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 16, offset: const Offset(0, 4)),
                  ],
                ),
                child: Column(
                  children: [
                    // Tab Bar
                    TabBar(
                      controller: _tabController,
                      indicatorColor: const Color(0xFFE65C00),
                      labelColor: const Color(0xFFE65C00),
                      unselectedLabelColor: const Color(0xFF6B7280),
                      labelStyle: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15),
                      unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 15),
                      tabs: const [
                        Tab(text: 'Log In'),
                        Tab(text: 'Sign Up'),
                      ],
                    ),
                    
                    // Tab View Contents
                    SizedBox(
                      height: 420,
                      child: TabBarView(
                        controller: _tabController,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          _buildLoginTab(),
                          _buildSignupTab(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoginTab() {
    return Form(
      key: _loginFormKey,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            // Email
            _buildInputField(
              controller: _loginEmailController,
              labelText: 'Email Address',
              prefixIcon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              validator: (v) => v == null || !v.contains('@') ? 'Enter a valid email' : null,
            ),
            const SizedBox(height: 16),
            // Password
            _buildInputField(
              controller: _loginPasswordController,
              labelText: 'Password',
              prefixIcon: Icons.lock_outline,
              obscureText: _obscureLoginPassword,
              suffixIcon: IconButton(
                icon: Icon(_obscureLoginPassword ? Icons.visibility_off : Icons.visibility, color: const Color(0xFF9CA3AF)),
                onPressed: () => setState(() => _obscureLoginPassword = !_obscureLoginPassword),
              ),
              validator: (v) => v == null || v.length < 6 ? 'Password must be min 6 characters' : null,
            ),
            const SizedBox(height: 8),

            // Forgot Password
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _isLoading ? null : _handleForgotPassword,
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                child: Text(
                  'Forgot Password?',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFFE65C00)),
                ),
              ),
            ),
            const Spacer(),

            // Login Button
            _buildPrimaryButton(
              text: 'Login',
              onPressed: _handleLogin,
            ),
            const SizedBox(height: 16),
            _buildSocialDivider(),
            const SizedBox(height: 16),
            _buildSocialRow(),
          ],
        ),
      ),
    );
  }

  Widget _buildSignupTab() {
    return Form(
      key: _signupFormKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Full Name
            _buildInputField(
              controller: _signupNameController,
              labelText: 'Full Name',
              prefixIcon: Icons.person_outline,
              validator: (v) => v == null || v.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            // Email
            _buildInputField(
              controller: _signupEmailController,
              labelText: 'Email Address',
              prefixIcon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              validator: (v) => v == null || !v.contains('@') ? 'Enter a valid email' : null,
            ),
            const SizedBox(height: 12),
            // Password
            _buildInputField(
              controller: _signupPasswordController,
              labelText: 'Password',
              prefixIcon: Icons.lock_outline,
              obscureText: _obscureSignupPassword,
              suffixIcon: IconButton(
                icon: Icon(_obscureSignupPassword ? Icons.visibility_off : Icons.visibility, color: const Color(0xFF9CA3AF)),
                onPressed: () => setState(() => _obscureSignupPassword = !_obscureSignupPassword),
              ),
              validator: (v) => v == null || v.length < 6 ? 'Password must be min 6 characters' : null,
            ),
            const SizedBox(height: 6),

            // Password Strength Indicator Bar
            if (_signupPasswordController.text.isNotEmpty) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Strength: $_passwordStrength',
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: _passwordStrengthColor),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: _passwordStrengthPercent,
                  backgroundColor: const Color(0xFFE5E7EB),
                  valueColor: AlwaysStoppedAnimation<Color>(_passwordStrengthColor),
                  minHeight: 4,
                ),
              ),
              const SizedBox(height: 10),
            ],

            // Confirm Password
            _buildInputField(
              controller: _signupConfirmPasswordController,
              labelText: 'Confirm Password',
              prefixIcon: Icons.lock_outline,
              obscureText: _obscureSignupConfirmPassword,
              suffixIcon: IconButton(
                icon: Icon(_obscureSignupConfirmPassword ? Icons.visibility_off : Icons.visibility, color: const Color(0xFF9CA3AF)),
                onPressed: () => setState(() => _obscureSignupConfirmPassword = !_obscureSignupConfirmPassword),
              ),
              validator: (v) => v != _signupPasswordController.text ? 'Passwords do not match' : null,
            ),
            const SizedBox(height: 16),

            // Create Account Button
            _buildPrimaryButton(
              text: 'Create Account',
              onPressed: _handleSignup,
            ),
            const SizedBox(height: 12),
            _buildSocialDivider(),
            const SizedBox(height: 12),
            _buildSocialRow(),
            const SizedBox(height: 16),
            Center(
              child: TextButton.icon(
                onPressed: () {
                  _tabController.animateTo(0);
                },
                icon: const Icon(Icons.arrow_back, color: Color(0xFF6B7280), size: 16),
                label: Text(
                  'Back to Login',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF6B7280),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String labelText,
    required IconData prefixIcon,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: GoogleFonts.inter(fontSize: 15, color: const Color(0xFF1A1A2E)),
      decoration: InputDecoration(
        labelText: labelText,
        labelStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF9CA3AF)),
        prefixIcon: Icon(prefixIcon, color: const Color(0xFF9CA3AF), size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB), width: 1.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE65C00), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.0),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
        ),
        errorStyle: GoogleFonts.inter(fontSize: 11, color: const Color(0xFFEF4444)),
      ),
      validator: validator,
    );
  }

  Widget _buildPrimaryButton({required String text, required VoidCallback onPressed}) {
    return ElevatedButton(
      onPressed: _isLoading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFE65C00),
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFFD1D5DB),
        disabledForegroundColor: const Color(0xFF9CA3AF),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
      child: _isLoading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
            )
          : Text(
              text,
              style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold),
            ),
    );
  }

  Widget _buildSocialDivider() {
    return Row(
      children: [
        const Expanded(child: Divider(color: Color(0xFFE5E7EB))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0),
          child: Text('or', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF9CA3AF))),
        ),
        const Expanded(child: Divider(color: Color(0xFFE5E7EB))),
      ],
    );
  }

  Widget _buildSocialRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildSocialCircleButton('Google', () => _handleOAuth('Google')),
        const SizedBox(width: 20),
        _buildSocialCircleButton('Apple', () => _handleOAuth('Apple')),
      ],
    );
  }

  Widget _buildSocialCircleButton(String provider, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2)),
          ],
          border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
        ),
        child: Center(
          child: provider == 'Google'
              ? const Icon(Icons.g_mobiledata, size: 40, color: Colors.blue)
              : const Icon(Icons.apple, size: 28, color: Colors.black),
        ),
      ),
    );
  }
}
