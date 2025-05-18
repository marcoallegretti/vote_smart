import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:logger/logger.dart';
import '../models/data_models.dart';
import '../models/audit_model.dart';
import './audit_service.dart';
import './database_service.dart';

// Models for delegation system
class DelegationNode {
  final UserModel user;
  int depth;
  final List<DelegationModel> delegatedFrom;
  DelegationModel? delegatedTo;

  DelegationNode({
    required this.user,
    required this.depth,
    required this.delegatedFrom,
    this.delegatedTo,
  });
}

class PropagatedVote {
  final String userId;
  final String proposalId;
  final String? topicId;
  final String vote; // This is the choice string
  final bool originalVoter;
  final String originalVoterId;
  final double weight;
  final double effectiveWeight;
  final DelegationModel? delegatedVia;
  final List<String> delegationPath;
  final Timestamp timestamp;
  final bool isDirectVote;

  PropagatedVote({
    required this.userId,
    required this.proposalId,
    this.topicId,
    required this.vote,
    required this.originalVoter,
    required this.originalVoterId,
    required this.weight,
    required this.effectiveWeight,
    this.delegatedVia,
    required this.delegationPath,
    required this.timestamp,
    required this.isDirectVote,
  });

  Map<String, dynamic> toJson({double? effectiveWeightOverride}) {
    return {
      'userId': userId,
      'proposalId': proposalId,
      'topicId': topicId,
      'vote': vote,
      'originalVoter': originalVoter,
      'originalVoterId': originalVoterId,
      'weight': weight, // Intrinsic weight of this specific vote instance
      'effectiveWeight': effectiveWeightOverride ??
          effectiveWeight, // Use override if provided
      'delegatedVia':
          delegatedVia?.toJson(), // Assuming DelegationModel has toJson
      'delegationPath': delegationPath,
      'timestamp': timestamp
          .toDate()
          .toIso8601String(), // Or FieldValue.serverTimestamp() if writing to Firestore directly
      'isDirectVote': isDirectVote,
    };
  }
}

class WeightedPropagatedVote {
  final PropagatedVote vote;
  final double effectiveWeight;

  WeightedPropagatedVote(this.vote, this.effectiveWeight);
}

class DelegationService {
  final FirebaseFirestore _firestore;
  final Logger _logger = Logger();
  final AuditService _auditService;
  final DatabaseService _databaseService;
  static const int _maxDepth = 10;

  DelegationService({
    required FirebaseFirestore firestore,
    required AuditService auditService,
    required DatabaseService databaseService,
  })  : _firestore = firestore,
        _auditService = auditService,
        _databaseService = databaseService;

  // Static method for testing convenience
  static DelegationService withInstance({
    required FirebaseFirestore firestoreInstance,
    required AuditService auditService,
    required DatabaseService databaseService,
  }) {
    return DelegationService(
      firestore: firestoreInstance,
      auditService: auditService,
      databaseService: databaseService,
    );
  }

  String? get currentUserId => _databaseService.currentUserId;

  Future<List<DelegationInfo>> getMyDelegations({String? topicId}) async {
    final String? uId = currentUserId;
    if (uId == null) {
      _logger.w('User not logged in. Cannot fetch their delegations.');
      return [];
    }

    try {
      _logger.i('Fetching delegations made by user $uId (topic: $topicId).');
      // getDelegationsByDelegator in DatabaseService fetches for the current user and does not take userId or topicId
      List<DelegationModel> allDelegations =
          await _databaseService.getDelegationsByDelegator();

      // Filter by topicId if provided
      if (topicId != null) {
        allDelegations =
            allDelegations.where((d) => d.topicId == topicId).toList();
      }

      if (allDelegations.isEmpty) {
        _logger.i('No delegations found for user $uId (topic: $topicId).');
        return [];
      }

      List<DelegationInfo> delegationInfos = [];

      // Fetch delegator user model (current user)
      final delegatorDoc = await _firestore.collection('users').doc(uId).get();
      if (!delegatorDoc.exists) {
        _logger.e(
            'Could not fetch UserModel for current user $uId. Aborting getMyDelegations.');
        return [];
      }
      final UserModel delegatorUser = UserModel.fromJson(delegatorDoc.data()!);

      for (var delegation in allDelegations) {
        // Fetch delegatee user model
        final delegateeDoc = await _firestore
            .collection('users')
            .doc(delegation.delegateeId)
            .get();
        if (delegateeDoc.exists) {
          final UserModel delegateeUser =
              UserModel.fromJson(delegateeDoc.data()!);
          delegationInfos.add(DelegationInfo(
            delegation: delegation,
            delegatorUser:
                delegatorUser, // Current user is always the delegator here
            delegateeUser: delegateeUser,
          ));
        } else {
          _logger.w(
              'Could not fetch UserModel for delegatee ${delegation.delegateeId} for delegation ${delegation.id}. Skipping this delegation.');
        }
      }
      _logger.i(
          'Successfully fetched ${delegationInfos.length} delegation(s) for user $uId (topic: $topicId).');
      return delegationInfos;
    } catch (e, stacktrace) {
      _logger.e(
          'Error fetching delegations for user $uId (topic: $topicId): $e',
          error: e,
          stackTrace: stacktrace);
      return [];
    }
  }

