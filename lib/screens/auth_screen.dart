import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/gestures.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../core/supabase_config.dart';


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
  static bool _googleInitialized = false;
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
      if (!mounted) return;

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

  bool _isAlreadyRegisteredError(Object e) {
    final msg = (e is AuthException ? e.message : e.toString()).toLowerCase();
    return msg.contains('already') || msg.contains('registered') || msg.contains('exists');
  }

  Future<void> _handleSignup() async {
    if (!_signupFormKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final supabase = Supabase.instance.client;
    final email = _signupEmailController.text.trim();
    final password = _signupPasswordController.text;
    final name = _signupNameController.text.trim();

    try {
      AuthResponse response;
      try {
        response = await supabase.auth.signUp(
          email: email,
          password: password,
          data: {'full_name': name},
        );
      } on AuthException catch (e) {
        // The email already exists in auth — almost always a previous half-
        // finished attempt (e.g. the profile write failed last time). Instead of
        // dead-ending on "already registered", seamlessly sign in with the SAME
        // credentials the user just typed and continue the flow.
        if (_isAlreadyRegisteredError(e)) {
          try {
            response = await supabase.auth.signInWithPassword(email: email, password: password);
          } on AuthException catch (signInErr) {
            if (!mounted) return;
            final m = signInErr.message.toLowerCase();
            if (m.contains('not confirmed') || m.contains('confirm')) {
              _showErrorSnackBar('Please confirm your email, then login.');
            } else {
              _showErrorSnackBar('This email is already registered. Please login.');
            }
            _tabController.animateTo(0); // switch to Login tab
            return;
          }
        } else {
          rethrow;
        }
      }

      // Supabase returns an obfuscated user with empty identities when the email
      // already exists and confirmations are on.
      final user = response.user;
      if (user != null && (user.identities?.isEmpty ?? false) && response.session == null) {
        if (!mounted) return;
        _showErrorSnackBar('Email already registered. Please login.');
        _tabController.animateTo(0);
        return;
      }

      if (user == null) {
        if (!mounted) return;
        _showErrorSnackBar('Signup failed. Please try again.');
        return;
      }

      // No session = email confirmation is required. We have NO valid JWT yet, so
      // we must NOT write the profile row (that's what caused the JWT error). Tell
      // the user to confirm + login; the profile is created on first login below
      // is not needed — login flow + role-select handle a missing row.
      if (response.session == null) {
        if (!mounted) return;
        _showSuccessSnackBar('Confirm your email, then login to continue.');
        _tabController.animateTo(0);
        return;
      }

      // Session is active → valid JWT → safe to create/repair the profile row.
      // This write is the real "signup success" marker.
      await supabase.from('users').upsert({
        'id': user.id,
        'email': user.email ?? email,
        'full_name': name,
        'nickname': name.split(' ').first,
        'role': null,
      });

      if (!mounted) return;
      _showSuccessSnackBar('Account created successfully!');
      Navigator.of(context).pushReplacementNamed('/role-select');
    } on PostgrestException catch (e) {
      if (!mounted) return;
      _showErrorSnackBar('Signup failed: ${e.message}');
    } on AuthException catch (e) {
      if (!mounted) return;
      _showErrorSnackBar(e.message);
    } catch (e) {
      if (!mounted) return;
      _showErrorSnackBar('Signup failed. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleOAuth(String provider) async {
    if (provider == 'Google') {
      await _handleGoogleSignIn();
      return;
    }
    // Apple Sign-In needs a paid Apple Developer account + a Mac to build/test.
    // Tracked as remaining task R1/R2 — kept honest instead of faking it.
    _showErrorSnackBar('Apple sign-in is coming soon.');
  }

  /// Native Google sign-in (google_sign_in v7) → Supabase `signInWithIdToken`.
  /// On web there is no native dialog, so we fall back to the redirect-based
  /// `signInWithOAuth` flow. After a successful sign-in we bootstrap the
  /// `users` row (first social login) and route exactly like email login.
  Future<void> _handleGoogleSignIn() async {
    final supabase = Supabase.instance.client;

    // Web / desktop: redirect-based OAuth (no native Credential Manager).
    if (kIsWeb) {
      try {
        await supabase.auth.signInWithOAuth(OAuthProvider.google);
        // Session resumes via redirect; AuthGate/splash handles routing.
      } catch (e) {
        _showErrorSnackBar('Could not start Google sign-in. Please try again.');
      }
      return;
    }

    if (SupabaseConfig.googleWebClientId.isEmpty) {
      _showErrorSnackBar(
          'Google sign-in is not configured yet. Add the Web client ID first.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final googleSignIn = GoogleSignIn.instance;
      if (!_googleInitialized) {
        await googleSignIn.initialize(
          serverClientId: SupabaseConfig.googleWebClientId,
          clientId: SupabaseConfig.googleIosClientId.isEmpty
              ? null
              : SupabaseConfig.googleIosClientId,
        );
        _googleInitialized = true;
      }

      // Opens the native account chooser (throws GoogleSignInException on cancel).
      final googleUser = await googleSignIn.authenticate();

      final idToken = googleUser.authentication.idToken;
      if (idToken == null) {
        throw const AuthException('No ID token returned by Google.');
      }

      // Authorize the scopes we need to also obtain an access token.
      const scopes = ['email', 'profile'];
      final authorization =
          await googleUser.authorizationClient.authorizationForScopes(scopes) ??
              await googleUser.authorizationClient.authorizeScopes(scopes);

      final response = await supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: authorization.accessToken,
      );

      final user = response.user;
      if (user == null) {
        throw const AuthException('Google sign-in failed. Please try again.');
      }

      final metaName = (user.userMetadata?['full_name'] ??
              user.userMetadata?['name'] ??
              googleUser.displayName)
          ?.toString();
      await _routeAfterAuth(user, fallbackName: metaName);
    } on GoogleSignInException catch (e) {
      // User dismissed the chooser — not an error, stay silent.
      if (e.code != GoogleSignInExceptionCode.canceled) {
        _showErrorSnackBar('Google sign-in failed. Please try again.');
      }
    } on AuthException catch (e) {
      _showErrorSnackBar(e.message);
    } catch (e) {
      _showErrorSnackBar('Google sign-in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Ensures a `users` row exists (bootstraps it on first social login) and
  /// then routes: role null → role-select, admin → admin home, else member home.
  Future<void> _routeAfterAuth(User user, {String? fallbackName}) async {
    final supabase = Supabase.instance.client;
    var userData =
        await supabase.from('users').select().eq('id', user.id).maybeSingle();

    if (userData == null) {
      final name =
          (fallbackName ?? user.email?.split('@').first ?? 'User').toString().trim();
      await supabase.from('users').upsert({
        'id': user.id,
        'email': user.email ?? '',
        'full_name': name.isEmpty ? 'User' : name,
        'nickname': name.isEmpty ? 'User' : name.split(' ').first,
        'role': null,
      });
      userData =
          await supabase.from('users').select().eq('id', user.id).maybeSingle();
    }

    if (!mounted) return;
    _showSuccessSnackBar('Signed in with Google.');
    if (userData == null || userData['role'] == null) {
      Navigator.of(context).pushReplacementNamed('/role-select');
    } else if (userData['role'] == 'admin') {
      Navigator.of(context).pushReplacementNamed('/admin/home');
    } else {
      Navigator.of(context).pushReplacementNamed('/member/home');
    }
  }

  void _handleForgotPassword() {
    final emailController = TextEditingController(text: _loginEmailController.text.trim());
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        bool isResetting = false;
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                top: 24,
                left: 24,
                right: 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Reset Password',
                    style: GoogleFonts.outfit(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter your registered email address to receive a password reset link.',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: const Color(0xFF6B7280),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    style: GoogleFonts.inter(fontSize: 15, color: const Color(0xFF1A1A2E)),
                    decoration: InputDecoration(
                      labelText: 'Email Address',
                      prefixIcon: const Icon(Icons.email_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: isResetting
                        ? null
                        : () async {
                            final email = emailController.text.trim();
                            if (email.isEmpty || !email.contains('@')) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Please enter a valid email address.')),
                              );
                              return;
                            }
                            setModalState(() => isResetting = true);
                            try {
                              await Supabase.instance.client.auth.resetPasswordForEmail(email);
                              if (context.mounted) {
                                Navigator.pop(context);
                                _showSuccessSnackBar('Password reset link sent to your email.');
                              }
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error: $e')),
                              );
                            } finally {
                              setModalState(() => isResetting = false);
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE65C00),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: isResetting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            'Send Reset Link',
                            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
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
                    'assets/images/transparent_logo_with_black_name.png',
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
                    BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, 4)),
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
              _buildSocialDivider(),
              const SizedBox(height: 16),
              _buildSocialRow(),
              const SizedBox(height: 24),
              Center(
                child: RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF6B7280), height: 1.5),
                    children: [
                      const TextSpan(text: 'By creating an account, you agree to our\n'),
                      TextSpan(
                        text: 'Terms',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFFE65C00),
                          decoration: TextDecoration.underline,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () {
                            Navigator.pushNamed(context, '/member/terms');
                          },
                      ),
                      const TextSpan(text: ' & '),
                      TextSpan(
                        text: 'Privacy Policy',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFFE65C00),
                          decoration: TextDecoration.underline,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () {
                            Navigator.pushNamed(context, '/member/privacy-policy');
                          },
                      ),
                      const TextSpan(text: '.'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
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
            BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
          ],
          border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
        ),
        child: Center(
          child: FaIcon(
            provider == 'Google' ? FontAwesomeIcons.google : FontAwesomeIcons.apple,
            size: 24,
            color: provider == 'Google' ? const Color(0xFFDB4437) : Colors.black,
          ),
        ),
      ),
    );
  }
}
