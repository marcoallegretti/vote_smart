import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import '../models/data_models.dart';

// Extension to capitalize the first letter of a string
extension StringExtension on String {
  String capitalize() {
    return isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
  }
}

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final bool _isTestMode;
  UserModel? _currentUser;

  // Stream controller for the UserModel
  final StreamController<UserModel?> _userModelController =
      StreamController<UserModel?>.broadcast();

  // Public stream for UserModel changes
  Stream<UserModel?> get userModelStream => _userModelController.stream;

  AuthService()
      : _auth = FirebaseAuth.instance,
        _firestore = FirebaseFirestore.instance,
        _isTestMode = false {
    _initialize();
  }

  // Constructor for testing with mock instances (auth only)
  AuthService.withInstance(this._auth)
      : _firestore = FirebaseFirestore.instance,
        _isTestMode = true {
    if (!_isTestMode) {
      _initialize();
    }
  }

  // Fully injectable constructor for testing (auth and firestore)
  AuthService.withInstances(this._auth, this._firestore)
      : _isTestMode = true {
    // No initialization in test mode
  }

  @override
  void dispose() {
    _userModelController.close();
    super.dispose();
  }

  Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } catch (e) {
      throw Exception('Failed to send password reset email: $e');
    }
  }

  // Demo user credentials with additional metadata
  static const Map<String, Map<String, dynamic>> demoUsers = {
    'admin': {
      'email': 'admin@example.com',
      'password': 'password123',
      'name': 'Admin User',
      'role': 'admin',
      'permissions': ['manage_users', 'manage_roles', 'manage_system'],
    },
    'moderator': {
      'email': 'moderator@example.com',
      'password': 'password123',
      'name': 'Moderator User',
      'role': 'moderator',
      'permissions': ['manage_content', 'review_proposals'],
    },
    'user': {
      'email': 'user@example.com',
      'password': 'password123',
      'name': 'Standard User',
      'role': 'user',
      'permissions': ['vote', 'delegate', 'comment'],
    },
    'proposer': {
      'email': 'proposer@example.com',
      'password': 'password123',
      'name': 'Proposer User',
      'role': 'proposer',
      'permissions': ['create_proposals', 'vote', 'comment'],
    },
  };

  // Get current user model
  UserModel? get currentUser => _currentUser;

  // Get current authentication state
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Sign up a new user
  Future<UserCredential> signUp(String email, String password) async {
    try {
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      return userCredential;
    } catch (e) {
      print('Error signing up: $e');
      rethrow;
    }
  }

  // Sign in a user
  Future<UserCredential> signIn(String email, String password) async {
    try {
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return userCredential;
    } catch (e) {
      print('Error signing in: $e');
      rethrow;
    }
  }

  // Initialize the service and listen for auth changes
  void _initialize() {
    print('DEBUG: 🔄 Initializing AuthService...');
    _auth.authStateChanges().listen((User? user) async {
      if (user != null) {
        print('DEBUG: 👤 Auth state changed - User signed in: ${user.uid}');
        print('DEBUG: 📧 User email: ${user.email}');

        try {
          await _fetchUserModel(user.uid);
        } catch (e) {
          print('DEBUG: ! Auth state listener error fetching user model: $e');
          if (_currentUser != null) {
            _currentUser = null;
            notifyListeners();
            _userModelController.sink.add(_currentUser);
          }
        }
      } else {
        print('DEBUG: ! Auth state changed - No user signed in');
        if (_currentUser != null) {
          _currentUser = null;
          notifyListeners();
          _userModelController.sink.add(_currentUser);
        }
      }
    });
  }

  // Fetch user model from Firestore
  Future<void> _fetchUserModel(String userId) async {
    print(
        'DEBUG: Attempting to fetch user model for userId: $userId. Current _auth.currentUser?.uid: ${_auth.currentUser?.uid}');

    if (_auth.currentUser == null || _auth.currentUser!.uid != userId) {
      print(
          'DEBUG: Skipping _fetchUserModel for $userId. Reason: _auth.currentUser is null OR _auth.currentUser.uid (${_auth.currentUser?.uid}) != target userId ($userId).');
      if (_auth.currentUser == null && _currentUser != null) {
        _currentUser = null;
        notifyListeners();
        _userModelController.sink.add(_currentUser);
      }
      return;
    }

    print(
        'DEBUG: Proceeding to fetch user model from Firestore for userId: $userId');

    try {
      final doc = await _firestore.collection('users').doc(userId).get();

      if (_auth.currentUser == null || _auth.currentUser!.uid != userId) {
        print(
            'DEBUG: Auth state changed during Firestore get() for $userId. Aborting _fetchUserModel.');
        if (_auth.currentUser == null && _currentUser != null) {
          _currentUser = null;
          notifyListeners();
          _userModelController.sink.add(_currentUser);
        }
        return;
      }

      if (doc.exists && doc.data() != null) {
        try {
          final userData = doc.data()!;
          _currentUser = UserModel.fromJson({
            'id': doc.id,
            'name': userData['name'] ?? '',
            'email': userData['email'] ?? '',
            'role': userData['role'] ?? 'user',
            'delegations': userData['delegations'] ?? [],
            'createdAt': userData['createdAt'] ?? FieldValue.serverTimestamp(),
            'updatedAt': userData['updatedAt'] ?? FieldValue.serverTimestamp(),
          });
          print(
              'Fetched user model for ${_currentUser?.name ?? 'unknown'} (ID: $userId) with role ${_currentUser?.role ?? 'unknown'}');
          notifyListeners(); // Notify after successful fetch and update
          _userModelController.sink.add(_currentUser);
        } catch (parseError) {
          print('ERROR parsing user data for $userId: $parseError');
          _currentUser = null;
          notifyListeners();
          _userModelController.sink.add(_currentUser);
        }
      } else {
        print(
            'User document does not exist for $userId. Potentially creating basic profile.');
        if (_auth.currentUser != null &&
            _auth.currentUser!.uid == userId &&
            _auth.currentUser!.email != null) {
          print(
              'DEBUG: Creating basic user profile for $userId in _fetchUserModel as document was not found.');
          await _createUserModelInFirestore(
            _auth.currentUser!,
            _auth.currentUser!.displayName ??
                _auth.currentUser!.email!.split('@')[0],
            UserRole.user,
          );
        } else {
          print(
              'DEBUG: Cannot create basic profile for $userId - auth state inconsistent or email null.');
          if (_currentUser != null) {
            _currentUser = null;
            notifyListeners();
            _userModelController.sink.add(_currentUser);
          }
        }
      }
    } catch (e) {
      print(
          'FIRESTORE ERROR in _fetchUserModel for $userId: $e. Stack: ${StackTrace.current}');
      if (_auth.currentUser != null && _auth.currentUser!.uid == userId) {
        _currentUser = null;
        notifyListeners();
        _userModelController.sink.add(_currentUser);
      }
    }
  }

  // Create a new user model in Firestore
  Future<void> _createUserModelInFirestore(
      User user, String name, UserRole role) async {
    print(
        'DEBUG: Attempting to create user model in Firestore for userId: ${user.uid}. Current _auth.currentUser?.uid: ${_auth.currentUser?.uid}');
    if (_auth.currentUser == null || _auth.currentUser!.uid != user.uid) {
      print(
          'DEBUG: Skipping _createUserModelInFirestore for ${user.uid}. Reason: _auth.currentUser is null OR _auth.currentUser.uid (${_auth.currentUser?.uid}) != target userId (${user.uid}).');
      return;
    }

    print(
        'DEBUG: Proceeding to create user model in Firestore for userId: ${user.uid}');

    try {
      await _firestore.collection('users').doc(user.uid).set({
        'name': name,
        'email': user.email,
        'role': role.name,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'delegations': [],
      });
      print(
          'DEBUG: Successfully created user model in Firestore for ${user.uid}');
    } catch (e) {
      print(
          'FIRESTORE ERROR in _createUserModelInFirestore for ${user.uid}: $e. Stack: ${StackTrace.current}');
    }
  }

  // Send email verification
  Future<void> sendEmailVerification() async {
    User? user = _auth.currentUser;
    if (user != null && !user.emailVerified) {
      await user.sendEmailVerification();
    }
  }

  // Request password reset email
  Future<void> requestPasswordReset(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  // Check if email is verified
  bool isEmailVerified() {
    return _auth.currentUser?.emailVerified ?? false;
  }

  // Sign in with email and password
  Future<UserCredential> signInWithEmailAndPassword(
      String email, String password) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(
          email: email, password: password);

      await _fetchUserModel(result.user!.uid);
      return result;
    } catch (e) {
      print('Error signing in: $e');
      rethrow;
    }
  }

  // Register with email and password
  Future<UserCredential> registerWithEmailAndPassword(
      String email, String password, String name, UserRole role) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
          email: email, password: password);

      await _createUserModelInFirestore(result.user!, name, role);

      return result;
    } catch (e) {
      print('Error registering user: $e');
      rethrow;
    }
  }

  // Sign out
  Future<void> signOut() async {
    try {
      print('DEBUG: 🚪 User signing out...');
      final currentAuthUser = _auth.currentUser;
      if (currentAuthUser == null) {
        print('DEBUG: No user currently signed in. Clearing local state.');
        if (_currentUser != null) {
          _currentUser = null;
          notifyListeners();
          _userModelController.sink.add(_currentUser);
        }
        return;
      }

      final currentEmail = currentAuthUser.email;
      print('DEBUG: 🚪 Attempting to sign out Firebase user: $currentEmail');

      await _auth.signOut();
      print('DEBUG: Firebase signOut() called for $currentEmail.');

      // Wait for authStateChanges to confirm the user is null
      final completer = Completer<void>();
      late StreamSubscription<User?> subscription;

      subscription = _auth.authStateChanges().listen((user) {
        if (user == null) {
          if (!completer.isCompleted) {
            print('DEBUG: ✅ Auth state confirmed null for $currentEmail.');
            completer.complete();
            subscription.cancel();
          }
        }
      });

      // Timeout to prevent indefinite waiting
      await completer.future.timeout(const Duration(seconds: 10),
          onTimeout: () {
        subscription.cancel();
        print(
            'WARNING: Timeout waiting for null auth state after signing out $currentEmail. Proceeding with local state clear.');
        // Fall through to clear local state anyway if timeout occurs
      });

      // Ensure local state is cleared after successful sign-out and confirmation
      if (_currentUser != null) {
        _currentUser = null;
        notifyListeners();
        _userModelController.sink.add(_currentUser);
      }
      print(
          'DEBUG: ✅ User signed out successfully and local state cleared for $currentEmail.');
    } catch (e) {
      print('ERROR: Failed to sign out: $e. Stack: ${StackTrace.current}');
      // Even if there's an error, try to reset the current user state
      if (_currentUser != null) {
        _currentUser = null;
        notifyListeners();
        _userModelController.sink.add(_currentUser);
      }
      // Don't rethrow, allow app to continue if possible
    }
  }

  // Create all demo users at once (for initialization)
  Future<void> createAllDemoUsers() async {
    print('DEBUG: 🚀 Starting demo user setup...');
    final originalAuthUser =
        _auth.currentUser; // Store original auth user to restore later
    String? originalUserEmail = originalAuthUser?.email;

    try {
      for (var userType in demoUsers.keys) {
        print('DEBUG: 🔄 Setting up demo user: $userType');
        try {
          // Ensure we are fully signed out before attempting to sign in a new demo user
          if (_auth.currentUser != null) {
            print(
                'DEBUG: Current user ${_auth.currentUser?.email} exists. Signing out before $userType setup.');
            await signOut();
          }

          await signInWithDemoCredentials(userType);
          print('DEBUG: ✅ Successfully created/verified demo user: $userType');

          // Sign out the current demo user before moving to the next one
          print('DEBUG: Signing out demo user $userType...');
          await signOut();
        } catch (e) {
          print(
              'ERROR: Failed to set up demo user $userType: $e. Attempting to recover...');
          // Ensure we are signed out before continuing to the next user or restoring original
          try {
            if (_auth.currentUser != null) {
              print(
                  'DEBUG: Error recovery - signing out current user: ${_auth.currentUser?.email}');
              await signOut();
            }
          } catch (innerError) {
            print(
                'ERROR: Additional error during cleanup for $userType: $innerError');
          }
        }
      }
      print('DEBUG: ✅ Demo user setup loop complete.');
    } catch (e) {
      print('ERROR: General failure in demo user setup sequence: $e');
    } finally {
      print('DEBUG: 🏁 Finalizing demo user setup...');
      // Ensure any lingering demo user is signed out
      if (_auth.currentUser != null &&
          demoUsers.values
              .any((du) => du['email'] == _auth.currentUser!.email)) {
        print(
            'DEBUG: Lingering demo user ${_auth.currentUser!.email} found. Signing out.');
        await signOut();
      }

      // Restore original user session if there was one
      if (originalUserEmail != null &&
          _auth.currentUser?.email != originalUserEmail) {
        print(
            'DEBUG: 🔄 Restoring original user session for: $originalUserEmail');
        try {
          // Attempt to sign in the original user by finding their type or using a generic sign-in.
          // This assumes original user might be one of the demo users or a regularly signed-in user.
          // For simplicity, if it was a demo user, we try to sign them back in.
          // A more robust solution might need to store original user's credentials securely if not a demo user.
          bool restored = false;
          for (var entry in demoUsers.entries) {
            if (entry.value['email'] == originalUserEmail) {
              await signInWithDemoCredentials(entry.key);
              print(
                  'DEBUG: ✅ Successfully restored original demo user session: $originalUserEmail');
              restored = true;
              break;
            }
          }
          if (!restored) {
            // If not a demo user, this part needs a strategy. For now, we'll just log.
            // If you have a generic signIn(email, password) and stored credentials, use it here.
            // Or, if the app expects the user to re-login manually if their session was interrupted this way.
            print(
                'DEBUG: Original user $originalUserEmail was not a demo user. Manual re-login may be required if not already signed in.');
            // If _auth.currentUser is already the original user, no action needed.
            if (_auth.currentUser?.email == originalUserEmail) {
              print(
                  'DEBUG: Original user $originalUserEmail is already the active user.');
            } else if (_auth.currentUser != null) {
              print(
                  'DEBUG: A different user ${_auth.currentUser!.email} is active. This might be unexpected.');
            } else {
              print(
                  'DEBUG: No user is active after demo setup and original was $originalUserEmail.');
              // Potentially trigger a sign-in screen or a specific state for re-login.
            }
          }
        } catch (e) {
          print(
              'ERROR: Failed to restore original user session for $originalUserEmail: $e');
          // Ensure a clean state if restoration fails
          if (_auth.currentUser != null) {
            await signOut();
          }
        }
      } else if (originalUserEmail != null &&
          _auth.currentUser?.email == originalUserEmail) {
        print(
            'DEBUG: Original user session $originalUserEmail already active. No restoration needed.');
      } else if (originalUserEmail == null && _auth.currentUser != null) {
        print(
            'DEBUG: No original user to restore, but a user ${_auth.currentUser?.email} is active. Signing out for clean state.');
        await signOut();
      } else {
        print(
            'DEBUG: No original user session to restore and no user currently active.');
      }
      print('DEBUG: 🏁 Demo user setup process finished.');
    }
  }

  // Sign in with demo user credentials
  Future<UserCredential> signInWithDemoCredentials(String userType) async {
    if (!demoUsers.containsKey(userType)) {
      throw Exception('Invalid demo user type: $userType');
    }

    final email = demoUsers[userType]!['email']!;
    final password = demoUsers[userType]!['password']!;

    print('DEBUG: 🔑 Attempting to sign in as demo $userType user: $email');

    // Ensure we're signed out first to avoid state conflicts
    if (_auth.currentUser != null) {
      print(
          'DEBUG: 🚪 Signing out current user before signing in as $userType');
      try {
        // Use the main signOut method for consistency and robustness
        await signOut();
      } catch (e) {
        print('WARNING: Error during pre-signin signout: $e');
      }
    }

    // Helper function to wait for specific auth state
    Future<User> waitForAuthState(String targetUid) async {
      final completer = Completer<User>();
      late StreamSubscription<User?> subscription;

      subscription = _auth.authStateChanges().listen((user) {
        if (user != null && user.uid == targetUid) {
          if (!completer.isCompleted) {
            completer.complete(user);
            subscription.cancel();
          }
        }
      });

      // Timeout to prevent indefinite waiting
      return completer.future.timeout(const Duration(seconds: 10),
          onTimeout: () {
        subscription.cancel();
        throw TimeoutException(
            'Timed out waiting for auth state for $targetUid');
      });
    }

    try {
      // Try to sign in with existing credentials
      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      print('DEBUG: ✅ Firebase sign-in successful for $email (existing user)');
      await waitForAuthState(
          result.user!.uid); // Wait for auth state propagation
      print('DEBUG: ✅ Auth state confirmed for $email');
      await _fetchUserModel(result.user!.uid);
      return result;
    } catch (e) {
      if (e is FirebaseAuthException && e.code == 'user-not-found') {
        // If user doesn't exist, create a new one
        print(
            'DEBUG: 🆕 Demo user $email not found, creating new $userType user');
        try {
          UserCredential result = await _auth.createUserWithEmailAndPassword(
            email: email,
            password: password,
          );
          print('DEBUG: ✅ Firebase user creation successful for $email');
          await waitForAuthState(
              result.user!.uid); // Wait for auth state propagation
          print('DEBUG: ✅ Auth state confirmed for new user $email');

          // Create user model with appropriate role
          final UserRole role;
          switch (userType) {
            case 'admin':
              role = UserRole.admin;
              break;
            case 'moderator':
              role = UserRole.moderator;
              break;
            case 'proposer':
              role = UserRole.proposer;
              break;
            default:
              role = UserRole.user;
          }

          // Set display name based on role
          await result.user!.updateDisplayName('${userType.capitalize()} User');

          // Create user document in Firestore
          await _firestore.collection('users').doc(result.user!.uid).set({
            'email': email,
            'displayName': '${userType.capitalize()} User',
            'role': role.toString().split('.').last,
            'createdAt': FieldValue.serverTimestamp(),
          });

          print('DEBUG: ✅ Created new demo $userType user');
          await _fetchUserModel(
              result.user!.uid); // Fetch to ensure _currentUser is set
          return result;
        } catch (creationError) {
          print('ERROR: Failed to create demo user $userType: $creationError');
          rethrow;
        }
      } else if (e is TimeoutException) {
        print(
            'ERROR: Timeout waiting for auth state propagation for $email: $e');
        rethrow;
      } else {
        print('ERROR: Failed to sign in demo user $userType ($email): $e');
        rethrow;
      }
    }
  }

  // Update user profile
  Future<void> updateUserProfile(String name) async {
    try {
      if (_currentUser != null) {
        await _firestore.collection('users').doc(_currentUser?.id).update({
          'name': name,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        await _fetchUserModel(_currentUser?.id ?? '');
      }
    } catch (e) {
      print('Error updating profile: $e');
      rethrow;
    }
  }

  // Change user role (admin only)
  Future<void> changeUserRole(String userId, UserRole newRole) async {
    try {
      if (_currentUser?.role == UserRole.admin) {
        await _firestore.collection('users').doc(userId).update({
          'role': newRole.toString().split('.').last,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        throw Exception('Only admins can change user roles');
      }
    } catch (e) {
      print('Error changing user role: $e');
      rethrow;
    }
  }

  // Get user by ID
  Future<UserModel?> getUserById(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();

      if (doc.exists) {
        return UserModel.fromJson({
          'id': doc.id,
          ...doc.data()!,
        });
      }

      return null;
    } catch (e) {
      print('Error getting user: $e');
      return null;
    }
  }

  // Get all users (admin only)
  Future<List<UserModel>> getAllUsers() async {
    try {
      if (_currentUser?.role == UserRole.admin) {
        final snapshot = await _firestore.collection('users').get();

        return snapshot.docs
            .map((doc) => UserModel.fromJson({
                  'id': doc.id,
                  ...doc.data(),
                }))
            .toList();
      } else {
        throw Exception('Only admins can access all users');
      }
    } catch (e) {
      print('Error getting all users: $e');
      rethrow;
    }
  }
}