  /// Fetches all active delegations where the current user is the delegatee.
  /// Optionally filters by topicId.
  Future<List<DelegationInfo>> getDelegationsToMe({String? topicId}) async {
    final String? uId = currentUserId;
    if (uId == null) {
      _logger.w('User not logged in. Cannot fetch delegations to them.');
      return [];
    }

    try {
      _logger.i('Fetching delegations to user $uId (topic: $topicId).');
      QuerySnapshot delegationSnapshot = await _firestore
          .collection('delegations')
          .where('delegateeId', isEqualTo: uId)
          .where('active', isEqualTo: true)
          .get();

      List<DelegationModel> delegationsToMe = delegationSnapshot.docs
          .map((doc) => DelegationModel.fromJson({
                'id': doc.id,
                ...(doc.data()! as Map<String, dynamic>),
              }))
          .toList();

      // Filter by topicId if provided
      if (topicId != null) {
        delegationsToMe =
            delegationsToMe.where((d) => d.topicId == topicId).toList();
      }

      if (delegationsToMe.isEmpty) {
        _logger.i('No delegations found to user $uId (topic: $topicId).');
        return [];
      }

      List<DelegationInfo> delegationInfos = [];

      // Fetch delegatee user model (current user)
      final delegateeDoc = await _firestore.collection('users').doc(uId).get();
      if (!delegateeDoc.exists) {
        _logger.e(
            'Could not fetch UserModel for current user (delegatee) $uId. Aborting getDelegationsToMe.');
        return [];
      }
      final UserModel delegateeUser = UserModel.fromJson(delegateeDoc.data()!);

      for (var delegation in delegationsToMe) {
        // Fetch delegator user model
        final delegatorDoc = await _firestore
            .collection('users')
            .doc(delegation.delegatorId)
            .get();
        if (delegatorDoc.exists) {
          final UserModel delegatorUser =
              UserModel.fromJson(delegatorDoc.data()!);
          delegationInfos.add(DelegationInfo(
            delegation: delegation,
            delegatorUser: delegatorUser,
            delegateeUser:
                delegateeUser, // Current user is always the delegatee here
          ));
        } else {
          _logger.w(
              'Could not fetch UserModel for delegator ${delegation.delegatorId} for delegation ${delegation.id}. Skipping this delegation.');
        }
      }
      _logger.i(
          'Successfully fetched ${delegationInfos.length} delegation(s) to user $uId (topic: $topicId).');
      return delegationInfos;
    } catch (e, stacktrace) {
      _logger.e('Error fetching delegations to user $uId (topic: $topicId): $e',
          error: e, stackTrace: stacktrace);
      return [];
    }
  }

  Future<bool> hasActiveDelegation({String? topicId}) async {
    final String? uId = currentUserId;
    if (uId == null) {
      _logger.w('User not logged in, cannot check for active delegations.');
      return false;
    }

    try {
      Query query = _firestore
          .collection('delegations')
          .where('delegatorId', isEqualTo: uId)
          .where('status', isEqualTo: 'active')
          .limit(1);

      if (topicId != null) {
        query = query.where('topicId', isEqualTo: topicId);
      } else {
        // If no topicId is specified, check for general delegations (topicId is null)
        query = query.where('topicId', isNull: true);
      }

      final snapshot = await query.get();
      final bool hasDelegation = snapshot.docs.isNotEmpty;

      if (hasDelegation) {
        _logger.i('User $uId has active delegation (topic: $topicId).');
      } else {
        _logger.i('User $uId has no active delegation (topic: $topicId).');
      }
      return hasDelegation;
    } catch (e, stacktrace) {
      _logger.e(
          'Error checking active delegation for user $uId, topic $topicId',
          error: e,
          stackTrace: stacktrace);
      return false;
    }
  }

  // Propagate a vote through delegation chains, considering weights
  Future<WeightedPropagatedVote?> propagateVote(
    String initialVoterId,
    String proposalId,
    Map<String, VoteModel> allVotesMap,
    Map<String, List<DelegationModel>> allDelegationsMap,
    String initialVoteChoice,
    double initialVoteWeight,
    String? topicId,
  ) async {
    _logger.d(
        'Starting propagateVote for initialVoterId: $initialVoterId, proposalId: $proposalId, topicId: $topicId, choice: $initialVoteChoice, weight: $initialVoteWeight');

    // allVotesMap and allDelegationsMap are assumed to be pre-fetched by the caller (e.g., VotingService).

    // Call the helper function to perform the recursive propagation.
    return _propagateVoteHelper(
      initialVoterId,
      initialVoterId,
      proposalId,
      topicId,
      allVotesMap,
      allDelegationsMap,
      1.0,
      [initialVoterId],
      0,
      initialVoteChoice,
      initialVoteWeight,
    );
  }

