import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/profile.dart';
import '../providers/profile_provider.dart';
import '../services/profile_service.dart';
import '../widgets/profile_avatar.dart';
import 'create_profile_screen.dart';
import 'home_screen.dart';

/// Shown on app launch when ≥1 profile exists.
class ProfilePickerScreen extends ConsumerWidget {
  const ProfilePickerScreen({super.key});

  Future<void> _select(BuildContext ctx, WidgetRef ref, Profile p) async {
    await ref.read(currentProfileProvider.notifier).setActive(p);
    if (!ctx.mounted) return;
    Navigator.of(ctx).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  Future<void> _addProfile(BuildContext ctx, WidgetRef ref) async {
    await Navigator.of(ctx).push(
      MaterialPageRoute(
        builder: (_) => const CreateProfileScreen(navigateHome: false),
      ),
    );
    if (!ctx.mounted) return;
    final profile = ref.read(currentProfileProvider);
    if (profile != null) {
      Navigator.of(ctx).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profilesAsync = ref.watch(allProfilesProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              Text(
                'யார் இது?',
                style: GoogleFonts.notoSansTamil(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: cs.primary,
                ),
              ),
              Text(
                'Who\'s using the app?',
                style: GoogleFonts.notoSansTamil(
                    fontSize: 14, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 28),
              Expanded(
                child: profilesAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Error: $e')),
                  data: (profiles) => GridView.count(
                    crossAxisCount: 2,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    children: [
                      for (var i = 0; i < profiles.length; i++)
                        _ProfileTile(
                          profile: profiles[i],
                          onTap: () => _select(context, ref, profiles[i]),
                        )
                            .animate()
                            .fadeIn(delay: (i * 60).ms)
                            .slideY(begin: 0.1, curve: Curves.easeOut),
                      _AddTile(
                        onTap: () => _addProfile(context, ref),
                      ).animate().fadeIn(delay: (profiles.length * 60).ms),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  final Profile profile;
  final VoidCallback onTap;
  const _ProfileTile({required this.profile, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Hero(
                tag: 'avatar-${profile.id}',
                child: ProfileAvatar(
                    name: profile.name, seed: profile.avatarSeed, size: 72),
              ),
              const SizedBox(height: 10),
              Text(
                profile.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.notoSansTamil(
                    fontSize: 15, fontWeight: FontWeight.w600),
              ),
              if (profile.grade != null && profile.grade!.isNotEmpty)
                Text(
                  profile.grade!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.notoSansTamil(
                      fontSize: 11, color: cs.onSurfaceVariant),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  final VoidCallback onTap;
  const _AddTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.primaryContainer,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.person_add_alt_1,
                  size: 40, color: cs.onPrimaryContainer),
              const SizedBox(height: 8),
              Text('புதிய சுயவிவரம்',
                  style: GoogleFonts.notoSansTamil(
                      color: cs.onPrimaryContainer,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              Text('Add profile',
                  style: GoogleFonts.notoSansTamil(
                      color: cs.onPrimaryContainer.withOpacity(0.7),
                      fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}
