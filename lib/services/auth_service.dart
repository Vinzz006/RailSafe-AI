import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../core/errors/app_error.dart';
import '../models/user_profile.dart';
import 'local_storage_service.dart';

class AuthService {
  final LocalStorageService _storage;
  bool _isFirebaseInitialized = false;
  FirebaseAuth? _auth;
  UserProfile? _currentUser;
  final StreamController<UserProfile?> _userStreamController =
      StreamController<UserProfile?>.broadcast();

  AuthService(this._storage);

  bool get isFirebaseAvailable => _isFirebaseInitialized && _auth != null;
  UserProfile? get currentUser => _currentUser;
  Stream<UserProfile?> get authStateChanges => _userStreamController.stream;

  /// Retrieves the current user's Firebase ID token for authenticating backend requests
  Future<String?> getIdToken({bool forceRefresh = false}) async {
    if (isFirebaseAvailable && _auth?.currentUser != null) {
      try {
        return await _auth!.currentUser!.getIdToken(forceRefresh);
      } catch (_) {}
    }
    // Demo officer / development token
    if (_currentUser?.isDemoUser == true) {
      return "DEMO_OFFICER_TOKEN";
    }
    if (_currentUser != null) {
      return "dev-test-token";
    }
    return null;
  }

  Future<void> initialize() async {
    try {
      if (Firebase.apps.isNotEmpty) {
        _isFirebaseInitialized = true;
        _auth = FirebaseAuth.instance;
      } else {
        _isFirebaseInitialized = false;
      }
    } catch (_) {
      _isFirebaseInitialized = false;
      _auth = null;
    }

    // Check cached local user profile
    _currentUser = _storage.getCachedUser();
    if (_isFirebaseInitialized && _auth != null) {
      final fbUser = _auth!.currentUser;
      if (fbUser != null) {
        _currentUser = UserProfile(
          uid: fbUser.uid,
          email: fbUser.email ?? 'officer@railsafe.local',
          displayName: fbUser.displayName ?? 'Screening Officer',
          role: "Screening Inspector",
          stationCode: "NDLS - New Delhi Central",
          isDemoUser: false,
        );
        await _storage.cacheUser(_currentUser);
      }
    }

    _userStreamController.add(_currentUser);
  }

  Future<UserProfile> signIn({required String email, required String password}) async {
    if (email.trim().isEmpty || password.trim().isEmpty) {
      throw AuthException("Email and password cannot be empty");
    }

    if (isFirebaseAvailable) {
      try {
        final credential = await _auth!.signInWithEmailAndPassword(
          email: email.trim(),
          password: password.trim(),
        );
        final user = credential.user;
        if (user == null) throw AuthException("Authentication failed: User null");

        final profile = UserProfile(
          uid: user.uid,
          email: user.email ?? email.trim(),
          displayName: user.displayName ?? email.split('@').first,
          role: "Screening Inspector",
          stationCode: "NDLS - New Delhi Central",
          isDemoUser: false,
        );
        _currentUser = profile;
        await _storage.cacheUser(profile);
        _userStreamController.add(_currentUser);
        return profile;
      } on FirebaseAuthException catch (e) {
        throw AuthException(e.message ?? "Authentication failed", code: e.code);
      } catch (e) {
        throw AuthException(e.toString());
      }
    } else {
      // Local / Offline authentication mode when Firebase is not connected
      final profile = UserProfile(
        uid: "local-user-${email.hashCode.abs()}",
        email: email.trim(),
        displayName: email.split('@').first.toUpperCase(),
        role: "Screening Inspector",
        stationCode: "NDLS - New Delhi Central",
        isDemoUser: false,
      );
      _currentUser = profile;
      await _storage.cacheUser(profile);
      _userStreamController.add(_currentUser);
      return profile;
    }
  }

  Future<UserProfile> register({
    required String displayName,
    required String email,
    required String password,
    String? stationCode,
  }) async {
    if (email.trim().isEmpty || password.trim().isEmpty || displayName.trim().isEmpty) {
      throw AuthException("All fields are required");
    }

    if (isFirebaseAvailable) {
      try {
        final credential = await _auth!.createUserWithEmailAndPassword(
          email: email.trim(),
          password: password.trim(),
        );
        final user = credential.user;
        if (user == null) throw AuthException("Registration failed: User null");

        await user.updateDisplayName(displayName.trim());

        final profile = UserProfile(
          uid: user.uid,
          email: user.email ?? email.trim(),
          displayName: displayName.trim(),
          role: "Screening Inspector",
          stationCode: stationCode ?? "NDLS - New Delhi Central",
          isDemoUser: false,
        );
        _currentUser = profile;
        await _storage.cacheUser(profile);
        _userStreamController.add(_currentUser);
        return profile;
      } on FirebaseAuthException catch (e) {
        throw AuthException(e.message ?? "Registration failed", code: e.code);
      } catch (e) {
        throw AuthException(e.toString());
      }
    } else {
      // Local authentication mode
      final profile = UserProfile(
        uid: "local-user-${email.hashCode.abs()}",
        email: email.trim(),
        displayName: displayName.trim(),
        role: "Screening Inspector",
        stationCode: stationCode ?? "NDLS - New Delhi Central",
        isDemoUser: false,
      );
      _currentUser = profile;
      await _storage.cacheUser(profile);
      _userStreamController.add(_currentUser);
      return profile;
    }
  }

  Future<UserProfile> signInAsDemoOfficer() async {
    final demoProfile = UserProfile.createDemoUser();
    _currentUser = demoProfile;
    await _storage.cacheUser(demoProfile);
    _userStreamController.add(_currentUser);
    return demoProfile;
  }

  Future<void> signOut() async {
    if (isFirebaseAvailable) {
      try {
        await _auth?.signOut();
      } catch (_) {}
    }
    _currentUser = null;
    await _storage.cacheUser(null);
    _userStreamController.add(null);
  }

  void dispose() {
    _userStreamController.close();
  }
}