  Future<WeightedPropagatedVote?> _propagateVoteHelper(
    String currentUserId,
    String initialVoterId,
    String proposalId,
    String? topicId,
    Map<String, VoteModel> allVotesMap,
    Map<String, List<DelegationModel>> allDelegationsMap,
    double currentWeightMultiplier,
    List<String> currentPath,
    int depth,
    String initialVoteChoiceForPropagation,
    double initialVoteWeightForPropagation,
  ) async {
    _logger.d(
        '[ENTER _propagateVoteHelper for $currentUserId (initial: $initialVoterId)] currentPath: $currentPath, depth: $depth, multiplier: $currentWeightMultiplier');

    if (depth > _maxDepth) {
      _logger.w(
          'Maximum recursion depth reached for $currentUserId (initial: $initialVoterId).');
      return null;
    }

    WeightedPropagatedVote? bestWeightedVoteSoFar;

    // Prefer direct vote from allVotesMap if available and matches proposalId
    VoteModel? directVoteModel = allVotesMap[currentUserId];
    if (directVoteModel != null && directVoteModel.proposalId != proposalId) {
      // Ignore vote if it's for a different proposal
      directVoteModel = null;
    }
    _logger.d(
        '[TRACE] Before _getDirectVote for $currentUserId (initialVoterId: $initialVoterId)');
    directVoteModel ??= await _getDirectVote(proposalId, currentUserId);
    _logger.d(
        '[TRACE] After _getDirectVote for $currentUserId: directVoteModel is null: ${directVoteModel == null} (initialVoterId: $initialVoterId)');
    if (directVoteModel != null) {
      _logger.d(
          '[TRACE] directVoteModel FOUND for $currentUserId: ${directVoteModel.choice} (initialVoterId: $initialVoterId)');
    }

    if (directVoteModel != null) {
      _logger.i(
          'User $currentUserId has a direct vote: ${directVoteModel.choice} for $proposalId with weight ${directVoteModel.weight}');
      // For direct votes, the userId should be the user who cast the direct vote (currentUserId)
      final directPropVote = PropagatedVote(
        userId:
            currentUserId, // For direct votes, this is correct - the vote stays with the user who cast it
        proposalId: proposalId,
        topicId: topicId,
        vote: directVoteModel.choice,
        originalVoter: true,
        originalVoterId: currentUserId,
        weight: directVoteModel.weight,
        effectiveWeight: directVoteModel.weight * currentWeightMultiplier,
        delegatedVia: null,
        delegationPath: [currentUserId],
        timestamp: Timestamp.now(),
        isDirectVote: true,
      );
      bestWeightedVoteSoFar = WeightedPropagatedVote(
          directPropVote, directPropVote.effectiveWeight);
      _logger.d(
          '[TRACE] bestWeightedVoteSoFar created from direct vote for $currentUserId. delegatedVia: ${bestWeightedVoteSoFar.vote.delegatedVia}, effectiveWeight: ${bestWeightedVoteSoFar.vote.effectiveWeight}, vote: ${bestWeightedVoteSoFar.vote.vote} (initialVoterId: $initialVoterId)');

      _logger.i('[DEBUG CHECK] Before direct vote check for initial voter: '
          'currentUserId: $currentUserId, initialVoterId: $initialVoterId, '
          'directVoteModel choice: ${directVoteModel.choice}');

      _logger.d(
          '[TRACE] PRE-CONDITION CHECK for $currentUserId: initialVoterId is $initialVoterId. Are they equal? ${currentUserId == initialVoterId}');
      // If currentUserId is the one we're resolving the vote for initially (initialVoterId),
      // their direct vote is definitive for them.
      if (currentUserId == initialVoterId) {
        _logger.i(
            '[SUCCESS PATH] Condition currentUserId == initialVoterId TRUE for $currentUserId. Returning direct vote.');
        // Ensure to remove from processedUsers if we return early,
        // so other paths can still process this user if they are part of another delegation chain.
        return bestWeightedVoteSoFar;
      } else {
        _logger.d(
            '[TRACE] Condition currentUserId == initialVoterId FALSE for $currentUserId (initial: $initialVoterId). Proceeding to check delegations for $currentUserId.');
      }
    }

    _logger.d(
        '[BEFORE DELEGATION LOOP for $currentUserId (initial: $initialVoterId)] currentPath: $currentPath, delegations to explore: ');

    final delegations = allDelegationsMap[currentUserId] ?? [];

    _logger.d(
        '[BEFORE DELEGATION LOOP for $currentUserId (initial: $initialVoterId)] currentPath: $currentPath, delegations to explore: ${delegations.length}');

    for (final delegation in delegations) {
      _logger.d(
          '[LOOP START for $currentUserId -> ${delegation.delegateeId}] currentPath: $currentPath');

      // Topic filtering for the delegation itself
      if (topicId != null &&
          delegation.topicId != null &&
          delegation.topicId != topicId) {
        _logger.i(
            'Skipping delegation ${delegation.id} from $currentUserId to ${delegation.delegateeId} due to topic mismatch (proposal: $topicId, delegation: ${delegation.topicId})');
        continue;
      }

      final List<String> pathForRecursiveCall = List.from(currentPath)
        ..add(delegation.delegateeId);

      if (currentPath.contains(delegation.delegateeId)) {
        _logger.w(
            'Cycle detected: ${delegation.delegateeId} is already in currentPath $currentPath. Skipping delegation to ${delegation.delegateeId}. Path for next level would have been $pathForRecursiveCall');
        continue;
      }

      _logger.d(
          '[PRE-AWAIT for $currentUserId -> ${delegation.delegateeId}] currentPath: $currentPath, pathForRecursiveCall: $pathForRecursiveCall');
      final delegateeResult = await _propagateVoteHelper(
        delegation.delegateeId,
        initialVoterId,
        proposalId,
        topicId,
        allVotesMap,
        allDelegationsMap,
        currentWeightMultiplier * delegation.weight,
        pathForRecursiveCall,
        depth + 1,
        initialVoteChoiceForPropagation,
        initialVoteWeightForPropagation,
      );
      _logger.d(
          '[POST-AWAIT for $currentUserId -> ${delegation.delegateeId}] currentPath: $currentPath');

      if (delegateeResult != null) {
        _logger.d(
            '[PATH CHECK FOR $currentUserId from ${delegation.delegateeId}] Delegatee path: ${delegateeResult.vote.delegationPath}, Delegatee originalVoterId: ${delegateeResult.vote.originalVoterId}');
        final double effectiveWeightFromDelegatee =
            delegateeResult.effectiveWeight;
        _logger.i(
            '[EFFECTIVE WEIGHT] Vote from delegatee ${delegation.delegateeId} for $currentUserId has effective weight $effectiveWeightFromDelegatee (delegation weight ${delegation.weight} * delegatee path eff. weight ${delegateeResult.effectiveWeight / delegation.weight})');

        // Only consider this delegate's vote if it's better than what we have so far
        if (bestWeightedVoteSoFar == null ||
            effectiveWeightFromDelegatee >
                bestWeightedVoteSoFar.effectiveWeight) {
          _logger.d(
              '[COMBINE CHECK for $currentUserId from ${delegation.delegateeId} - qualified delegate vote] currentPath: $currentPath, delegateePath: ${delegateeResult.vote.delegationPath}');

          final List<String> newDelegatedVotePath =
              delegateeResult.vote.delegationPath;

          // In the delegation chain, the vote should be attributed to the userId from the delegateeResult,
          // which represents the user who ultimately cast the vote or where the vote landed.
          final newPropagatedVote = PropagatedVote(
            userId: delegateeResult
                .vote.userId, // CHANGED from delegation.delegateeId
            proposalId: delegateeResult.vote.proposalId,
            topicId: delegateeResult.vote.topicId,
            vote: delegateeResult.vote.vote,
            originalVoter: false,
            originalVoterId: delegateeResult.vote.originalVoterId,
            weight: delegateeResult.vote.weight,
            effectiveWeight: effectiveWeightFromDelegatee,
            delegatedVia: delegation,
            delegationPath: newDelegatedVotePath, // CHANGED
            timestamp: delegateeResult.vote.timestamp,
            isDirectVote: delegateeResult.vote.isDirectVote,
          );
          bestWeightedVoteSoFar = WeightedPropagatedVote(
              newPropagatedVote, effectiveWeightFromDelegatee);
          _logger.i(
              'Updating best vote for $currentUserId based on ${delegation.delegateeId}\'s vote. New effective weight: $effectiveWeightFromDelegatee, Choice: ${newPropagatedVote.vote}, Final UserId: ${newPropagatedVote.userId}');
        }
      }
    }

    // If, after all checks, currentUserId is the initialVoterId, they have no direct vote model,
    // and no better weighted vote was found through their delegations, then their original vote (being propagated)
    // is considered the effective vote for this path.
    if (currentUserId == initialVoterId &&
        bestWeightedVoteSoFar == null &&
        directVoteModel == null) {
      _logger.i(
          'User $currentUserId (initial voter, no direct vote model and no delegation found) is effectively casting their original vote: $initialVoteChoiceForPropagation with weight $initialVoteWeightForPropagation');
      // For the initial vote when no delegations or direct votes exist, the vote stays with the initial voter
      final initialPropVote = PropagatedVote(
        userId:
            currentUserId, // The initial voter casts their own vote when no delegations or direct votes exist
        proposalId: proposalId,
        topicId: topicId,
        vote: initialVoteChoiceForPropagation,
        originalVoter: true,
        originalVoterId: currentUserId,
        weight: initialVoteWeightForPropagation,
        effectiveWeight:
            initialVoteWeightForPropagation * currentWeightMultiplier,
        delegatedVia: null,
        delegationPath: List.from(currentPath),
        timestamp: Timestamp.now(),
        isDirectVote: true,
      );
      // The weight multiplier for this initial vote is the one accumulated up to initialVoterId (which is 1.0 if this is the start).
      bestWeightedVoteSoFar = WeightedPropagatedVote(
          initialPropVote, initialPropVote.effectiveWeight);
      _logger.d(
          '[INITIAL VOTE CAST by $currentUserId] Path: ${initialPropVote.delegationPath}, Vote: ${initialPropVote.vote}, Effective Weight: ${bestWeightedVoteSoFar.effectiveWeight}');
    }
    // NEW BLOCK: If currentUserId is NOT the initial voter, has no direct vote,
    // and no delegations panned out (bestWeightedVoteSoFar is still null),
    // it means they are the end of the line for initialVoterId's vote.
    else if (currentUserId != initialVoterId &&
        bestWeightedVoteSoFar == null &&
        directVoteModel == null) {
      _logger.i(
          'User $currentUserId is end of delegation chain for $initialVoterId\'s vote ($initialVoteChoiceForPropagation). Effective multiplier: $currentWeightMultiplier');
      final endOfChainVote = PropagatedVote(
        userId: currentUserId, // Vote lands on currentUserId
        proposalId: proposalId,
        topicId: topicId,
        vote: initialVoteChoiceForPropagation, // Use the initial voter's choice
        originalVoter: false, // It's not currentUserId's original vote
        originalVoterId:
            initialVoterId, // The vote originated from initialVoterId
        weight:
            initialVoteWeightForPropagation, // Use the initial voter's original weight
        effectiveWeight: initialVoteWeightForPropagation *
            currentWeightMultiplier, // Multiplied by the path
        delegatedVia:
            null, // This specific user didn't delegate it further from themselves
        delegationPath: List.from(currentPath), // The full path to this user
        timestamp: Timestamp.now(),
        isDirectVote: false, // It's not a direct vote by currentUserId
      );
      bestWeightedVoteSoFar = WeightedPropagatedVote(
          endOfChainVote, endOfChainVote.effectiveWeight);
      _logger.d(
          '[END OF CHAIN for $initialVoterId\'s vote at $currentUserId] Path: ${endOfChainVote.delegationPath}, Vote: ${endOfChainVote.vote}, Effective Weight: ${bestWeightedVoteSoFar.effectiveWeight}, OriginalVoterID: ${endOfChainVote.originalVoterId}');
    }

    if (bestWeightedVoteSoFar == null) {
      _logger.i(
          'No vote determined for $currentUserId for $proposalId in this path. This might be an issue if not intended.');
    }
    return bestWeightedVoteSoFar;
  }

