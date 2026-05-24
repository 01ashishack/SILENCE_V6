import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'role_selection_screen.dart';
import 'splash_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _loginFormKey = GlobalKey<FormState>();
  final _signupFormKey = GlobalKey<FormState>();

  // Login controllers
  final _loginEmailController = TextEditingController();
  final _loginPasswordController = TextEditingController();

  // Signup controllers
  final _signupNameController = TextEditingController();
  final _signupEmailController = TextEditingController();
  final _signupPasswordController = TextEditingController();
  final _signupConfirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _obscureLoginPassword = true;
  bool _obscureSignupPassword = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w500),
        ),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w500),
        ),
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
        if (!mounted) return;
        _showSuccessSnackBar('Welcome back!');
        
        // Use splash screen routing logic to figure out role and redirect
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const SplashScreen()),
        );
      }
    } on AuthException catch (e) {
      _showErrorSnackBar(e.message);
    } catch (e) {
      _showErrorSnackBar('An unexpected error occurred: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSignup() async {
    if (!_signupFormKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;
      
      // Perform standard sign up (no email verification as per constraint)
      final response = await supabase.auth.signUp(
        email: _signupEmailController.text.trim(),
        password: _signupPasswordController.text,
      );

      if (response.user != null) {
        // Create user record in 'users' table
        await supabase.from('users').insert({
          'id': response.user!.id,
          'email': _signupEmailController.text.trim(),
          'full_name': _signupNameController.text.trim(),
          'role': 'member', // Default to member until explicitly selected/saved
        });

        if (!mounted) return;
        _showSuccessSnackBar('Account created successfully!');
        
        // Navigate to Role Selection Screen
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const RoleSelectionScreen()),
        );
      }
    } on AuthException catch (e) {
      _showErrorSnackBar(e.message);
    } catch (e) {
      _showErrorSnackBar('An unexpected error occurred: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              // App Logo branding
              Center(
                child: Image.asset(
                  'assets/images/LOGO.png',
                  width: 90,
                  height: 90,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        color: Color(0xFFE65C00),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.library_books,
                        size: 40,
                        color: Colors.white,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'SILENCE',
                  style: GoogleFonts.outfit(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFFE65C00),
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              Center(
                child: Text(
                  'Library Management & QR Attendance',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.grey[600],
                  ),
                ),
              ),
              const SizedBox(height: 36),

              // Login / Signup Tab Bar
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    color: const Color(0xFFE65C00),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.grey[700],
                  labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
                  unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 14),
                  tabs: const [
                    Tab(text: 'Login'),
                    Tab(text: 'Sign Up'),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Tab Views containing Forms
              SizedBox(
                height: 360,
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildLoginForm(),
                    _buildSignupForm(),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              
              // Divider
              Row(
                children: [
                  Expanded(child: Divider(color: Colors.grey[300])),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text(
                      'OR',
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[500], fontWeight: FontWeight.bold),
                    ),
                  ),
                  Expanded(child: Divider(color: Colors.grey[300])),
                ],
              ),
              const SizedBox(height: 20),

              // Social OAuth Buttons
              Row(
                children: [
                  Expanded(
                    child: _buildSocialButton(
                      icon: Icons.g_mobiledata_outlined,
                      label: 'Google',
                      onPressed: () {
                        _showErrorSnackBar('Google login coming soon in V1.1!');
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildSocialButton(
                      icon: Icons.apple,
                      label: 'Apple',
                      onPressed: () {
                        _showErrorSnackBar('Apple login coming soon in V1.1!');
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm() {
    return Form(
      key: _loginFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _loginEmailController,
            keyboardType: TextInputType.emailAddress,
            style: GoogleFonts.inter(fontSize: 14),
            decoration: _buildInputDecoration('Email Address', Icons.email_outlined),
            validator: (value) {
              if (value == null || value.isEmpty) return 'Email is required';
              if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) return 'Enter a valid email address';
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _loginPasswordController,
            obscureText: _obscureLoginPassword,
            style: GoogleFonts.inter(fontSize: 14),
            decoration: _buildInputDecoration(
              'Password',
              Icons.lock_outlined,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureLoginPassword ? Icons.visibility_off : Icons.visibility,
                  color: Colors.grey[500],
                  size: 20,
                ),
                onPressed: () => setState(() => _obscureLoginPassword = !_obscureLoginPassword),
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) return 'Password is required';
              return null;
            },
          ),
          const SizedBox(height: 28),
          ElevatedButton(
            onPressed: _isLoading ? null : _handleLogin,
            style: _buildButtonStyle(),
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                  )
                : Text('Log In', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildSignupForm() {
    return Form(
      key: _signupFormKey,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _signupNameController,
              keyboardType: TextInputType.name,
              style: GoogleFonts.inter(fontSize: 14),
              decoration: _buildInputDecoration('Full Name', Icons.person_outline),
              validator: (value) {
                if (value == null || value.isEmpty) return 'Full name is required';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _signupEmailController,
              keyboardType: TextInputType.emailAddress,
              style: GoogleFonts.inter(fontSize: 14),
              decoration: _buildInputDecoration('Email Address', Icons.email_outlined),
              validator: (value) {
                if (value == null || value.isEmpty) return 'Email is required';
                if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) return 'Enter a valid email address';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _signupPasswordController,
              obscureText: _obscureSignupPassword,
              style: GoogleFonts.inter(fontSize: 14),
              decoration: _buildInputDecoration(
                'Password',
                Icons.lock_outlined,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureSignupPassword ? Icons.visibility_off : Icons.visibility,
                    color: Colors.grey[500],
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscureSignupPassword = !_obscureSignupPassword),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) return 'Password is required';
                if (value.length < 6) return 'Password must be at least 6 characters';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _signupConfirmPasswordController,
              obscureText: true,
              style: GoogleFonts.inter(fontSize: 14),
              decoration: _buildInputDecoration('Confirm Password', Icons.lock_outline),
              validator: (value) {
                if (value == null || value.isEmpty) return 'Please confirm your password';
                if (value != _signupPasswordController.text) return 'Passwords do not match';
                return null;
              },
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _handleSignup,
              style: _buildButtonStyle(),
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                    )
                  : Text('Sign Up', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration(String label, IconData prefixIcon, {Widget? suffixIcon}) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.inter(color: Colors.grey[600], fontSize: 13),
      prefixIcon: Icon(prefixIcon, color: const Color(0xFFE65C00), size: 20),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 16.0),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey[300]!, width: 1.0),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE65C00), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.0),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
      ),
    );
  }

  ButtonStyle _buildButtonStyle() {
    return ElevatedButton.styleFrom(
      foregroundColor: Colors.white,
      backgroundColor: const Color(0xFFE65C00),
      padding: const EdgeInsets.symmetric(vertical: 14.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      elevation: 1,
    );
  }

  Widget _buildSocialButton({required IconData icon, required String label, required VoidCallback onPressed}) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: Colors.grey[300]!),
        padding: const EdgeInsets.symmetric(vertical: 12.0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.grey[700], size: 22),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.inter(color: Colors.grey[700], fontWeight: FontWeight.w600, fontSize: 14),
          ),
        ],
      ),
    );
  }
}


