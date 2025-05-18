// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart'; // For FakeFirebaseFirestore
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';   // For MockFirebaseAuth, MockUser

// Internal package imports
import 'package:vote_smart/models/audit_model.dart'; // Restored: For AuditEventType
import 'package:vote_smart/services/audit_service.dart';
import 'package:vote_smart/models/data_models.dart'; // This should contain VoteModel, DelegationModel, etc.
import 'package:vote_smart/services/delegation_service.dart';
import 'package:vote_smart/services/database_service.dart'; 

// Import generated mocks
import 'delegation_service_test.mocks.dart'; 

@GenerateMocks([AuditService])
void main() {
  late FakeFirebaseFirestore mockFirestore;
  late MockFirebaseAuth mockAuth;
  late DelegationService delegationService;
  late MockAuditService mockAuditService;
  late DatabaseService databaseServiceInstance; 
  const String testUserId = 'testUser1';
  const String testProposalId = 'testProposal1';
  const String testTopicId = 'testTopic1';

  setUp(() {
    mockFirestore = FakeFirebaseFirestore();
    mockAuth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: testUserId));
    databaseServiceInstance = DatabaseService.withInstance(mockFirestore, auth: mockAuth);

    mockAuditService = MockAuditService(); 
    // Stubbing for AuditService logAuditEvent
    when(mockAuditService.logAuditEvent(
      eventType: argThat(isA<AuditEventType>(), named: 'eventType'),
      actorUserId: argThat(isA<String>(), named: 'actorUserId'),
      targetUserId: argThat(isA<String?>(), named: 'targetUserId'), 
      entityId: argThat(isA<String?>(), named: 'entityId'),         
      entityType: argThat(isA<String?>(), named: 'entityType'),     
      details: argThat(isA<Map<String, dynamic>?>(), named: 'details') 
    )).thenAnswer((_) async => Future.value());

    delegationService = DelegationService.withInstance(
      firestoreInstance: mockFirestore, // Pass mockFirestore here
      auditService: mockAuditService,
      databaseService: databaseServiceInstance 
    );

    // Helper to easily add proposals to Firestore for tests
    mockFirestore.collection('proposals').doc(testProposalId).set({
      'id': testProposalId,
      'topicId': testTopicId,
      'title': 'Test Proposal',
      'description': 'A test proposal for voting',
      'status': 'active',
      'createdAt': DateTime.now().toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
      'creatorId': testUserId,
      'options': ['OptionA', 'OptionB', 'OptionC'],
      'votingMethod': 'firstPastThePost'
    });

    // Add topic document
    mockFirestore.collection('topics').doc(testTopicId).set({
      'id': testTopicId,
      'title': 'Test Topic',
      'description': 'Test topic for delegation testing',
      'createdAt': DateTime.now().toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String()
    });

    // Create base test user
    mockFirestore.collection('users').doc(testUserId).set({
      'id': testUserId,
      'name': 'Test User',
      'email': 'testuser@example.com',
      'role': 'user',
      'createdAt': DateTime.now().toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String()
    });
  });

  // Helper method to create user documents in Firestore
  Future<void> createTestUser(String userId, {String? name, String? email}) async {
    await mockFirestore.collection('users').doc(userId).set({
      'id': userId,
      'name': name ?? 'User $userId',
      'email': email ?? '$userId@example.com',
      'role': 'user',
      'createdAt': DateTime.now().toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String()
    });
  }

  // Note: We're using createTestUser directly in our tests

  group('DelegationService - Weighted Vote Propagation', () {
    // Test cases will go here

    test('propagates a new vote with specified initialVoteWeight correctly', () async {
      // No additional setup needed as testUser1 is already created in setUp
      final result = await delegationService.propagateVote(
        'testUser1', // initialVoterId
        'testProposal1', // proposalId
        {}, // allVotesMap
        {}, // allDelegationsMap
        'OptionA', // initialVoteChoice
        0.75, // initialVoteWeight
        null, // topicId
      );

      expect(result, isNotNull);
      expect(result!.vote.userId, testUserId);
      expect(result.vote.vote, 'OptionA');
      expect(result.vote.originalVoter, isTrue);
      expect(result.effectiveWeight, 0.75);
    });

    test('propagates using weight from existing direct VoteModel', () async {
      // Setup: Create a direct vote for testUser1
      final directVote = VoteModel(
        id: 'directVote1',
        userId: testUserId,
        proposalId: testProposalId, // Assuming proposalId is proposalId in this context
        choice: 'OptionB',
        weight: 0.5,
        isDelegated: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await mockFirestore.collection('votes').doc(directVote.id).set(directVote.toJson());

      final Map<String, VoteModel> allVotesMap = {
        testUserId: directVote,
      };

      final result = await delegationService.propagateVote(
        'testUser1', // initialVoterId
        'testProposal1', // proposalId
        allVotesMap, // allVotesMap now contains the direct vote
        {}, // allDelegationsMap
        'OptionX', // initialVoteChoice (userA's direct vote)
        1.0, // initialVoteWeight (userA's direct vote weight)
        null, // topicId
      );

      expect(result, isNotNull);
      expect(result!.vote.userId, testUserId);
      expect(result.vote.vote, 'OptionB'); // Expects the choice from the stored VoteModel
      expect(result.vote.originalVoter, isTrue);
      expect(result.vote.delegatedVia, isNull, reason: 'A direct vote is not delegated.');
      expect(result.effectiveWeight, 0.5); // Expects the weight from the stored VoteModel
    });

    test('simple delegation chain with weight multiplication (A->B, A votes)', () async {
      const userAId = 'userA';
      const userBId = 'userB';

      // Create necessary user documents first
      await createTestUser(userAId);
      await createTestUser(userBId);

      // Setup: UserA delegates to UserB with weight 0.8
      final delegationAtoB = DelegationModel(
        id: 'delegationAtoB',
        delegatorId: userAId,
        delegateeId: userBId,
        topicId: null, // General delegation
        weight: 0.8,
        active: true,
        validUntil: DateTime.now().add(const Duration(days: 30)), // Add required validUntil
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await mockFirestore.collection('delegations').doc(delegationAtoB.id).set(delegationAtoB.toJson());

      // Ensure no direct votes exist for userA or userB for this proposal
      // (FakeFirebaseFirestore is empty by default for 'votes' unless populated)

      // Populate delegation map to be used in propagation
      final Map<String, List<DelegationModel>> allDelegationsMap = {
        userAId: [delegationAtoB],
      };

      // No direct votes, so allVotesMap remains empty
      final Map<String, VoteModel> allVotesMap = {};

      final result = await delegationService.propagateVote(
        'userA', // initialVoterId
        'testProposal1', // proposalId
        allVotesMap, // Pass populated allVotesMap
        allDelegationsMap, // Pass populated allDelegationsMap
        'ChoiceFromA', // initialVoteChoice for userA's vote being propagated
        0.9, // initialVoteWeight for userA's vote being propagated
        null, // topicId
      );

      expect(result, isNotNull, reason: 'Result should not be null for A->B delegation.');
      expect(result!.vote.userId, userBId, reason: 'Vote should be for the delegatee UserB.');
      expect(result.vote.vote, 'ChoiceFromA', reason: 'Choice should be from UserA.');
      expect(result.vote.originalVoter, isFalse, reason: 'UserB is not the original voter who initiated the process.');
      expect(result.vote.delegatedVia, isNotNull, reason: 'Vote should be delegated.');
      // For C's vote, it was delegated via B, so delegatedVia.delegatorId is B.
      // The original initiating vote was from A, but the direct delegation link to C is from B.
      expect(result.vote.delegatedVia?.delegatorId, userAId, reason: 'Vote should be delegated by UserA via the A->B delegation.');
      expect(result.vote.delegatedVia?.delegateeId, userBId);
      expect(result.vote.delegatedVia?.id, delegationAtoB.id);
      expect(result.effectiveWeight, closeTo(0.9 * 0.8, 0.001), reason: 'Effective weight should be initialVoteWeight * delegationWeight.');
    });

    test('weight multiplication down a chain (A->B->C, A votes)', () async {
      const userAId = 'userA';
      const userBId = 'userB';
      const userCId = 'userC';
      final validUntil = DateTime.now().add(const Duration(days: 30));

      // Create necessary user documents first
      await createTestUser(userAId);
      await createTestUser(userBId);
      await createTestUser(userCId);

      // Setup: UserA delegates to UserB (weight 0.8)
      final delegationAtoB = DelegationModel(
        id: 'delegationAtoBChain',
        delegatorId: userAId,
        delegateeId: userBId,
        topicId: null,
        weight: 0.8,
        active: true,
        validUntil: validUntil,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await mockFirestore.collection('delegations').doc(delegationAtoB.id).set(delegationAtoB.toJson());

      // Setup: UserB delegates to UserC (weight 0.7)
      final delegationBtoC = DelegationModel(
        id: 'delegationBtoCChain',
        delegatorId: userBId,
        delegateeId: userCId,
        topicId: null,
        weight: 0.7,
        active: true,
        validUntil: validUntil,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await mockFirestore.collection('delegations').doc(delegationBtoC.id).set(delegationBtoC.toJson());

      // Populate delegation map to be used in propagation - this is crucial for the delegation service
      // to find and follow the delegation chain from A->B->C
      final Map<String, List<DelegationModel>> allDelegationsMap = {
        userAId: [delegationAtoB],
        userBId: [delegationBtoC],
      };

      // No direct votes, so allVotesMap remains empty
      final Map<String, VoteModel> allVotesMap = {};

      final result = await delegationService.propagateVote(
        userAId, // initialVoterId
        testProposalId, // proposalId
        allVotesMap,
        allDelegationsMap,
        'ChoiceChain', // initialVoteChoice for userA's vote being propagated
        0.9, // initialVoteWeight for userA's vote being propagated
        null, // topicId
      );

      expect(result, isNotNull, reason: 'Result should not be null for A->B->C delegation.');
      expect(result!.vote.userId, userCId, reason: 'Vote should be for the final delegatee UserC.');
      expect(result.vote.vote, 'ChoiceChain', reason: 'Choice should be from UserA.');
      expect(result.vote.originalVoter, isFalse, reason: 'UserC is not the original voter.');
      expect(result.vote.delegatedVia, isNotNull, reason: 'Vote should be delegated.');
      // For C's vote, it was delegated via B, so delegatedVia.delegatorId is B.
      // The original initiating vote was from A, but the direct delegation link to C is from B.
      expect(result.vote.delegatedVia?.delegatorId, userBId, reason: 'Vote for C is delegated by UserB via the B->C delegation.');
      expect(result.vote.delegatedVia?.delegateeId, userCId);
      expect(result.vote.delegatedVia?.id, delegationBtoC.id);
      expect(result.effectiveWeight, closeTo(0.9 * 0.8 * 0.7, 0.0001), reason: 'Effective weight should be product of initial and all delegation weights.');
    });

    test('direct vote with its own weight overrides delegation', () async {
      const userAId = 'userA';
      const userBId = 'userB';
      final validUntil = DateTime.now().add(const Duration(days: 30));

      // Create necessary user documents first
      await createTestUser(userAId);
      await createTestUser(userBId);

      // Setup: UserA delegates to UserB (weight 0.8)
      final delegationAtoB = DelegationModel(
        id: 'delegationAtoBDirectOverride',
        delegatorId: userAId,
        delegateeId: userBId,
        topicId: null,
        weight: 0.8,
        active: true,
        validUntil: validUntil,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await mockFirestore.collection('delegations').doc(delegationAtoB.id).set(delegationAtoB.toJson());

      // Setup: UserB has a direct vote (weight 0.5)
      final directVoteB = VoteModel(
        id: 'directVoteBOverride',
        userId: userBId,
        proposalId: testProposalId,
        choice: 'DirectChoiceB',
        weight: 0.5,
        isDelegated: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await mockFirestore.collection('votes').doc(directVoteB.id).set(directVoteB.toJson());

      // Populate delegation map to be used in propagation
      final Map<String, List<DelegationModel>> allDelegationsMap = {
        userAId: [delegationAtoB],
      };

      // Add direct vote to votes map
      final Map<String, VoteModel> allVotesMap = {
        userBId: directVoteB,
      };

      final result = await delegationService.propagateVote(
        userAId, // initialVoterId
        testProposalId, // proposalId
        allVotesMap,
        allDelegationsMap,
        'DelegatedChoiceFromA', // initialVoteChoice for userA's vote being propagated
        0.9, // initialVoteWeight for userA's vote being propagated
        null, // topicId
      );

      expect(result, isNotNull, reason: 'Result should not be null.');
      expect(result!.vote.userId, userBId, reason: 'Vote should be for UserB.');
      expect(result.vote.vote, 'DirectChoiceB', reason: 'UserB\'s direct vote choice should take precedence.');
      expect(result.vote.originalVoter, isTrue, reason: 'It is UserB\'s own direct vote.');
      expect(result.vote.delegatedVia, isNull, reason: 'A direct vote is not delegatedVia anyone.');
      expect(result.effectiveWeight, 0.5, reason: 'Effective weight should be from UserB\'s direct vote.');
    });

    test('delegated vote (even if stronger) does NOT override existing direct vote', () async {
      const userAId = 'userA';
      const userBId = 'userB';
      final validUntil = DateTime.now().add(const Duration(days: 30));
      
      // Create necessary user documents first
      await createTestUser(userAId);
      await createTestUser(userBId);

      // Setup: UserA delegates to UserB
      final delegationAtoB = DelegationModel(
        id: 'delegationAtoBStrongDelegation',
        delegatorId: userAId,
        delegateeId: userBId,
        topicId: null,
        weight: 1.0,
        active: true,
        validUntil: validUntil,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await mockFirestore.collection('delegations').doc(delegationAtoB.id).set(delegationAtoB.toJson());

      // Setup: UserB has a direct, but weaker, vote (weight 0.1)
      final directVoteB = VoteModel(
        id: 'directVoteBWeakDirect',
        userId: userBId,
        proposalId: testProposalId,
        choice: 'DirectButWeakerChoiceB',
        weight: 0.1,
        isDelegated: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await mockFirestore.collection('votes').doc(directVoteB.id).set(directVoteB.toJson());

      // Populate delegation map to be used in propagation
      final Map<String, List<DelegationModel>> allDelegationsMap = {
        userAId: [delegationAtoB],
      };

      // Add direct vote to votes map
      final Map<String, VoteModel> allVotesMap = {
        userBId: directVoteB,
      };

      final result = await delegationService.propagateVote(
        userAId, // initialVoterId
        testProposalId, // proposalId
        allVotesMap,
        allDelegationsMap,
        'DelegatedAndStrongerChoiceFromA', // initialVoteChoice for userA's vote being propagated
        1.0, // initialVoteWeight for userA's vote being propagated (userA's *potential* vote weight)
        null, // topicId
      );

      expect(result, isNotNull, reason: 'Result should not be null.');
      expect(result!.vote.userId, userBId, reason: 'The vote should be attributed to UserB who has the direct vote.');
      expect(result.vote.vote, 'DirectButWeakerChoiceB', reason: 'The vote choice should be UserB\'s direct choice.');
      expect(result.vote.originalVoterId, userBId, reason: 'The original voter determining the choice and base weight is UserB.');
      expect(result.vote.isDirectVote, false, reason: 'UserA\'s vote is achieved via delegation.');
      expect(result.vote.delegatedVia?.id, delegationAtoB.id, reason: 'UserA\'s vote came via delegation to UserB.');
      expect(result.vote.delegatedVia?.delegatorId, userAId);
      expect(result.vote.delegatedVia?.delegateeId, userBId);
      expect(result.vote.weight, 0.1, reason: 'The intrinsic weight of the vote comes from UserB\'s direct vote.');
      // Effective weight for UserA's vote: (UserB's direct vote weight) * (A->B delegation weight)
      // In this test, UserA delegates with weight 1.0 to UserB, UserB's direct vote has weight 0.1.
      // So, UserA's vote, when propagated through B, should effectively have UserB's choice and weight * A->B delegation weight.
      expect(result.effectiveWeight, closeTo(0.1 * 1.0, 0.001), reason: 'Effective weight for UserA should be (UserB\'s direct vote weight) * (A->B delegation weight).');
    });
    
    test('delegated vote (A->B) uses B\'s direct vote if B voted, effective weight reflects delegation', () async {
      const userAId = 'userA';
      const userBId = 'userB';
      final validUntil = DateTime.now().add(const Duration(days: 30));
      
      // Create necessary user documents first
      await createTestUser(userAId);
      await createTestUser(userBId);

      // Setup: UserA delegates to UserB (weight 0.7)
      final delegationAtoB = DelegationModel(
        id: 'delegationAtoBForBDirectVote',
        delegatorId: userAId,
        delegateeId: userBId,
        topicId: null,
        weight: 0.7, // A->B delegation weight
        active: true,
        validUntil: validUntil,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await mockFirestore.collection('delegations').doc(delegationAtoB.id).set(delegationAtoB.toJson());

      // Setup: UserB has a direct vote (weight 0.5)
      final directVoteB = VoteModel(
        id: 'directVoteBForOverrideTest',
        userId: userBId,
        proposalId: testProposalId,
        choice: 'ChoiceByBDirectly',
        weight: 0.5, // B's direct vote weight
        isDelegated: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await mockFirestore.collection('votes').doc(directVoteB.id).set(directVoteB.toJson());

      // Populate delegation map to be used in propagation
      final Map<String, List<DelegationModel>> allDelegationsMap = {
        userAId: [delegationAtoB],
      };

      // Add direct vote to votes map
      final Map<String, VoteModel> allVotesMap = {
        userBId: directVoteB,
      };

      final result = await delegationService.propagateVote(
        userAId, // initialVoterId
        testProposalId, // proposalId
        allVotesMap,
        allDelegationsMap,
        'ChoiceByAInitially', // initialVoteChoice for userA's vote being propagated
        1.0, // initialVoteWeight for userA's potential vote (if B hadn't voted)
        null, // topicId
      );

      expect(result, isNotNull, reason: 'Result should not be null.');
      // The 'vote' object within PropagatedVote represents userA's final stance
      expect(result!.vote.userId, userAId, reason: 'The PropagatedVote.vote object should be for UserA.');
      expect(result.vote.vote, 'ChoiceByBDirectly', reason: 'UserA\'s final vote choice should be UserB\'s direct choice.');
      expect(result.vote.originalVoterId, userBId, reason: 'The original voter determining the choice and base weight is UserB.');
      // For userA's PropagatedVote, isDirectVote should be false because it's the result of delegation.
      expect(result.vote.isDirectVote, false, reason: 'UserA\'s vote is achieved via delegation, so it is not a direct vote for UserA.');
      expect(result.vote.delegatedVia?.id, delegationAtoB.id, reason: 'UserA\'s vote is delegated via the A->B delegation.');
      expect(result.vote.delegatedVia?.delegatorId, userAId);
      expect(result.vote.delegatedVia?.delegateeId, userBId);
      // The intrinsic weight of userA's vote, in this case, is taken from userB's direct vote
      expect(result.vote.weight, 0.5, reason: 'The intrinsic weight of the vote (for A) comes from UserB\'s direct vote.');
      // Effective weight for UserA's vote: (UserB's direct vote weight) * (A->B delegation weight)
      expect(result.effectiveWeight, closeTo(0.5 * 0.7, 0.001), reason: 'Effective weight for UserA should be (UserB\'s direct vote weight) * (A->B delegation weight).');
    });

    // Add more tests for:
    // - Cycles (should still return null or handle gracefully)
    // - Topic-specific vs general delegations with weights
  });

  group('DelegationService - Circular Delegation Detection', () {
    const String userAId = 'userA';
    const String userBId = 'userB';
    const String userCId = 'userC';
    const String userDId = 'userD';

    setUp(() async {
      // Create all the user documents needed for circular delegation tests
      await createTestUser(userAId);
      await createTestUser(userBId);
      await createTestUser(userCId);
      await createTestUser(userDId);
    });

    test('wouldCreateCircularDelegation returns false for no cycle (A->B, trying C->D)', () async {
      // Setup: A -> B
      mockAuth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: userAId));
      databaseServiceInstance = DatabaseService.withInstance(mockFirestore, auth: mockAuth);
      delegationService = DelegationService.withInstance(firestoreInstance: mockFirestore, auditService: mockAuditService, databaseService: databaseServiceInstance);
      await databaseServiceInstance.createDelegation(userBId, DateTime.now().add(const Duration(days: 30)), null);
      
      // Check: C tries to delegate to D
      mockAuth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: userCId));
      databaseServiceInstance = DatabaseService.withInstance(mockFirestore, auth: mockAuth); // Update service for correct user context
      delegationService = DelegationService.withInstance(firestoreInstance: mockFirestore, auditService: mockAuditService, databaseService: databaseServiceInstance);
      final isCycle = await delegationService.wouldCreateCircularDelegation(userDId, topicId: null);
      expect(isCycle, isFalse);
    });

    test('wouldCreateCircularDelegation returns true for simple cycle (A->B, trying B->A)', () async {
      // Setup: A -> B
      mockAuth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: userAId));
      databaseServiceInstance = DatabaseService.withInstance(mockFirestore, auth: mockAuth);
      delegationService = DelegationService.withInstance(firestoreInstance: mockFirestore, auditService: mockAuditService, databaseService: databaseServiceInstance);
      await databaseServiceInstance.createDelegation(userBId, DateTime.now().add(const Duration(days: 30)), null);
      
      // Check: B tries to delegate to A
      mockAuth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: userBId));
      databaseServiceInstance = DatabaseService.withInstance(mockFirestore, auth: mockAuth); // Update service for correct user context
      delegationService = DelegationService.withInstance(firestoreInstance: mockFirestore, auditService: mockAuditService, databaseService: databaseServiceInstance);
      final isCycle = await delegationService.wouldCreateCircularDelegation(userAId, topicId: null);
      expect(isCycle, isTrue);
    });

    test('wouldCreateCircularDelegation returns true for longer cycle (A->B, B->C, trying C->A)', () async {
      // Setup: A -> B
      mockAuth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: userAId));
      databaseServiceInstance = DatabaseService.withInstance(mockFirestore, auth: mockAuth);
      delegationService = DelegationService.withInstance(firestoreInstance: mockFirestore, auditService: mockAuditService, databaseService: databaseServiceInstance);
      await databaseServiceInstance.createDelegation(userBId, DateTime.now().add(const Duration(days: 30)), null);
      
      // Setup: B -> C
      mockAuth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: userBId));
      databaseServiceInstance = DatabaseService.withInstance(mockFirestore, auth: mockAuth);
      delegationService = DelegationService.withInstance(firestoreInstance: mockFirestore, auditService: mockAuditService, databaseService: databaseServiceInstance);
      await databaseServiceInstance.createDelegation(userCId, DateTime.now().add(const Duration(days: 30)), null);
      
      // Check: C tries to delegate to A
      mockAuth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: userCId));
      databaseServiceInstance = DatabaseService.withInstance(mockFirestore, auth: mockAuth); // Update service for correct user context
      delegationService = DelegationService.withInstance(firestoreInstance: mockFirestore, auditService: mockAuditService, databaseService: databaseServiceInstance);
      final isCycle = await delegationService.wouldCreateCircularDelegation(userAId, topicId: null);
      expect(isCycle, isTrue);
    });

    test('wouldCreateCircularDelegation returns false if path ends (A->B, B->C, trying D->A)', () async {
      // Setup: A -> B
      mockAuth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: userAId));
      databaseServiceInstance = DatabaseService.withInstance(mockFirestore, auth: mockAuth);
      delegationService = DelegationService.withInstance(firestoreInstance: mockFirestore, auditService: mockAuditService, databaseService: databaseServiceInstance);
      await databaseServiceInstance.createDelegation(userBId, DateTime.now().add(const Duration(days: 30)), null);
      // Setup: B -> C
      mockAuth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: userBId));
      databaseServiceInstance = DatabaseService.withInstance(mockFirestore, auth: mockAuth);
      delegationService = DelegationService.withInstance(firestoreInstance: mockFirestore, auditService: mockAuditService, databaseService: databaseServiceInstance);
      await databaseServiceInstance.createDelegation(userCId, DateTime.now().add(const Duration(days: 30)), null);
      
      // Check: D tries to delegate to A
      mockAuth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: userDId));
      databaseServiceInstance = DatabaseService.withInstance(mockFirestore, auth: mockAuth);
      delegationService = DelegationService.withInstance(firestoreInstance: mockFirestore, auditService: mockAuditService, databaseService: databaseServiceInstance);
      final isCycle = await delegationService.wouldCreateCircularDelegation(userAId, topicId: null);
      expect(isCycle, isFalse);
    });

    test('wouldCreateCircularDelegation topic-specific: A(T1)->B, trying B(T1)->A should be a cycle', () async {
      // Setup: A(T1) -> B
      mockAuth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: userAId));
      databaseServiceInstance = DatabaseService.withInstance(mockFirestore, auth: mockAuth);
      delegationService = DelegationService.withInstance(firestoreInstance: mockFirestore, auditService: mockAuditService, databaseService: databaseServiceInstance);
      await databaseServiceInstance.createDelegation(userBId, DateTime.now().add(const Duration(days: 30)), testTopicId);
      
      // Check: B(T1) tries to delegate to A(T1)
      mockAuth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: userBId));
      databaseServiceInstance = DatabaseService.withInstance(mockFirestore, auth: mockAuth);
      delegationService = DelegationService.withInstance(firestoreInstance: mockFirestore, auditService: mockAuditService, databaseService: databaseServiceInstance);
      final isCycle = await delegationService.wouldCreateCircularDelegation(userAId, topicId: testTopicId);
      expect(isCycle, isTrue);
    });

    test('wouldCreateCircularDelegation topic-specific: A(T1)->B, B(T2)->C, trying C(T1)->A should NOT be a cycle by current logic', () async {
      // Setup: A(T1) -> B
      mockAuth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: userAId));
      databaseServiceInstance = DatabaseService.withInstance(mockFirestore, auth: mockAuth);
      delegationService = DelegationService.withInstance(firestoreInstance: mockFirestore, auditService: mockAuditService, databaseService: databaseServiceInstance);
      await databaseServiceInstance.createDelegation(userBId, DateTime.now().add(const Duration(days: 30)), testTopicId);
      // Setup: B(T2) -> C
      mockAuth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: userBId));
      databaseServiceInstance = DatabaseService.withInstance(mockFirestore, auth: mockAuth);
      delegationService = DelegationService.withInstance(firestoreInstance: mockFirestore, auditService: mockAuditService, databaseService: databaseServiceInstance);
      await databaseServiceInstance.createDelegation(userCId, DateTime.now().add(const Duration(days: 30)), 'anotherTopic');
      
      // Check: C(T1) tries to delegate to A(T1)
      mockAuth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: userCId));
      databaseServiceInstance = DatabaseService.withInstance(mockFirestore, auth: mockAuth);
      delegationService = DelegationService.withInstance(firestoreInstance: mockFirestore, auditService: mockAuditService, databaseService: databaseServiceInstance);
      final isCycle = await delegationService.wouldCreateCircularDelegation(userAId, topicId: testTopicId);
      expect(isCycle, isFalse, reason: "Strict topic matching in cycle check means B's delegation on T2 is ignored when checking T1 cycle.");
    });

    test('wouldCreateCircularDelegation mixed: A(any)->B, B(T1)->C, trying C(any)->A should be complex and might be false depending on strictness', () async {
      // Setup: A(any) -> B
      mockAuth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: userAId));
      databaseServiceInstance = DatabaseService.withInstance(mockFirestore, auth: mockAuth);
      delegationService = DelegationService.withInstance(firestoreInstance: mockFirestore, auditService: mockAuditService, databaseService: databaseServiceInstance);
      await databaseServiceInstance.createDelegation(userBId, DateTime.now().add(const Duration(days: 30)), null); 
      // Setup: B(T1) -> C
      mockAuth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: userBId));
      databaseServiceInstance = DatabaseService.withInstance(mockFirestore, auth: mockAuth);
      delegationService = DelegationService.withInstance(firestoreInstance: mockFirestore, auditService: mockAuditService, databaseService: databaseServiceInstance);
      await databaseServiceInstance.createDelegation(userCId, DateTime.now().add(const Duration(days: 30)), testTopicId);
      
      // Check: C(any) tries to delegate to A(any)
      mockAuth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: userCId));
      databaseServiceInstance = DatabaseService.withInstance(mockFirestore, auth: mockAuth);
      delegationService = DelegationService.withInstance(firestoreInstance: mockFirestore, auditService: mockAuditService, databaseService: databaseServiceInstance);
      final isCycle = await delegationService.wouldCreateCircularDelegation(userAId, topicId: null);
      expect(isCycle, false, reason: "Current cycle detection is strict: a general check from C would only follow general delegations from B. B->C (Topic1) is not general.");
    });

    test('wouldCreateCircularDelegation general: A(any)->B, trying B(any)->A should be a cycle', () async {
      // Setup: A(any) -> B
      mockAuth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: userAId));
      databaseServiceInstance = DatabaseService.withInstance(mockFirestore, auth: mockAuth);
      delegationService = DelegationService.withInstance(firestoreInstance: mockFirestore, auditService: mockAuditService, databaseService: databaseServiceInstance);
      await databaseServiceInstance.createDelegation(userBId, DateTime.now().add(const Duration(days: 30)), null);

      // Check: B(any) -> A(any)
      mockAuth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: userBId));
      databaseServiceInstance = DatabaseService.withInstance(mockFirestore, auth: mockAuth);
      delegationService = DelegationService.withInstance(firestoreInstance: mockFirestore, auditService: mockAuditService, databaseService: databaseServiceInstance);
      final isCycle = await delegationService.wouldCreateCircularDelegation(userAId, topicId: null);
      expect(isCycle, isTrue);
    });

  });
}