  Future<Map<String, DelegationNode>> getDelegationGraph(
      String rootUserId) async {
    final Map<String, DelegationNode> graphNodes = {};
    final Map<String, UserModel> usersMap = {};

    try {
      // 1. Fetch all users
      final usersSnapshot = await _firestore.collection('users').get();
      for (var doc in usersSnapshot.docs) {
        final user = UserModel.fromJson({'id': doc.id, ...doc.data()});
        usersMap[user.id] = user;
        // Initialize DelegationNode for each user
        graphNodes[user.id] = DelegationNode(
          user: user,
          depth: -1, // Initialize depth, will be calculated later
          delegatedFrom: [],
          delegatedTo: null,
        );
      }

      // 2. Fetch ALL delegations (including expired ones)
      final delegationsSnapshot = await _firestore
          .collection('delegations')
          .get();
      final List<DelegationModel> allDelegations = delegationsSnapshot
          .docs
          .map((doc) => DelegationModel.fromJson({'id': doc.id, ...doc.data()}))
          .toList();
      
      _logger.i('Found ${allDelegations.length} total delegations');

      // 3. Populate delegatedFrom and delegatedTo for each node
      for (final delegation in allDelegations) {
        // Populate delegatedFrom for the delegatee
        if (graphNodes.containsKey(delegation.delegateeId)) {
          graphNodes[delegation.delegateeId]!.delegatedFrom.add(delegation);
        }

        // Populate delegatedTo for the delegator
        // For general delegations or topic-specific ones if no general delegation exists
        if (graphNodes.containsKey(delegation.delegatorId)) {
          // If no delegation is set yet, use this one
          if (graphNodes[delegation.delegatorId]!.delegatedTo == null) {
            graphNodes[delegation.delegatorId]!.delegatedTo = delegation;
          } 
          // If a topic-specific delegation exists but a general one is found, prefer the general one
          else if (graphNodes[delegation.delegatorId]!.delegatedTo!.topicId != null && 
                   delegation.topicId == null) {
            graphNodes[delegation.delegatorId]!.delegatedTo = delegation;
          }
        }
      }

      // 4. Build a more comprehensive graph by including both incoming and outgoing delegations
      // This ensures we see all connections to/from the root user
      Set<String> connectedUsers = {rootUserId};
      List<String> queue = [rootUserId];
      int head = 0;
      
      // First pass: find all users connected to root (both directions)
      while (head < queue.length) {
        final currentUserId = queue[head++];
        final currentNode = graphNodes[currentUserId];
        
        if (currentNode == null) continue;
        
        // Add users who delegated to current user
        for (final delegation in currentNode.delegatedFrom) {
          if (!connectedUsers.contains(delegation.delegatorId)) {
            connectedUsers.add(delegation.delegatorId);
            queue.add(delegation.delegatorId);
          }
        }
        
        // Add user that current user delegated to
        if (currentNode.delegatedTo != null) {
          final delegateeId = currentNode.delegatedTo!.delegateeId;
          if (!connectedUsers.contains(delegateeId)) {
            connectedUsers.add(delegateeId);
            queue.add(delegateeId);
          }
        }
      }
      
      // Filter graph to only include connected users
      final Map<String, DelegationNode> connectedGraph = {};
      for (final userId in connectedUsers) {
        if (graphNodes.containsKey(userId)) {
          connectedGraph[userId] = graphNodes[userId]!;
        }
      }

      // 5. Calculate depths using BFS from rootUserId
      if (connectedGraph.containsKey(rootUserId)) {
        final List<String> depthQueue = [rootUserId];
        connectedGraph[rootUserId]!.depth = 0;
        int depthHead = 0;

        while (depthHead < depthQueue.length) {
          final currentUserId = depthQueue[depthHead++];
          final currentNode = connectedGraph[currentUserId]!;

          // Set depth for users who delegated to current user (incoming)
          for (final delegation in currentNode.delegatedFrom) {
            final delegatorId = delegation.delegatorId;
            if (connectedGraph.containsKey(delegatorId) &&
                connectedGraph[delegatorId]!.depth == -1) {
              connectedGraph[delegatorId]!.depth = currentNode.depth + 1;
              depthQueue.add(delegatorId);
            }
          }
          
          // Set depth for user that current user delegated to (outgoing)
          if (currentNode.delegatedTo != null) {
            final delegateeId = currentNode.delegatedTo!.delegateeId;
            if (connectedGraph.containsKey(delegateeId) &&
                connectedGraph[delegateeId]!.depth == -1) {
              connectedGraph[delegateeId]!.depth = currentNode.depth + 1;
              depthQueue.add(delegateeId);
            }
          }
        }
      }
      
      _logger.i('Delegation graph constructed with ${connectedGraph.length} nodes out of ${graphNodes.length} total users.');
      return connectedGraph;
    } catch (e, stacktrace) {
      _logger.e('Error constructing delegation graph for $rootUserId',
          error: e, stackTrace: stacktrace);
      return {}; // Return empty graph on error
    }
  }

