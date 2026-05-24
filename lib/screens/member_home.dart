import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

class MemberHomeScreen extends StatelessWidget {
  const MemberHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFE65C00),
        title: Text('SILENCE Member Home', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white)),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
              if (context.mounted) {
                Navigator.of(context).pushReplacementNamed('/login');
              }
            },
          )
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFE65C00).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.school, size: 60, color: Color(0xFFE65C00)),
              ),
              const SizedBox(height: 24),
              Text(
                'Welcome, Student!',
                style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
              ),
              const SizedBox(height: 12),
              Text(
                'You have successfully signed up and logged in as a student.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[600]),
              ),
              const SizedBox(height: 24),
              if (user != null)
                Text(
                  'Email: ${user.email}',
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: const Color(0xFF1E293B)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
