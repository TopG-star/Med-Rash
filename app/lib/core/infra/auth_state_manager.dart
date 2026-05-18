import 'package:flutter/foundation.dart';

import 'device_identity_service.dart';
import 'identity_spine.dart';

class AuthStateManager extends ChangeNotifier {
  AuthStateManager({required DeviceIdentityService deviceIdentityService})
      : _deviceIdentityService = deviceIdentityService;

  final DeviceIdentityService _deviceIdentityService;

  bool _initialized = false;
  bool _hasProfile = false;
  String? _participantId;
  String? _deviceId;

  bool get initialized => _initialized;
  bool get hasProfile => _hasProfile;
  String? get participantId => _participantId;
  String? get deviceId => _deviceId;
  IdentitySpine? get identitySpine {
    final String? deviceId = _deviceId;
    final String? participantId = _participantId;
    if (deviceId == null || participantId == null) {
      return null;
    }
    return IdentitySpine(
      deviceInstallId: deviceId,
      participantId: participantId,
      hasBoundProfile: _hasProfile,
    );
  }

  Future<void> initialize() async {
    final IdentitySpine identitySpine = await _deviceIdentityService.getIdentitySpine();
    _deviceId = identitySpine.deviceInstallId;
    _participantId = identitySpine.participantId;
    _hasProfile = identitySpine.hasBoundProfile;
    _initialized = true;
    notifyListeners();
  }

  Future<void> markJoined() async {
    _hasProfile = true;
    await _deviceIdentityService.setBoundProfile(true);
    notifyListeners();
  }
}