  Future<double> calculateRepresentedVoterCount(String targetUserId,
      {String? topicId}) async {
    final Set<String> representedVoters = {targetUserId};
    final List<String> queue = [targetUserId];
    int head = 0;

    try {
      // Fetch all active delegations once
      final querySnapshot = await _firestore
          .collection('delegations')
          .where('status', isEqualTo: 'active')
          .get();

      final allActiveDelegations = querySnapshot.docs
          .map((doc) => DelegationModel.fromJson({'id': doc.id, ...doc.data()}))
          .toList();

      while (head < queue.length) {
        final currentProcessingUserId = queue[head++];

        // Find delegations TO the currentProcessingUserId
        for (final delegation in allActiveDelegations) {
          if (delegation.delegateeId == currentProcessingUserId) {
            // Topic filtering logic:
            // A delegation applies if:
            // 1. The method is called for a specific topic AND the delegation is for that specific topic.
            // 2. The method is called for a specific topic AND the delegation is general (topicId is null).
            // 3. The method is called without a specific topic (general count) AND the delegation is general.
            // (A specific-topic delegation should not count for a general count, unless we define general to include all specifics)
            // For simplicity here: if topicId is specified for method, delegation must match it or be general.
            // If topicId is NOT specified for method, only general delegations to currentProcessingUserId count.

            bool topicMatch = false;
            if (topicId != null) {
              // Method called for a specific topic
              if (delegation.topicId == topicId || delegation.topicId == null) {
                topicMatch = true;
              }
            } else {
              // Method called for a general count
              if (delegation.topicId == null) {
                topicMatch = true;
              }
            }

            if (topicMatch) {
              if (!representedVoters.contains(delegation.delegatorId)) {
                representedVoters.add(delegation.delegatorId);
                queue.add(delegation.delegatorId);
              }
            }
          }
        }
      }
      _logger.i(
          'User $targetUserId represents ${representedVoters.length} voters for topic $topicId.');
      return representedVoters.length.toDouble();
    } catch (e, stacktrace) {
      _logger.e(
          'Error calculating represented voter count for $targetUserId, topic $topicId',
          error: e,
          stackTrace: stacktrace);
      return 1.0; // Return 1.0 (self) on error
    }
  }

