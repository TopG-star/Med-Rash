import '../../../core/events/medrash_events.dart';

/// Emitted by [SessionJoinPage] right after it has successfully resolved a
/// session and written the join code to [LastSessionStore]. The Mode
/// Selection home subscribes so its "Continue last session" card refreshes
/// without polling.
class LastSessionRecordedEvent extends MedRashEvent {
  const LastSessionRecordedEvent({required this.joinCode});

  final String joinCode;
}
