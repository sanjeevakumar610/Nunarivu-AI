import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/profile.dart';
import '../services/profile_service.dart';
import 'chat_session_provider.dart';

/// SharedPreferences key prefix for per-profile last chat ID.
const _kLastChatId = 'lastChatId_';

/// Currently active profile, or null if none selected yet.
class CurrentProfileNotifier extends Notifier<Profile?> {
  @override
  Profile? build() => null;

  /// Switch to profile [p].
  ///
  /// - If switching to a **different** profile: saves the current chatId for
  ///   the outgoing profile, then starts a fresh blank chat for the new profile.
  /// - If updating the **same** profile (grade change, settings save): just
  ///   updates the profile state — does NOT touch chatId so the active chat stays open.
  Future<void> setActive(Profile p) async {
    await ref.read(profileServiceProvider).touch(p);

    final currentProfile = state;
    final isNewProfile = currentProfile == null || currentProfile.id != p.id;

    if (isNewProfile) {
      final prefs = await SharedPreferences.getInstance();

      // 1. Save the outgoing profile's current chatId.
      if (currentProfile != null) {
        final outgoingChatId = ref.read(currentChatIdProvider);
        if (outgoingChatId != null) {
          await prefs.setString('$_kLastChatId${currentProfile.id}', outgoingChatId);
        } else {
          await prefs.remove('$_kLastChatId${currentProfile.id}');
        }
      }

      // 2. Activate new profile first so _messagesProvider sees the right profile.
      state = p;

      // 3. Always start with a fresh blank chat on profile switch.
      ref.read(currentChatIdProvider.notifier).state = null;
    } else {
      // Same profile — just refresh state (settings/grade update).
      // chatId intentionally left unchanged so the active chat stays open.
      state = p;
    }
  }

  /// Log out — clears profile and saves the current chatId so it can be
  /// restored the next time this profile logs in.
  Future<void> clear() async {
    final currentProfile = state;
    if (currentProfile != null) {
      final prefs = await SharedPreferences.getInstance();
      final outgoingChatId = ref.read(currentChatIdProvider);
      if (outgoingChatId != null) {
        await prefs.setString('$_kLastChatId${currentProfile.id}', outgoingChatId);
      } else {
        await prefs.remove('$_kLastChatId${currentProfile.id}');
      }
    }
    // Reset chatId — setActive will restore the right one for the next profile.
    ref.read(currentChatIdProvider.notifier).state = null;
    state = null;
  }
}

final currentProfileProvider =
    NotifierProvider<CurrentProfileNotifier, Profile?>(
        CurrentProfileNotifier.new);

/// Async list of all profiles in DB. Refresh by invalidating.
final allProfilesProvider = FutureProvider<List<Profile>>((ref) {
  return ref.read(profileServiceProvider).all();
});