  Future<void> createDelegation({
    required String delegateeId,
    String? topicId,
    required DateTime validUntil,
    double weight = 1.0,
  }) async {
    try {
      final userId = _databaseService.currentUserId;
      if (userId == null) throw Exception('User not authenticated');

      // Check if delegation already exists
      final existingDelegation = await _getDelegationBetweenUsers(
        delegatorId: userId,
        delegateeId: delegateeId,
        topicId: topicId,
      );

      if (existingDelegation != null) {
        throw Exception('Delegation already exists');
      }

      final docRef = _firestore.collection('delegations').doc();
      final now = DateTime.now();

      final delegation = DelegationModel(
        id: docRef.id,
        delegatorId: userId,
        delegateeId: delegateeId,
        active: true,
        topicId: topicId,
        weight: weight,
        validUntil: validUntil,
        createdAt: now,
        updatedAt: now,
      );

      await docRef.set(delegation.toJson());

      // Log audit event for delegation creation
      await _auditService.logAuditEvent(
        eventType: AuditEventType.DELEGATION_CREATED,
        actorUserId: userId,
        targetUserId: delegateeId,
        entityId: delegation.id,
        entityType: 'DELEGATION',
        details: {
          'topicId': topicId,
          'validUntil': validUntil.toIso8601String(),
          'weight': weight,
        },
      );

      // Update user's delegations list
      await _firestore.collection('users').doc(userId).update({
        'delegations': FieldValue.arrayUnion([docRef.id]),
      });

      return;
    } catch (e) {
      _logger.e('Error creating delegation', error: e);
      rethrow;
    }
  }

