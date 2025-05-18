import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/data_models.dart';
import 'auth_service.dart';

class DatabaseInitializer {
  final FirebaseFirestore _firestore;
  final AuthService _authService;

  DatabaseInitializer()
      : _firestore = FirebaseFirestore.instance,
        _authService = AuthService();

  // Fully injectable constructor for testing
  DatabaseInitializer.withInstances(this._firestore, this._authService);

  static const String _initDoneKey = 'database_initialized_flag'; // Key for SharedPreferences

  // Initialize the database with sample data
  Future<void> initializeDatabase() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_initDoneKey) ?? false) {
      print('INFO: Database already initialized (flag found). Skipping.');
      return;
    }

    try {
      print('INFO: Starting database initialization (first time)...');
      
      bool adminAuthenticated = false;
      final initialUser = FirebaseAuth.instance.currentUser;

      if (initialUser != null && initialUser.email == 'admin@example.com') {
        print('INFO: Admin user is already signed in.');
        // Verify UserModel is loaded for admin, otherwise _fetchUserModel might not have completed from a previous run.
        if (_authService.currentUser == null || _authService.currentUser?.email != 'admin@example.com') {
          print('INFO: Admin UserModel not yet loaded in this AuthService instance, fetching...');
          await _authService.signInWithEmailAndPassword('admin@example.com', 'password123');
        }
        adminAuthenticated = true;
      } else {
        print('INFO: No admin user signed in or a different user is active. Attempting admin sign-in for initialization.');
        if (initialUser != null) {
          print('INFO: Signing out current user: ${initialUser.email} before admin login.');
          await _authService.signOut(); // Use the service's sign out
        }
        try {
          await _authService.signInWithEmailAndPassword(
            'admin@example.com',
            'password123',
          );
          final adminUser = FirebaseAuth.instance.currentUser; // Re-check after sign-in attempt
          if (adminUser != null && adminUser.email == 'admin@example.com') {
            print('INFO: Successfully authenticated as admin: ${adminUser.uid}');
            adminAuthenticated = true;
          } else {
            print('ERROR: Failed to authenticate as admin! Aborting initialization.');
            return;
          }
        } catch (e) {
          print('ERROR: Exception during admin sign-in for initialization: $e. Aborting.');
          return;
        }
      }

      if (!adminAuthenticated) {
        print('ERROR: Admin authentication could not be established. Aborting initialization.');
        return;
      }
      
      // Initialize users collection (conditionally)
      await _initializeUsersIfNeeded();
      
      // Initialize topics collection
      await _initializeTopics();
      
      // Initialize settings collection
      await _initializeSettings();
      
      // Initialize proposals collection
      await _initializeProposals();
      
      // Attempt to restore original user or sign out admin if this initializer isn't the main app flow.
      // For now, leave admin signed in as per previous logic, main app flow will handle user state.
      print('INFO: Database initialization process completed. Admin is expected to be signed in.');
      
      // Set the flag after successful initialization
      await prefs.setBool(_initDoneKey, true);
      print('INFO: Database initialization flag set. Future runs will skip this process.');

    } catch (e) {
      print('ERROR: Error initializing database: $e');
      // Do not set the flag if initialization failed, so it can be retried.
    }
  }

  // Initialize users collection only if they seem to be missing
  Future<void> _initializeUsersIfNeeded() async {
    try {
      print('INFO: Checking if users collection needs initialization...');
      
      // Check if admin user document exists as a proxy for demo users setup
      // This is a simplification. A more robust check might query for all demo users.
      final adminEmail = AuthService.demoUsers['admin']!['email']!;
      QuerySnapshot adminUserQuery = await _firestore
          .collection('users')
          .where('email', isEqualTo: adminEmail)
          .limit(1)
          .get();

      if (adminUserQuery.docs.isNotEmpty) {
        print('INFO: Admin user document found. Assuming demo users are already initialized.');
        // Optionally, verify all demo users here if needed for full integrity.
      } else {
        print('INFO: Admin user document NOT found. Proceeding to create all demo users.');
        // Ensure admin is authenticated within this AuthService instance context
        if (_authService.currentUser == null || _authService.currentUser?.role != UserRole.admin) {
            print('INFO: Ensuring admin context in AuthService before creating demo users...');
            await _authService.signInWithEmailAndPassword(AuthService.demoUsers['admin']!['email']!, AuthService.demoUsers['admin']!['password']!); 
        }

        await _authService.createAllDemoUsers();
        print('INFO: Demo users creation process completed.');

        // createAllDemoUsers attempts to restore original user or signs out.
        // For initialization, we often want admin to remain signed in to proceed.
        // So, ensure admin is signed back in if not already.
        if (FirebaseAuth.instance.currentUser?.email != adminEmail) {
            print('INFO: Re-authenticating as admin after demo user creation for subsequent initialization steps...');
            await _authService.signInWithEmailAndPassword(adminEmail, AuthService.demoUsers['admin']!['password']!); 
        }
      }
      
      print('INFO: Users collection check/initialization completed.');
    } catch (e) {
      print('ERROR: Error initializing users collection: $e');
    }
  }

  // Initialize topics collection
  Future<void> _initializeTopics() async {
    try {
      print('INFO: Initializing topics collection...');
      
      final topicsQuery = await _firestore.collection('topics').limit(1).get(); // More efficient check
      
      if (topicsQuery.docs.isNotEmpty) {
        print('INFO: Topics collection already appears to be initialized.');
        return;
      }
      
      final sampleTopics = [
        {
          'title': 'Environmental Initiatives',
          'description': 'Proposals related to environmental protection and sustainability.',
        },
        {
          'title': 'Community Development',
          'description': 'Proposals for improving local community infrastructure and services.',
        },
        {
          'title': 'Education Reform',
          'description': 'Proposals for enhancing educational systems and opportunities.',
        },
        {
          'title': 'Healthcare Access',
          'description': 'Proposals focused on improving healthcare accessibility and quality.',
        },
      ];
      
      // Create sample topics
      for (var topicData in sampleTopics) {
        final docRef = _firestore.collection('topics').doc();
        
        await docRef.set({
          'title': topicData['title'],
          'description': topicData['description'],
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        
        print('INFO: Created sample topic: ${topicData['title']}');
      }
      
      print('INFO: Topics collection initialization completed');
    } catch (e) {
      print('ERROR: Error initializing topics collection: $e');
    }
  }

  // Initialize settings collection
  Future<void> _initializeSettings() async {
    try {
      print('INFO: Initializing settings collection...');
      
      final votingSettingsDoc = await _firestore.collection('settings').doc('voting').get();
      
      if (votingSettingsDoc.exists) {
        print('INFO: Voting settings already initialized.');
      } else {
        await _firestore.collection('settings').doc('voting').set({
          'defaultMethod': 'firstPastThePost',
          'availableMethods': [
            'firstPastThePost',
            'approvalVoting',
            'rankedChoice',
            'borda',
            'condorcet',
            'cumulativeVoting',
            'quadraticVoting',
          ],
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        print('INFO: Created default voting settings');
      }
      
      final topicVotingMethodsDoc = await _firestore.collection('settings').doc('topicVotingMethods').get();
      
      if (topicVotingMethodsDoc.exists) {
        print('INFO: Topic voting methods already initialized');
      } else {
        final topicsQuery = await _firestore.collection('topics').get();
        if (topicsQuery.docs.isEmpty) {
            print('WARN: No topics found to initialize topic voting methods. Skipping.');
            return;
        }
        
        final topicVotingMethods = <String, dynamic>{
          'updatedAt': FieldValue.serverTimestamp(),
        };
        
        for (var topic in topicsQuery.docs) {
          final topicId = topic.id;
          final topicTitle = topic.data()['title'] as String? ?? 'Unknown Topic';
          
          String votingMethod;
          if (topicTitle.contains('Environmental')) {
            votingMethod = 'approvalVoting';
          } else if (topicTitle.contains('Community')) {
            votingMethod = 'rankedChoice';
          } else if (topicTitle.contains('Education')) {
            votingMethod = 'cumulativeVoting'; // Changed for variety
          } else if (topicTitle.contains('Healthcare')) {
            votingMethod = 'quadraticVoting'; // Changed for variety
          } else {
            votingMethod = 'firstPastThePost'; // Default fallback
          }
          topicVotingMethods[topicId] = votingMethod;
        }
        
        await _firestore.collection('settings').doc('topicVotingMethods').set(topicVotingMethods);
        print('INFO: Created topic voting methods settings');
      }
      print('INFO: Settings collection initialization completed');
    } catch (e) {
      print('ERROR: Error initializing settings collection: $e');
    }
  }

  // Initialize proposals collection
  Future<void> _initializeProposals() async {
    try {
      print('INFO: Initializing proposals collection...');
      
      final proposalsQuery = await _firestore.collection('proposals').limit(1).get(); // More efficient check
      
      if (proposalsQuery.docs.isNotEmpty) {
        print('INFO: Proposals collection already appears to be initialized.');
        return;
      }

      // Ensure we have topics to associate proposals with
      final topicsSnapshot = await _firestore.collection('topics').get();
      if (topicsSnapshot.docs.isEmpty) {
        print('WARN: No topics found. Cannot create sample proposals.');
        return;
      }
      List<DocumentSnapshot> topics = topicsSnapshot.docs;

      // Ensure we have users (proposers) to associate proposals with
      // For simplicity, try to get the 'proposer' demo user's ID after demo user setup.
      final proposerEmail = AuthService.demoUsers['proposer']!['email']!;
      final proposerUserQuery = await _firestore.collection('users').where('email', isEqualTo: proposerEmail).limit(1).get();
      String proposerId = 'unknown_proposer_id'; // Fallback ID
      if (proposerUserQuery.docs.isNotEmpty) {
          proposerId = proposerUserQuery.docs.first.id;
      } else {
          print('WARN: Proposer demo user not found. Sample proposals will use a fallback ID.');
      }
      
      final sampleProposals = [
        {
          'title': 'Community Garden Initiative',
          'description': 'Establish a community garden to promote local food production and community engagement.',
          'topicId': topics.firstWhere((t) => (t.data() as Map)['title'].contains('Community'), orElse: () => topics.first).id,
          'createdBy': proposerId,
          'status': 'pending',
        },
        {
          'title': 'Renewable Energy for Public Buildings',
          'description': 'Install solar panels on all municipal buildings to reduce carbon footprint.',
          'topicId': topics.firstWhere((t) => (t.data() as Map)['title'].contains('Environmental'), orElse: () => topics.first).id,
          'createdBy': proposerId,
          'status': 'pending',
        },
        {
          'title': 'Digital Literacy Program for Seniors',
          'description': 'Offer free workshops to help seniors improve their digital skills.',
          'topicId': topics.firstWhere((t) => (t.data() as Map)['title'].contains('Education'), orElse: () => topics.first).id,
          'createdBy': proposerId,
          'status': 'active_voting',
          'votingStartDate': Timestamp.now(),
          'votingEndDate': Timestamp.fromDate(DateTime.now().add(const Duration(days: 7))),
        },
         {
          'title': 'Expansion of Public Health Clinics',
          'description': 'Increase the number of public health clinics in underserved areas.',
          'topicId': topics.firstWhere((t) => (t.data() as Map)['title'].contains('Healthcare'), orElse: () => topics.first).id,
          'createdBy': proposerId,
          'status': 'closed_voting_ended',
          'votingStartDate': Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 14))),
          'votingEndDate': Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 7))),
        },
      ];
      
      for (var proposalData in sampleProposals) {
        final docRef = _firestore.collection('proposals').doc();
        
        await docRef.set({
          ...proposalData,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'choices': ['Yes', 'No', 'Abstain'], // Default choices
          'results': {},
          'totalVotes': 0,
        });
        print('INFO: Created sample proposal: ${proposalData['title']}');
      }
      
      print('INFO: Proposals collection initialization completed');
    } catch (e) {
      print('ERROR: Error initializing proposals collection: $e');
    }
  }
}
