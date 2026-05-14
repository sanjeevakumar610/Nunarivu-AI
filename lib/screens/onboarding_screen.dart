import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'create_profile_screen.dart';

/// First-launch welcome screen — introduces the app then opens the
/// full profile creation form.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(Icons.school_rounded, size: 96, color: cs.primary)
                  .animate()
                  .fadeIn(duration: 600.ms)
                  .scale(begin: const Offset(0.8, 0.8)),
              const SizedBox(height: 28),
              Text(
                'வணக்கம்!',
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansTamil(
                  fontSize: 44,
                  fontWeight: FontWeight.bold,
                  color: cs.primary,
                ),
              ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.2),
              const SizedBox(height: 6),
              Text(
                'Nunarivu AI · Offline Tutor',
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansTamil(
                    fontSize: 16, color: cs.onSurfaceVariant),
              ).animate().fadeIn(delay: 350.ms),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    _FeatureRow(
                      icon: Icons.chat_bubble_outline,
                      tamil: 'தமிழ் மற்றும் ஆங்கிலத்தில் கேளுங்கள்',
                      english: 'Chat in Tamil or English',
                    ),
                    const Divider(height: 16),
                    _FeatureRow(
                      icon: Icons.camera_alt_outlined,
                      tamil: 'புத்தகப் படம் எடுத்து கேளுங்கள்',
                      english: 'Snap a photo of your textbook',
                    ),
                    const Divider(height: 16),
                    _FeatureRow(
                      icon: Icons.wifi_off,
                      tamil: 'இணைய இணைப்பு தேவையில்லை',
                      english: '100% offline — no internet needed',
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 500.ms).slideY(begin: 0.1),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) =>
                        const CreateProfileScreen(navigateHome: true),
                  ),
                ),
                icon: const Icon(Icons.arrow_forward_rounded),
                label: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('தொடங்கு',
                        style: GoogleFonts.notoSansTamil(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                    Text('Get started',
                        style: GoogleFonts.notoSansTamil(fontSize: 11)),
                  ],
                ),
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14)),
              ).animate().fadeIn(delay: 700.ms),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String tamil;
  final String english;
  const _FeatureRow(
      {required this.icon, required this.tamil, required this.english});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, color: cs.primary, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tamil,
                  style: GoogleFonts.notoSansTamil(
                      fontSize: 13, fontWeight: FontWeight.w500)),
              Text(english,
                  style: GoogleFonts.notoSansTamil(
                      fontSize: 11, color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }
}