  /// Fetches a list of users to whom the current user can delegate their vote.
  /// This currently returns all users except the current user.
  Future<List<UserModel>> getPotentialDelegates() async {
    final String? uId = currentUserId;
    if (uId == null) {
      _logger.w('User not logged in. Cannot fetch potential delegates.');
      return [];
    }

    try {
      _logger.i(
          'Fetching all users to determine potential delegates for user $uId.');
      List<UserModel> allUsers = await _databaseService.getAllUsers();

      // Filter out the current user
      List<UserModel> potentialDelegates =
          allUsers.where((user) => user.id != uId).toList();

      _logger.i(
          'Found ${potentialDelegates.length} potential delegates for user $uId.');
      return potentialDelegates;
    } catch (e, stacktrace) {
      _logger.e('Error fetching potential delegates for user $uId: $e',
          error: e, stackTrace: stacktrace);
      return [];
    }
  }

  Future<bool> revokeDelegation(String delegationId) async {
    final String? uId = currentUserId;
    if (uId == null) {
      _logger.w('User not logged in. Cannot revoke delegation.');
      return false;
    }
    _logger.i('Attempting to revoke delegation $delegationId by user $uId.');
    try {
      // Fetch the delegation to ensure it exists and belongs to the user (or has rights to revoke)
      final delegationDoc =
          await _firestore.collection('delegations').doc(delegationId).get();
      if (!delegationDoc.exists) {
        _logger.w('Delegation $delegationId not found for revocation.');
        return false;
      }
      DelegationModel delegation = DelegationModel.fromJson(
          {'id': delegationDoc.id, ...delegationDoc.data()!});

      if (delegation.delegatorId != uId) {
        _logger.w(
            'User $uId is not the delegator of delegation $delegationId. Revocation denied.');
        // Potentially allow admin revocation here if that's a feature
        return false;
      }

      // Update the delegation to be inactive
      await _firestore.collection('delegations').doc(delegationId).update({
        'active': false,
        'revokedTimestamp': FieldValue.serverTimestamp(),
        'updatedTimestamp': FieldValue.serverTimestamp(),
      });

      // Log the revocation audit event
      await _auditService.logAuditEvent(
        eventType: AuditEventType.DELEGATION_REVOKED,
        actorUserId: uId,
        entityId: delegationId,
        entityType: 'delegation',
        details: {
          'delegationId': delegationId,
          'delegatorId': delegation.delegatorId,
          'delegateeId': delegation.delegateeId,
          'topicId': delegation.topicId,
          'reason': 'User revoked delegation',
        },
      );
      _logger.i('Delegation $delegationId revoked successfully by user $uId.');
      return true;
    } catch (e, stacktrace) {
      _logger.e('Error revoking delegation $delegationId: $e',
          error: e, stackTrace: stacktrace);
      return false;
    }
  }

