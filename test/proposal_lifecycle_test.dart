import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:vote_smart/models/data_models.dart';
import 'package:vote_smart/services/proposal_lifecycle_service.dart';
import 'package:vote_smart/services/database_service.dart';
import 'package:vote_smart/services/auth_service.dart';

void main() {
  group('ProposalLifecycle Tests', () {
    late FakeFirebaseFirestore fakeFirestore;
    late MockFirebaseAuth mockAuth;
    late AuthService mockAuthService;
    late ProposalLifecycleService lifecycleService;
    late DatabaseService databaseService;

    setUp(() async {
      fakeFirestore = FakeFirebaseFirestore();
      mockAuth = MockFirebaseAuth();
      mockAuthService = AuthService.withInstances(mockAuth, fakeFirestore);
      databaseService =
          DatabaseService.withInstance(fakeFirestore, auth: mockAuth);

      final mockUser = MockUser(
        isAnonymous: false,
        uid: 'test-user-uid',
        email: 'testuser@example.com',
        displayName: 'Test User',
      );
      await mockAuthService.signInWithEmailAndPassword(
          mockUser.email!, 'password');

      lifecycleService = ProposalLifecycleService.withInstances(
        fakeFirestore,
        databaseService,
        mockAuthService,
      );
    });

    tearDown(() {
      // No need to call dispose on AuthService in this context
    });

    Future<ProposalModel> createTestProposal({
      required String id,
      required ProposalStatus status,
      DateTime? phaseEndDate,
      List<String> supporters = const [],
      String? topicId,
    }) async {
      final testTopicId = topicId ?? 'test-topic';
      await fakeFirestore.collection('topics').doc(testTopicId).set({
        'id': testTopicId,
        'title': 'Test Topic',
        'description': 'Test Description',
        'createdAt': DateTime.now(),
        'updatedAt': DateTime.now(),
      });
      final proposal = ProposalModel(
        id: id,
        title: 'Test Proposal',
        content: 'Test Content',
        authorId: 'test-author',
        topicId: testTopicId,
        status: status,
        supporters: supporters,
        phaseEndDate: phaseEndDate,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await fakeFirestore
          .collection('proposals')
          .doc(id)
          .set(proposal.toJson());
      return proposal;
    }

    Future<void> createTestUsers(int count) async {
      for (var i = 0; i < count; i++) {
        await fakeFirestore.collection('users').doc('user-$i').set({
          'id': 'user-$i',
          'name': 'Test User $i',
          'email': 'user$i@test.com',
          'role': 'user',
          'createdAt': DateTime.now(),
          'updatedAt': DateTime.now(),
        });
      }
    }

    group('Phase Transitions', () {
      test('Draft to Discussion phase transition', () async {
        final proposal = await createTestProposal(
          id: 'test-proposal-1',
          status: ProposalStatus.draft,
          supporters: ['test-author'],
        );

        await lifecycleService.checkAndUpdateStatus(proposal.id);

        await Future.delayed(const Duration(milliseconds: 100));

        final updatedDoc = await fakeFirestore
            .collection('proposals')
            .doc('test-proposal-1')
            .get();
        final status = updatedDoc.data()?['status'] as String?;
        expect(status, equals('discussion'));
      });

      test('Discussion to Support phase transition after time expires',
          () async {
        final proposal = await createTestProposal(
          id: 'test-proposal-2',
          status: ProposalStatus.discussion,
          phaseEndDate: DateTime.now().subtract(const Duration(days: 1)),
        );

        await lifecycleService.checkAndUpdateStatus(proposal.id);

        final updatedDoc = await fakeFirestore
            .collection('proposals')
            .doc('test-proposal-2')
            .get();
        final status = updatedDoc.data()?['status'] as String?;
        expect(status, equals('support'));
      });

      test('Support phase transition with sufficient support', () async {
        await createTestUsers(10);

        final proposal = await createTestProposal(
          id: 'test-proposal-3',
          status: ProposalStatus.support,
          supporters: List.generate(2, (i) => 'user-$i'),
        );

        await lifecycleService.checkAndUpdateStatus(proposal.id);

        final updatedDoc = await fakeFirestore
            .collection('proposals')
            .doc('test-proposal-3')
            .get();
        final status = updatedDoc.data()?['status'] as String?;
        expect(status, equals('frozen'));
      });

      test('Support phase closes proposal with insufficient support', () async {
        await createTestUsers(20);

        final proposal = await createTestProposal(
          id: 'test-proposal-4',
          status: ProposalStatus.support,
          supporters: ['user-0'],
          phaseEndDate: DateTime.now().subtract(const Duration(days: 1)),
        );

        await lifecycleService.checkAndUpdateStatus(proposal.id);

        final updatedDoc = await fakeFirestore
            .collection('proposals')
            .doc('test-proposal-4')
            .get();
        final status = updatedDoc.data()?['status'] as String?;
        final reason = updatedDoc.data()?['closedReason'] as String?;
        expect(status, equals('closed'));
        expect(reason, equals('Insufficient support'));
      });

      test('Frozen to Voting phase transition', () async {
        final proposal = await createTestProposal(
          id: 'test-proposal-5',
          status: ProposalStatus.frozen,
          phaseEndDate: DateTime.now().subtract(const Duration(days: 1)),
        );

        await fakeFirestore.collection('settings').doc('voting').set({
          'defaultMethod': 'firstPastThePost',
        });

        await lifecycleService.checkAndUpdateStatus(proposal.id);

        final updatedDoc = await fakeFirestore
            .collection('proposals')
            .doc('test-proposal-5')
            .get();
        final status = updatedDoc.data()?['status'] as String?;
        expect(status, equals('voting'));

        final voteSessions = await fakeFirestore
            .collection('voteSessions')
            .where('proposalId', isEqualTo: 'test-proposal-5')
            .get();
        expect(voteSessions.docs.length, equals(1));
      });

      test('Voting to Closed phase transition', () async {
        final proposal = await createTestProposal(
          id: 'test-proposal-6',
          status: ProposalStatus.voting,
          phaseEndDate: DateTime.now().subtract(const Duration(days: 1)),
        );

        final voteSession = VoteSessionModel(
          id: 'test-session-1',
          proposalId: 'test-proposal-6',
          method: VotingMethod.firstPastThePost,
          options: ['approve', 'reject'],
          startDate: DateTime.now().subtract(const Duration(days: 5)),
          endDate: DateTime.now().subtract(const Duration(days: 1)),
          status: VoteSessionStatus.closed,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        await fakeFirestore
            .collection('voteSessions')
            .doc(voteSession.id)
            .set(voteSession.toJson());

        await fakeFirestore.collection('votes').doc('vote-1').set({
          'id': 'vote-1',
          'sessionId': voteSession.id,
          'userId': 'user-1',
          'choice': 'approve',
          'isDelegated': false,
          'createdAt': DateTime.now(),
          'updatedAt': DateTime.now(),
        });

        await fakeFirestore.collection('votes').doc('vote-2').set({
          'id': 'vote-2',
          'sessionId': voteSession.id,
          'userId': 'user-2',
          'choice': 'reject',
          'isDelegated': false,
          'createdAt': DateTime.now(),
          'updatedAt': DateTime.now(),
        });

        await fakeFirestore.collection('votes').doc('vote-3').set({
          'id': 'vote-3',
          'sessionId': voteSession.id,
          'userId': 'user-3',
          'choice': 'approve',
          'isDelegated': false,
          'createdAt': DateTime.now(),
          'updatedAt': DateTime.now(),
        });

        await lifecycleService.checkAndUpdateStatus(proposal.id);

        final updatedDoc = await fakeFirestore
            .collection('proposals')
            .doc('test-proposal-6')
            .get();
        final status = updatedDoc.data()?['status'] as String?;
        final results =
            updatedDoc.data()?['votingResults'] as Map<String, dynamic>?;

        expect(status, equals('closed'));
        expect(results, isNotNull);
        expect(results!['approve'], equals(2));
        expect(results['reject'], equals(1));
      });
    });

    group('Phase Duration and Progress', () {
      test('Get remaining phase time', () async {
        final endDate = DateTime.now().add(const Duration(days: 2));
        await createTestProposal(
          id: 'test-proposal-7',
          status: ProposalStatus.discussion,
          phaseEndDate: endDate,
        );

        final remaining =
            await lifecycleService.getRemainingPhaseTime('test-proposal-7');
        expect(remaining.inDays, equals(2));
      });

      test('Get phase progress', () async {
        final startDate = DateTime.now().subtract(const Duration(days: 3));
        final endDate = startDate.add(const Duration(days: 7));
        await createTestProposal(
          id: 'test-proposal-8',
          status: ProposalStatus.discussion,
          phaseEndDate: endDate,
        );

        final progress =
            await lifecycleService.getPhaseProgress('test-proposal-8');
        expect(progress, greaterThan(0.3));
        expect(progress, lessThan(0.5));
      });
    });
  });
}
