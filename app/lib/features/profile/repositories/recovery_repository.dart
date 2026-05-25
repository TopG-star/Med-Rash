import '../../../core/infra/auth_state_manager.dart';
import '../../../core/infra/medrash_http_client.dart';
import '../models/user_profile.dart';

/// Base class for every error surfaced by the recovery flow. The UI does an
/// `is` check on each subclass to pick the right inline copy.
abstract class RecoveryException implements Exception {
  const RecoveryException(this.message);
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Returned when no `app.users` row carries the supplied recovery email.
class ProfileNotFoundException extends RecoveryException {
  const ProfileNotFoundException(super.message);
}

/// Returned when Supabase Auth rejects the OTP (wrong code, expired, or
/// already consumed). The UI shows a single message and a resend affordance.
class OtpInvalidException extends RecoveryException {
  const OtpInvalidException(super.message);
}

/// Returned when the same email is held by two Supabase Auth identities
/// racing for the same domain profile. Practically impossible, but worth a
/// distinct code so support can spot it in logs.
class RecoveryConflictException extends RecoveryException {
  const RecoveryConflictException(super.message);
}

/// Returned when Supabase Auth is throttling OTP requests.
class RecoveryRateLimitedException extends RecoveryException {
  const RecoveryRateLimitedException(super.message);
}

/// Returned when the server reaches but can't deliver the OTP email (SMTP
/// outage, bad config). Distinct from rate-limit so the UI can suggest
/// "try again in a moment" rather than "wait".
class OtpDeliveryFailedException extends RecoveryException {
  const OtpDeliveryFailedException(super.message);
}

/// Returned for network / parse / unknown failures so the UI always has a
/// concrete exception type to pattern-match against.
class RecoveryNetworkException extends RecoveryException {
  const RecoveryNetworkException(super.message);
}

/// Payload returned by [RecoveryRepository.verifyOtp] on success. The caller
/// is responsible for installing this identity via [AuthStateManager
/// .adoptRecoveredIdentity] and persisting the profile.
class RecoveredIdentity {
  const RecoveredIdentity({
    required this.participantId,
    required this.deviceInstallId,
    required this.profile,
  });

  final String participantId;
  final String deviceInstallId;
  final UserProfile profile;
}

abstract class RecoveryRepository {
  /// Asks the server to send a one-time code to [email]. Throws a subclass of
  /// [RecoveryException] on failure. Returns normally on a 200 OK.
  Future<void> requestOtp({required String email});

  /// Verifies the [otp] for [email]. On success returns the recovered
  /// identity payload; on failure throws a [RecoveryException] subclass.
  Future<RecoveredIdentity> verifyOtp({
    required String email,
    required String otp,
  });
}

class NetlifyRecoveryRepository implements RecoveryRepository {
  NetlifyRecoveryRepository({
    required MedRashHttpClient httpClient,
    required AuthStateManager authStateManager,
  })  : _httpClient = httpClient,
        _authStateManager = authStateManager;

  final MedRashHttpClient _httpClient;
  final AuthStateManager _authStateManager;

  @override
  Future<void> requestOtp({required String email}) async {
    final String normalized = email.trim().toLowerCase();
    if (normalized.isEmpty) {
      throw const RecoveryNetworkException('Enter your email first.');
    }

    try {
      await _httpClient.postJson(
        'recover-request',
        <String, Object?>{'email': normalized},
      );
    } on MedRashGateException catch (error) {
      throw _mapGateException(error);
    } catch (error) {
      throw RecoveryNetworkException(_safeMessage(error));
    }
  }

  @override
  Future<RecoveredIdentity> verifyOtp({
    required String email,
    required String otp,
  }) async {
    final String normalizedEmail = email.trim().toLowerCase();
    final String normalizedOtp = otp.trim();
    final String? deviceInstallId = _authStateManager.deviceId;
    final String? currentParticipantId = _authStateManager.participantId;

    if (normalizedEmail.isEmpty || normalizedOtp.isEmpty) {
      throw const RecoveryNetworkException('Enter your email and the 6-digit code.');
    }
    if (deviceInstallId == null || deviceInstallId.isEmpty) {
      throw const RecoveryNetworkException(
        'This device is missing an install id. Restart the app and try again.',
      );
    }

    Map<String, dynamic> response;
    try {
      response = await _httpClient.postJson(
        'recover-verify',
        <String, Object?>{
          'email': normalizedEmail,
          'otp': normalizedOtp,
          'deviceInstallId': deviceInstallId,
          if (currentParticipantId != null && currentParticipantId.isNotEmpty)
            'currentParticipantId': currentParticipantId,
        },
      );
    } on MedRashGateException catch (error) {
      throw _mapGateException(error);
    } catch (error) {
      throw RecoveryNetworkException(_safeMessage(error));
    }

    final String? participantId = response['participantId']?.toString();
    final String? returnedDevice = response['deviceInstallId']?.toString();
    final Map<String, dynamic>? profileJson =
        response['profile'] is Map<String, dynamic> ? response['profile'] as Map<String, dynamic> : null;

    if (participantId == null || participantId.isEmpty || profileJson == null) {
      throw const RecoveryNetworkException(
        'Recovery succeeded but the server returned an incomplete payload. Try again.',
      );
    }

    final UserProfile profile = UserProfile(
      fullName: profileJson['fullName']?.toString() ?? '',
      nickname: profileJson['nickname']?.toString() ?? '',
      facility: profileJson['facility']?.toString() ?? '',
      specialty: profileJson['specialty']?.toString() ?? 'Doctor',
      totalPoints: 0,
      rank: 0,
      email: profileJson['email']?.toString(),
    );

    return RecoveredIdentity(
      participantId: participantId,
      deviceInstallId: (returnedDevice == null || returnedDevice.isEmpty)
          ? deviceInstallId
          : returnedDevice,
      profile: profile,
    );
  }

  RecoveryException _mapGateException(MedRashGateException error) {
    final String code = error.code;
    final String message = error.body['message']?.toString() ?? 'Recovery failed.';
    switch (code) {
      case 'PROFILE_NOT_FOUND':
        return ProfileNotFoundException(message);
      case 'OTP_INVALID':
        return OtpInvalidException(message);
      case 'RECOVERY_CONFLICT':
        return RecoveryConflictException(message);
      case 'RATE_LIMITED':
        return RecoveryRateLimitedException(message);
      case 'OTP_SEND_FAILED':
        return OtpDeliveryFailedException(message);
      default:
        return RecoveryNetworkException(message);
    }
  }

  String _safeMessage(Object error) {
    final String text = error.toString();
    return text.isEmpty ? 'Network error. Check your connection and try again.' : text;
  }
}
