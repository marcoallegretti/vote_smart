import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/data_models.dart';

class DatabaseService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final bool _isTestMode;

  DatabaseService()
      : _firestore = FirebaseFirestore.instance,
        _auth = FirebaseAuth.instance,
        _isTestMode = false;

  // Constructor for testing with mock instances
  DatabaseService.withInstance(this._firestore, {FirebaseAuth? auth})
      : _auth = auth ?? FirebaseAuth.instance,
        _isTestMode = true;

  // Get current user ID
  String? get currentUserId => _auth.currentUser?.uid;

  // TOPICS
  // Create a new topic (admin only)
  Future<TopicModel> createTopic(String title, String description) async {
    try {
      final docRef = _firestore.collection('topics').doc();

      final topic = TopicModel(
        id: docRef.id,
        title: title,
        description: description,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await docRef.set(topic.toJson());
      return topic;
    } catch (e) {
      print('Error creating topic: $e');
      rethrow;
    }
  }

  // Get all topics
  Future<List<TopicModel>> getAllTopics() async {
    try {
      final snapshot = await _firestore.collection('topics').get();

      return snapshot.docs
          .map((doc) => TopicModel.fromJson({
                'id': doc.id,
                ...doc.data(),
              }))
          .toList();
    } catch (e) {
      print('Error getting topics: $e');
      rethrow;
    }
  }

  // Get topic by ID
  Future<TopicModel?> getTopicById(String topicId) async {
    try {
      final doc = await _firestore.collection('topics').doc(topicId).get();

      if (doc.exists) {
        return TopicModel.fromJson({
          'id': doc.id,
          ...doc.data()!,
        });
      }

      return null;
    } catch (e) {
      print('Error getting topic: $e');
      return null;
    }
  }

  // PROPOSALS
  // Create a new proposal
  Future<ProposalModel> createProposal(
      String title, String content, String topicId, {VotingMethod? preferredVotingMethod}) async {
    try {
      final userId = currentUserId;
      if (userId == null) throw Exception('User not authenticated');

      final docRef = _firestore.collection('proposals').doc();

      final proposal = ProposalModel(
        id: docRef.id,
        title: title,
        content: content,
        authorId: userId,
        topicId: topicId,
        status: ProposalStatus.draft,
        supporters: [userId], // Author is automatically a supporter
        preferredVotingMethod: preferredVotingMethod,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await docRef.set(proposal.toJson());
      return proposal;
    } catch (e) {
      print('Error creating proposal: $e');
      rethrow;
    }
  }

  // Get proposals by topic
  Future<List<ProposalModel>> getProposalsByTopic(String topicId) async {
    try {
      final snapshot = await _firestore
          .collection('proposals')
          .where('topicId', isEqualTo: topicId)
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => ProposalModel.fromJson({
                'id': doc.id,
                ...doc.data(),
              }))
          .toList();
    } catch (e) {
      print('Error getting proposals by topic: $e');
      rethrow;
    }
  }

  // Get proposals by status
  Future<List<ProposalModel>> getProposalsByStatus(
      ProposalStatus status) async {
    try {
      // First try with the index that includes createdAt
      try {
        final snapshot = await _firestore
            .collection('proposals')
            .where('status', isEqualTo: status.toString().split('.').last)
            .orderBy('createdAt', descending: true)
            .get();

        return snapshot.docs
            .map((doc) => ProposalModel.fromJson({
                  'id': doc.id,
                  ...doc.data(),
                }))
            .toList();
      } catch (indexError) {
        // Fallback to a simpler query without ordering if index is missing
        print('Using fallback query without ordering: $indexError');
        final snapshot = await _firestore
            .collection('proposals')
            .where('status', isEqualTo: status.toString().split('.').last)
            .get();

        return snapshot.docs
            .map((doc) => ProposalModel.fromJson({
                  'id': doc.id,
                  ...doc.data(),
                }))
            .toList();
      }
    } catch (e) {
      print('Error getting proposals by status: $e');
      return []; // Return empty list instead of throwing to avoid app crashes
    }
  }

  // PLATFORM SETTINGS

  // Local cache for settings when Firestore permissions are restricted
  static final Map<String, dynamic> _localSettings = {
    'defaultVotingMethod': 'firstPastThePost',
  };

  // Get platform default voting method
  Future<VotingMethod> getDefaultVotingMethod() async {
    try {
      // First try to get from Firestore
      try {
        final doc = await _firestore.collection('settings').doc('voting').get();

        if (doc.exists &&
            doc.data() != null &&
            doc.data()!.containsKey('defaultMethod')) {
          final methodStr = doc.data()!['defaultMethod'] as String;
          // Update local cache
          _localSettings['defaultVotingMethod'] = methodStr;
          return _parseVotingMethod(methodStr);
        }
      } catch (firestoreError) {
        print(
            'Error accessing Firestore for default voting method: $firestoreError');
        // Continue to use local cache
      }

      // Use local cache if Firestore failed
      final localMethodStr = _localSettings['defaultVotingMethod'] as String;
      print('Using locally cached voting method: $localMethodStr');
      return _parseVotingMethod(localMethodStr);
    } catch (e) {
      print('Error getting default voting method: $e');
      // Fallback to first past the post if there's an error
      return VotingMethod.firstPastThePost;
    }
  }

  // Helper method to parse voting method string to enum
  VotingMethod _parseVotingMethod(String methodStr) {
    try {
      return VotingMethod.values.firstWhere(
        (method) => method.toString().split('.').last == methodStr,
        orElse: () => VotingMethod.firstPastThePost,
      );
    } catch (e) {
      print('Error parsing voting method: $e');
      return VotingMethod.firstPastThePost;
    }
  }

  // Update platform default voting method
  Future<bool> updateDefaultVotingMethod(VotingMethod method) async {
    try {
      // First try with direct Firestore access
      try {
        await _firestore.collection('settings').doc('voting').set({
          'defaultMethod': method.toString().split('.').last,
          'updatedAt': _isTestMode ? DateTime.now() : FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        return true;
      } catch (directError) {
        print(
            'Direct update failed, trying alternative approach: $directError');

        // Store the method in local storage as a fallback
        // This ensures the UI shows the selected method even if Firebase update fails
        final methodStr = method.toString().split('.').last;
        _localSettings['defaultVotingMethod'] = methodStr;
        print('Setting local default method to: $methodStr');

        // Return false to indicate that the server update failed
        // but we've handled it gracefully
        return false;
      }
    } catch (e) {
      print('Error updating default voting method: $e');
      return false;
    }
  }

  // Get topic-specific default voting method
  Future<VotingMethod?> getTopicDefaultVotingMethod(String topicId) async {
    try {
      final doc = await _firestore
          .collection('settings')
          .doc('topicVotingMethods')
          .get();

      if (doc.exists) {
        final data = doc.data();
        if (data != null && data.containsKey(topicId)) {
          final methodStr = data[topicId] as String;
          try {
            return VotingMethod.values.firstWhere(
              (method) => method.toString().split('.').last == methodStr,
              orElse: () => VotingMethod.firstPastThePost,
            );
          } catch (e) {
            print('Error parsing topic voting method: $e');
          }
        }
      }

      // Return null if not found (will fall back to platform default)
      return null;
    } catch (e) {
      print('Error getting topic default voting method: $e');
      return null;
    }
  }

  // Update topic-specific default voting method
  Future<void> updateTopicDefaultVotingMethod(
      String topicId, VotingMethod method) async {
    try {
      await _firestore.collection('settings').doc('topicVotingMethods').set({
        topicId: method.toString().split('.').last,
        'updatedAt': _isTestMode ? DateTime.now() : FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      print('Error updating topic default voting method: $e');
      rethrow;
    }
  }
  
  // Get available voting methods
  Future<Map<String, bool>> getAvailableVotingMethods() async {
    try {
      // Initialize with all methods available by default
      final availableMethods = <String, bool>{};
      for (var method in VotingMethod.values) {
        final methodName = method.toString().split('.').last;
        availableMethods[methodName] = true;
      }
      
      // Try to get from Firestore
      try {
        final doc = await _firestore.collection('settings').doc('availableVotingMethods').get();
        
        if (doc.exists && doc.data() != null && doc.data()!.containsKey('methods')) {
          final methods = doc.data()!['methods'] as Map<String, dynamic>?;
          if (methods != null) {
            methods.forEach((key, value) {
              if (value is bool) {
                availableMethods[key] = value;
              }
            });
          }
        }
      } catch (e) {
        print('Error getting available voting methods: $e');
        // Continue with default values
      }
      
      return availableMethods;
    } catch (e) {
      print('Error in getAvailableVotingMethods: $e');
      // Return default values if there's an error
      final defaultMethods = <String, bool>{};
      for (var method in VotingMethod.values) {
        final methodName = method.toString().split('.').last;
        defaultMethods[methodName] = true;
      }
      return defaultMethods;
    }
  }
  
  // Update available voting methods
  Future<bool> updateAvailableVotingMethods(Map<String, bool> methods) async {
    try {
      await _firestore.collection('settings').doc('availableVotingMethods').set({
        'methods': methods,
        'updatedAt': _isTestMode ? DateTime.now() : FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      print('Error updating available voting methods: $e');
      return false;
    }
  }

  // Get proposals by author
  Future<List<ProposalModel>> getProposalsByAuthor(String? authorId) async {
    try {
      if (authorId == null) {
        print('Warning: Attempted to get proposals with null authorId');
        return [];
      }

      final snapshot = await _firestore
          .collection('proposals')
          .where('authorId', isEqualTo: authorId)
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => ProposalModel.fromJson({
                'id': doc.id,
                ...doc.data(),
              }))
          .toList();
    } catch (e) {
      print('Error getting proposals by author: $e');
      rethrow;
    }
  }

  // Get proposal by ID
  Future<ProposalModel?> getProposalById(String proposalId) async {
    try {
      final doc =
          await _firestore.collection('proposals').doc(proposalId).get();

      if (doc.exists) {
        return ProposalModel.fromJson({
          'id': doc.id,
          ...doc.data()!,
        });
      }

      return null;
    } catch (e) {
      print('Error getting proposal: $e');
      return null;
    }
  }

  // Update proposal status
  Future<void> updateProposalStatus(
      String proposalId, ProposalStatus newStatus) async {
    try {
      await _firestore.collection('proposals').doc(proposalId).update({
        'status': newStatus.toString().split('.').last,
        'updatedAt': _isTestMode ? DateTime.now() : FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error updating proposal status: $e');
      rethrow;
    }
  }

  // Support a proposal
  Future<void> supportProposal(String proposalId) async {
    try {
      final userId = currentUserId;
      if (userId == null) throw Exception('User not authenticated');

      await _firestore.collection('proposals').doc(proposalId).update({
        'supporters': FieldValue.arrayUnion([userId]),
        'updatedAt': _isTestMode ? DateTime.now() : FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error supporting proposal: $e');
      rethrow;
    }
  }

  // VOTE SESSIONS
  // Create a new vote session
  Future<VoteSessionModel> createVoteSession(
      String proposalId,
      VotingMethod method,
      List<String> options,
      DateTime startDate,
      DateTime endDate) async {
    try {
      final docRef = _firestore.collection('voteSessions').doc();

      // Determine status based on start date
      VoteSessionStatus status;
      final now = DateTime.now();
      if (startDate.isAfter(now)) {
        status = VoteSessionStatus.upcoming;
      } else if (endDate.isAfter(now)) {
        status = VoteSessionStatus.active;
      } else {
        status = VoteSessionStatus.closed;
      }

      final voteSession = VoteSessionModel(
        id: docRef.id,
        proposalId: proposalId,
        method: method,
        options: options,
        startDate: startDate,
        endDate: endDate,
        status: status,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await docRef.set(voteSession.toJson());

      // Update proposal status to voting
      await updateProposalStatus(proposalId, ProposalStatus.voting);

      return voteSession;
    } catch (e) {
      print('Error creating vote session: $e');
      rethrow;
    }
  }

  // Get vote session by proposal ID
  Future<VoteSessionModel?> getVoteSessionByProposal(String proposalId) async {
    try {
      final snapshot = await _firestore
          .collection('voteSessions')
          .where('proposalId', isEqualTo: proposalId)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        return VoteSessionModel.fromJson({
          'id': snapshot.docs.first.id,
          ...snapshot.docs.first.data(),
        });
      }

      return null;
    } catch (e) {
      print('Error getting vote session: $e');
      return null;
    }
  }

  Future<VoteSessionModel?> getVoteSessionById(String sessionId) async {
    try {
      final doc =
          await _firestore.collection('voteSessions').doc(sessionId).get();

      if (doc.exists) {
        return VoteSessionModel.fromJson({
          'id': doc.id,
          ...doc.data()!,
        });
      }

      return null;
    } catch (e) {
      print('Error getting vote session by ID: $e');
      return null;
    }
  }

  // Get active vote sessions
  Future<List<VoteSessionModel>> getActiveVoteSessions() async {
    try {
      final snapshot = await _firestore
          .collection('voteSessions')
          .where('status',
              isEqualTo: VoteSessionStatus.active.toString().split('.').last)
          .get();

      return snapshot.docs
          .map((doc) => VoteSessionModel.fromJson({
                'id': doc.id,
                ...doc.data(),
              }))
          .toList();
    } catch (e) {
      print('Error getting active vote sessions: $e');
      rethrow;
    }
  }

  // VOTES
  // Casts a vote for the current user in a given session (proposal).
  // Also handles propagating this vote to users who have delegated their vote to the current user.
  Future<void> castVote(String proposalId, dynamic choice, {double weight = 1.0}) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      throw Exception('User not logged in');
    }

    // Check if the user has already voted in this session
    final existingVoteQuery = await _firestore
        .collection('votes')
        .where('userId', isEqualTo: userId)
        .where('proposalId', isEqualTo: proposalId)
        .limit(1)
        .get();

    if (existingVoteQuery.docs.isNotEmpty) {
      // User has already voted, update the existing vote
      final existingVoteDoc = existingVoteQuery.docs.first;
      await existingVoteDoc.reference.update({
        'choice': choice,
        'weight': weight, // Update weight if it changed
        'updatedAt': FieldValue.serverTimestamp(),
        'isDelegated': false, // Ensure it's marked as a direct vote
        'delegatedBy': null, // Clear any previous delegation info
      });
    } else {
      // User has not voted, create a new vote
      final voteRef = _firestore.collection('votes').doc();
      final vote = VoteModel(
        id: voteRef.id,
        userId: userId,
        proposalId: proposalId,
        choice: choice,
        isDelegated: false,
        weight: weight, // Use the provided weight for the direct vote
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await voteRef.set(vote.toJson());
    }

    // Propagate the vote to users who delegated to the current user for this proposal's topic (or globally)
    final proposalDoc = await _firestore.collection('proposals').doc(proposalId).get();
    final proposalData = proposalDoc.data();
    final topicId = proposalData?['topicId'] as String?;

    final delegationsToMeSnapshot = await _firestore
        .collection('delegations')
        .where('delegateeId', isEqualTo: userId)
        .where('active', isEqualTo: true)
        // .where('validUntil', isGreaterThanOrEqualTo: Timestamp.now()) // Already handled by 'active' potentially, but good for explicitness
        .get();

    for (final delegationDoc in delegationsToMeSnapshot.docs) {
      final delegation = DelegationModel.fromJson(delegationDoc.data());
      final delegatorId = delegation.delegatorId;

      // Check if the delegation applies to this proposal's topic or is a global delegation
      if (delegation.topicId == null || delegation.topicId == topicId) {
        // Check if the delegator has already voted in this session
        final existingDelegatedVoteSnapshot = await _firestore
            .collection('votes')
            .where('userId', isEqualTo: delegatorId)
            .where('proposalId', isEqualTo: proposalId)
            .limit(1)
            .get();

        if (existingDelegatedVoteSnapshot.docs.isEmpty) {
          final delegatedVoteRef = _firestore.collection('votes').doc();
          final delegatedVote = VoteModel(
            id: delegatedVoteRef.id,
            userId: delegatorId,
            proposalId: proposalId,
            choice: choice,
            isDelegated: true,
            delegatedBy: userId,
            weight: weight, // The weight of the delegate's vote is applied
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );
          await delegatedVoteRef.set(delegatedVote.toJson());
        } else {
          // If delegator already has a vote (e.g. direct or another delegation took precedence),
          // we might log this or have specific rules. For now, we don't override.
          print('Delegator $delegatorId already has a vote for proposal $proposalId. Delegated vote from $userId not applied.');
        }
      }
    }
  }

  /// Retrieves all votes for a given session (proposal).
  Future<List<VoteModel>> getVotesForSession(String proposalId) async {
    try {
      final snapshot = await _firestore
          .collection('votes')
          .where('proposalId', isEqualTo: proposalId)
          .get();
      return snapshot.docs.map((doc) {
        try {
          return VoteModel.fromJson({
            'id': doc.id,
            ...doc.data(),
          });
        } catch (e) {
          print('Error parsing vote document ${doc.id}: $e');
          // Return a default/placeholder vote model or handle error appropriately
          return VoteModel(
            id: doc.id,
            userId: doc.data()['userId'] as String? ?? 'unknown',
            proposalId: proposalId,
            choice: doc.data()['choice'] ?? 'invalid',
            isDelegated: doc.data()['isDelegated'] as bool? ?? false,
            weight: doc.data()['weight'] as double? ?? 1.0, // Default weight
            createdAt: DateTime.now(), // Placeholder
            updatedAt: DateTime.now(), // Placeholder
          );
        }
      }).toList();
    } catch (e) {
      print('Error getting votes for session $proposalId: $e');
      rethrow;
    }
  }

  /// Gets the results of a voting session (proposal).
  Future<Map<String, dynamic>> getVoteResults(String proposalId) async {
    try {
      final session = await getVoteSessionByProposal(proposalId);
      if (session == null) {
        throw Exception('Vote session not found');
      }

      final votes = await getVotesForSession(proposalId);
      final voteData = votes
          .map((vote) => {
                'userId': vote.userId,
                'choice': vote.choice,
                'isDelegated': vote.isDelegated,
                'weight': vote.weight,
              })
          .toList();

      // Count votes by choice
      Map<String, double> counts = {};
      for (var vote in votes) {
        if (vote.choice is String) {
          final choice = vote.choice as String;
          counts[choice] = (counts[choice] ?? 0) + vote.weight;
        }
      }

      return {
        'method': session.method.toString().split('.').last,
        'votes': voteData,
        'counts': counts,
        'total': votes.fold(0.0, (total, vote) => total + vote.weight),
      };
    } catch (e) {
      print('Error getting vote results: $e');
      rethrow;
    }
  }

  // Check if user has voted in a session
  Future<bool> hasUserVoted(String proposalId) async {
    try {
      final userId = currentUserId;
      if (userId == null) throw Exception('User not authenticated');

      final snapshot = await _firestore
          .collection('votes')
          .where('userId', isEqualTo: userId)
          .where('proposalId', isEqualTo: proposalId)
          .limit(1)
          .get();

      return snapshot.docs.isNotEmpty;
    } catch (e) {
      print('Error checking if user voted: $e');
      rethrow;
    }
  }

  // DELEGATIONS
  // Create a delegation
  Future<DelegationModel> createDelegation(
      String delegateeId, DateTime validUntil,
      [String? topicId]) async {
    try {
      final delegatorId = currentUserId;
      if (delegatorId == null) throw Exception('User not authenticated');

      final docRef = _firestore.collection('delegations').doc();

      final delegation = DelegationModel(
        id: docRef.id,
        delegatorId: delegatorId,
        delegateeId: delegateeId,
        active: true,
        topicId: topicId,
        validUntil: validUntil,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await docRef.set(delegation.toJson());

      // Update user's delegations array
      await _firestore.collection('users').doc(delegatorId).update({
        'delegations': FieldValue.arrayUnion([delegateeId]),
        'updatedAt': _isTestMode ? DateTime.now() : FieldValue.serverTimestamp(),
      });

      return delegation;
    } catch (e) {
      print('Error creating delegation: $e');
      rethrow;
    }
  }

  // Get delegations by delegator
  Future<List<DelegationModel>> getDelegationsByDelegator() async {
    try {
      final delegatorId = currentUserId;
      if (delegatorId == null) throw Exception('User not authenticated');

      final snapshot = await _firestore
          .collection('delegations')
          .where('delegatorId', isEqualTo: delegatorId)
          .get();

      return snapshot.docs
          .map((doc) => DelegationModel.fromJson({
                'id': doc.id,
                ...doc.data(),
              }))
          .toList();
    } catch (e) {
      print('Error getting delegations: $e');
      rethrow;
    }
  }

  // Revoke a delegation
  Future<void> revokeDelegation(String delegationId) async {
    try {
      final delegatorId = currentUserId;
      if (delegatorId == null) throw Exception('User not authenticated');

      // Get the delegation to find the delegatee
      final doc =
          await _firestore.collection('delegations').doc(delegationId).get();
      if (!doc.exists) throw Exception('Delegation not found');

      final delegateeId = doc.data()!['delegateeId'] as String;

      // Update the delegation status
      await _firestore.collection('delegations').doc(delegationId).update({
        'active': false,
        'updatedAt': _isTestMode ? DateTime.now() : FieldValue.serverTimestamp(),
      });

      // Remove from user's delegations array
      await _firestore.collection('users').doc(delegatorId).update({
        'delegations': FieldValue.arrayRemove([delegateeId]),
        'updatedAt': _isTestMode ? DateTime.now() : FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error revoking delegation: $e');
      rethrow;
    }
  }

  // COMMENTS
  // Add a comment to a proposal
  Future<CommentModel> addComment(String proposalId, String content) async {
    try {
      final authorId = currentUserId;
      if (authorId == null) throw Exception('User not authenticated');

      final docRef = _firestore.collection('comments').doc();

      final comment = CommentModel(
        id: docRef.id,
        proposalId: proposalId,
        authorId: authorId,
        content: content,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await docRef.set(comment.toJson());
      return comment;
    } catch (e) {
      print('Error adding comment: $e');
      rethrow;
    }
  }

  // Get comments for a proposal
  Future<List<CommentModel>> getCommentsForProposal(String proposalId) async {
    try {
      final snapshot = await _firestore
          .collection('comments')
          .where('proposalId', isEqualTo: proposalId)
          .orderBy('createdAt')
          .get();

      return snapshot.docs
          .map((doc) => CommentModel.fromJson({
                'id': doc.id,
                ...doc.data(),
              }))
          .toList();
    } catch (e) {
      print('Error getting comments: $e');
      rethrow;
    }
  }

  // GROUPS
  // Create a group (admin only)
  Future<GroupModel> createGroup(String name, List<String> memberIds,
      [String? description]) async {
    try {
      final docRef = _firestore.collection('groups').doc();

      final group = GroupModel(
        id: docRef.id,
        name: name,
        memberIds: memberIds,
        description: description,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await docRef.set(group.toJson());
      return group;
    } catch (e) {
      print('Error creating group: $e');
      rethrow;
    }
  }

  // Get all groups
  Future<List<GroupModel>> getAllGroups() async {
    try {
      final snapshot = await _firestore.collection('groups').get();

      return snapshot.docs
          .map((doc) => GroupModel.fromJson({
                'id': doc.id,
                ...doc.data(),
              }))
          .toList();
    } catch (e) {
      print('Error getting groups: $e');
      rethrow;
    }
  }

  // Add user to group
  Future<void> addUserToGroup(String groupId, String userId) async {
    try {
      await _firestore.collection('groups').doc(groupId).update({
        'memberIds': FieldValue.arrayUnion([userId]),
        'updatedAt': _isTestMode ? DateTime.now() : FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error adding user to group: $e');
      rethrow;
    }
  }

  // Remove user from group
  Future<void> removeUserFromGroup(String groupId, String userId) async {
    try {
      await _firestore.collection('groups').doc(groupId).update({
        'memberIds': FieldValue.arrayRemove([userId]),
        'updatedAt': _isTestMode ? DateTime.now() : FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error removing user from group: $e');
      rethrow;
    }
  }

  // Get groups for a user
  Future<List<GroupModel>> getGroupsForUser(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('groups')
          .where('memberIds', arrayContains: userId)
          .get();

      return snapshot.docs
          .map((doc) => GroupModel.fromJson({
                'id': doc.id,
                ...doc.data(),
              }))
          .toList();
    } catch (e) {
      print('Error getting groups for user: $e');
      rethrow;
    }
  }

  // Get all users
  Future<List<UserModel>> getAllUsers() async {
    try {
      final snapshot = await _firestore.collection('users').get();
      return snapshot.docs.map((doc) {
        try {
          return UserModel.fromJson({
            'id': doc.id,
            ...(doc.data()),
          });
        } catch (e) {
          print('Error parsing user document ${doc.id}: $e');
          // Return a default/placeholder user model or handle error appropriately
          // For now, rethrowing to ensure issues are visible during development
          rethrow;
        }
      }).toList();
    } catch (e) {
      print('Error getting all users: $e');
      rethrow;
    }
  }
}
