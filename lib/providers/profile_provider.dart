import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/profile.dart';
import '../services/profile_service.dart';
import 'chat_session_provider.dart';

/// Currently active profile, or null if none selected yet.
class CurrentProfileNotifier extends Notifier<Profile?> {
  @override
  Profile? build() => null;

  Future<void> setActive(Profile p) async {
    await ref.read(profileServiceProvider).touch(p);
    // Reset chat session so the new profile starts with a blank chat,
    // not the previous profile's last chat.
    ref.read(currentChatIdProvider.notifier).state = null;
    state = p;
  }

  void clear() => state = null;
}

final currentProfileProvider =
    NotifierProvider<CurrentProfileNotifier, Profile?>(
        CurrentProfileNotifier.new);

/// Async list of all profiles in DB. Refresh by invalidating.
final allProfilesProvider = FutureProvider<List<Profile>>((ref) {
  return ref.read(profileServiceProvider).all();
});
