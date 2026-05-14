import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/profile_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/profile_picker_screen.dart';
import 'services/model_service.dart';
import 'services/notification_service.dart';
import 'services/profile_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();
  runApp(const ProviderScope(child: NunarivuApp()));
}

class NunarivuApp extends ConsumerWidget {
  const NunarivuApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'Nunarivu AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      home: const _AppRouter(),
    );
  }
}

/// Decides the initial screen:
///   no profiles  → OnboardingScreen
///   ≥1 profiles  → ProfilePickerScreen
///   active set   → HomeScreen (after picker selection)
class _AppRouter extends ConsumerStatefulWidget {
  const _AppRouter();

  @override
  ConsumerState<_AppRouter> createState() => _AppRouterState();
}

class _AppRouterState extends ConsumerState<_AppRouter> {
  Future<bool>? _hasProfilesFuture;

  @override
  void initState() {
    super.initState();
    _hasProfilesFuture = _checkProfiles();
    // Kick off model auto-load in parallel with the profile check.
    Future.microtask(
        () => ref.read(modelServiceProvider.notifier).tryAutoLoad());
  }

  Future<bool> _checkProfiles() async {
    final n = await ref.read(profileServiceProvider).count();
    return n > 0;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _hasProfilesFuture,
      builder: (ctx, snap) {
        if (!snap.hasData) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        final hasProfiles = snap.data!;
        final activeProfile = ref.watch(currentProfileProvider);

        if (!hasProfiles) return const OnboardingScreen();
        if (activeProfile == null) return const ProfilePickerScreen();
        return const HomeScreen();
      },
    );
  }
}
