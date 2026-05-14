import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ID of the currently active chat session.
/// null = new blank chat (session will be auto-created on first message).
final currentChatIdProvider = StateProvider<String?>((ref) => null);