  /// Checks if creating a delegation from the current user to the specified delegatee would create a circular delegation.
  Future<bool> wouldCreateCircularDelegation(String delegateeId,
      {String? topicId}) async {
    final String? uId = currentUserId;
    if (uId == null) {
      _logger.w('User not logged in. Cannot check for circular delegation.');
      return true; // Prevent action if user unknown
    }

    _logger.d(
        'Checking for circular delegation: $uId -> $delegateeId (Topic: $topicId)');

    // A user cannot delegate to themselves.
    if (uId == delegateeId) {
      _logger.i(
          'User $uId cannot delegate to themselves. This is a direct cycle.');
      return true;
    }

    // Start recursive path search
    return await _checkCycleRecursive(uId, delegateeId, topicId, [uId], 0);
  }

  // Recursive helper for robust cycle detection
  Future<bool> _checkCycleRecursive(
      String originalUserId,
      String currentDelegatee,
      String? topicId,
      List<String> path,
      int depth) async {
    if (depth > _maxDepth) {
      _logger.w(
          'Reached max depth ($_maxDepth) checking for circular delegation. Assuming cycle to prevent infinite loops. Path: ${path.join(" -> ")}');
      return true; // Prevent infinite recursion
    }
    path = List<String>.from(path)..add(currentDelegatee);
    Query query = _firestore
        .collection('delegations')
        .where('delegatorId', isEqualTo: currentDelegatee)
        .where('active', isEqualTo: true);

    if (topicId != null) {
      // For topic-specific, follow both topic-specific and general delegations
      query = query.where('topicId', whereIn: [topicId, null]);
    } else {
      // For general, only follow general delegations
      query = query.where('topicId', isNull: true);
    }

    QuerySnapshot snapshot = await query.get();
    if (snapshot.docs.isEmpty) {
      _logger.d(
          'No further delegation from $currentDelegatee for topic $topicId. Path: ${path.join(" -> ")}. No cycle found.');
      return false;
    }
    for (var doc in snapshot.docs) {
      DelegationModel nextDelegation = DelegationModel.fromJson(
          {'id': doc.id, ...doc.data()! as Map<String, dynamic>});
      String nextDelegatee = nextDelegation.delegateeId;
      if (nextDelegatee == originalUserId) {
        // Cycle detected
        List<String> cyclePath = List<String>.from(path)..add(nextDelegatee);
        _logger.i('Circular delegation detected: ${cyclePath.join(" -> ")}.');
        return true;
      }
      if (path.contains(nextDelegatee)) {
        // Already visited this node in this path, skip to avoid infinite loops
        continue;
      }
      if (await _checkCycleRecursive(
          originalUserId, nextDelegatee, topicId, path, depth + 1)) {
        return true;
      }
    }
    return false;
  }

  // Helper method to get an existing delegation between two users for a specific topic
  Future<DelegationModel?> _getDelegationBetweenUsers({
    required String delegatorId,
    required String delegateeId,
    String? topicId,
  }) async {
    try {
      Query query = _firestore
          .collection('delegations')
          .where('delegatorId', isEqualTo: delegatorId)
          .where('delegateeId', isEqualTo: delegateeId)
          .where('active', isEqualTo: true);

      if (topicId != null) {
        query = query.where('topicId', isEqualTo: topicId);
      } else {
        // If topicId is null, we need to ensure we fetch delegations that are also explicitly 'global' (topicId == null)
        query = query.where('topicId', isNull: true);
      }

      final snapshot = await query.limit(1).get();

      if (snapshot.docs.isNotEmpty) {
        return DelegationModel.fromJson(
            snapshot.docs.first.data() as Map<String, dynamic>
              ..addAll({'id': snapshot.docs.first.id}));
      }
      return null;
    } catch (e, s) {
      _logger.e(
          'Error fetching delegation between $delegatorId and $delegateeId for topic $topicId',
          error: e,
          stackTrace: s);
      return null;
    }
  }

  // Fetch the user's direct vote for this proposal
  Future<VoteModel?> _getDirectVote(String proposalId, String userId) async {
    _logger.i(
        'Attempting to fetch direct vote for user $userId on proposal $proposalId');

    try {
      final voteSnapshot = await _firestore
          .collection('votes')
          .where('sessionId', isEqualTo: proposalId)
          .where('userId', isEqualTo: userId)
          .where('isDelegated', isEqualTo: false)
          .limit(1)
          .get();

      if (voteSnapshot.docs.isNotEmpty) {
        final voteDoc = voteSnapshot.docs.first;
        final voteData = voteDoc.data();
        _logger.i(
            'Direct vote found for user $userId on proposal $proposalId: $voteData');
        // The 'id' field in VoteModel.fromJson expects the document ID.
        // Firestore query snapshot's doc.id gives this.
        return VoteModel.fromJson(voteData..addAll({'id': voteDoc.id}));
      } else {
        _logger.i(
            'No direct vote found for user $userId on proposal $proposalId.');
        return null;
      }
    } catch (e, s) {
      _logger.e(
          'Error fetching direct vote for user $userId on proposal $proposalId',
          error: e,
          stackTrace: s);
      return null;
    }
  }
}
