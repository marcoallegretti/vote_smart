import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/data_models.dart';
import 'database_service.dart';
import 'auth_service.dart';

class ProposalLifecycleService {
  final FirebaseFirestore _firestore;
  final DatabaseService _databaseService;
  final AuthService _authService;
  final bool _isTestMode;

  StreamSubscription<QuerySnapshot>? _proposalsSubscription;
  StreamSubscription<UserModel?>? _authSubscription;

  ProposalLifecycleService({required AuthService authService})
      : _firestore = FirebaseFirestore.instance,
        _databaseService = DatabaseService(),
        _authService = authService,
        _isTestMode = false {
    _listenToAuthChanges();
  }

  ProposalLifecycleService.withMocks(
    this._firestore, 
    this._databaseService, 
    this._authService,
  ) : _isTestMode = true {
    _listenToAuthChanges();
  }

  // Fully injectable constructor for testing
  ProposalLifecycleService.withInstances(
    this._firestore, 
    this._databaseService, 
    this._authService,
  ) : _isTestMode = true {
    // No initialization in test mode
  }

  void _listenToAuthChanges() {
    _authSubscription = _authService.userModelStream.listen((userModel) {
      if (userModel != null) {
        print('DEBUG: ProposalLifecycleService - User signed in, initializing listener.');
        initializeLifecycleMonitoring();
      } else {
        print('DEBUG: ProposalLifecycleService - User signed out, cancelling listener.');
        _cancelProposalsListener();
      }
    });
  }

  static const Map<ProposalStatus, int> defaultPhaseDurations = {
    ProposalStatus.discussion: 7, 
    ProposalStatus.support: 3, 
    ProposalStatus.frozen: 1, 
    ProposalStatus.voting: 5, 
  };

  static const double supportThreshold = 0.10; 

  Future<void> initializeLifecycleMonitoring() async {
    if (_proposalsSubscription != null) {
      print('DEBUG: ProposalLifecycleService - Proposals listener already active.');
      return; 
    }
    print('DEBUG: ProposalLifecycleService - Setting up proposals listener.');
    _proposalsSubscription = _firestore.collection('proposals').snapshots().listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.modified) {
          final proposal = ProposalModel.fromJson({
            'id': change.doc.id,
            ...change.doc.data()!,
          });
          _handleProposalStatusChange(proposal);
        }
      }
    });
  }

  void _cancelProposalsListener() {
    _proposalsSubscription?.cancel();
    _proposalsSubscription = null;
    print('DEBUG: ProposalLifecycleService - Proposals listener cancelled.');
  }

  Future<void> checkAndUpdateStatus(String proposalId) async {
    final proposal = await _databaseService.getProposalById(proposalId);
    if (proposal == null) return;
    await _handleProposalStatusChange(proposal);
  }

  Future<void> _handleProposalStatusChange(ProposalModel proposal) async {
    switch (proposal.status) {
      case ProposalStatus.draft:
        if (proposal.supporters.isNotEmpty) {
          await _moveToDiscussionPhase(proposal);
        }
        break;
      case ProposalStatus.discussion:
        await _checkDiscussionPhaseCompletion(proposal);
        break;
      case ProposalStatus.support:
        await _checkSupportThreshold(proposal);
        break;
      case ProposalStatus.frozen:
        await _checkFreezePhaseCompletion(proposal);
        break;
      case ProposalStatus.voting:
        await _checkVotingPhaseCompletion(proposal);
        break;
      case ProposalStatus.closed:
        break;
    }
  }

  Future<void> _moveToDiscussionPhase(ProposalModel proposal) async {
    final discussionEndDate = DateTime.now().add(
      Duration(days: defaultPhaseDurations[ProposalStatus.discussion]!),
    );

    await _firestore.collection('proposals').doc(proposal.id).update({
      'status': ProposalStatus.discussion.toString().split('.').last,
      'phaseEndDate': discussionEndDate,
      'updatedAt': _isTestMode ? DateTime.now() : FieldValue.serverTimestamp(),
    });
  }

  Future<void> _checkDiscussionPhaseCompletion(ProposalModel proposal) async {
    final now = DateTime.now();
    final phaseEndDate = proposal.phaseEndDate ?? now;

    if (now.isAfter(phaseEndDate)) {
      await _firestore.collection('proposals').doc(proposal.id).update({
        'status': ProposalStatus.support.toString().split('.').last,
        'phaseEndDate': now.add(
          Duration(days: defaultPhaseDurations[ProposalStatus.support]!),
        ),
        'updatedAt':
            _isTestMode ? DateTime.now() : FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> _checkSupportThreshold(ProposalModel proposal) async {
    final usersSnapshot = await _firestore.collection('users').get();
    final totalUsers = usersSnapshot.size;

    final requiredSupport = (totalUsers * supportThreshold).ceil();

    if (proposal.supporters.length >= requiredSupport) {
      await _firestore.collection('proposals').doc(proposal.id).update({
        'status': ProposalStatus.frozen.toString().split('.').last,
        'phaseEndDate': DateTime.now().add(
          Duration(days: defaultPhaseDurations[ProposalStatus.frozen]!),
        ),
        'updatedAt':
            _isTestMode ? DateTime.now() : FieldValue.serverTimestamp(),
      });
    } else {
      final now = DateTime.now();
      final phaseEndDate = proposal.phaseEndDate ?? now;

      if (now.isAfter(phaseEndDate)) {
        await _firestore.collection('proposals').doc(proposal.id).update({
          'status': ProposalStatus.closed.toString().split('.').last,
          'closedReason': 'Insufficient support',
          'updatedAt':
              _isTestMode ? DateTime.now() : FieldValue.serverTimestamp(),
        });
      }
    }
  }

  Future<void> _checkFreezePhaseCompletion(ProposalModel proposal) async {
    final now = DateTime.now();
    final phaseEndDate = proposal.phaseEndDate ?? now;

    if (now.isAfter(phaseEndDate)) {
      final votingMethod = await _databaseService
              .getTopicDefaultVotingMethod(proposal.topicId) ??
          VotingMethod.firstPastThePost;
      final votingEndDate = now.add(
        Duration(days: defaultPhaseDurations[ProposalStatus.voting]!),
      );

      await _databaseService.createVoteSession(
        proposal.id,
        votingMethod,
        ['approve', 'reject'], 
        now,
        votingEndDate,
      );

      final currentProposal =
          await _databaseService.getProposalById(proposal.id);
      if (currentProposal?.status != ProposalStatus.voting) {
        await _firestore.collection('proposals').doc(proposal.id).update({
          'status': ProposalStatus.voting.toString().split('.').last,
          'voteStartDate': now,
          'phaseEndDate': votingEndDate,
          'updatedAt':
              _isTestMode ? DateTime.now() : FieldValue.serverTimestamp(),
        });
      }
    }
  }

  Future<void> _checkVotingPhaseCompletion(ProposalModel proposal) async {
    final now = DateTime.now();
    final phaseEndDate = proposal.phaseEndDate ?? now;

    if (now.isAfter(phaseEndDate)) {
      final voteSession =
          await _databaseService.getVoteSessionByProposal(proposal.id);
      if (voteSession != null) {
        final results = await _databaseService.getVoteResults(voteSession.id);

        String? closedReason = 'Voting ended.';
        if (results.containsKey('winner')) {
            closedReason = 'Winner: ${results['winner']}';
        } else if (results.containsKey('outcome')) {
            closedReason = 'Outcome: ${results['outcome']}';
        }

        await _firestore.collection('proposals').doc(proposal.id).update({
          'status': ProposalStatus.closed.toString().split('.').last,
          'votingResults': results['counts'], 
          'closedReason': closedReason,
          'updatedAt':
              _isTestMode ? DateTime.now() : FieldValue.serverTimestamp(),
        });
      } else {
        await _firestore.collection('proposals').doc(proposal.id).update({
          'status': ProposalStatus.closed.toString().split('.').last,
          'closedReason': 'Voting ended, no session/results.',
          'updatedAt':
              _isTestMode ? DateTime.now() : FieldValue.serverTimestamp(),
        });
      }
    }
  }

  Future<Duration> getRemainingPhaseTime(String proposalId) async {
    final doc = await _firestore.collection('proposals').doc(proposalId).get();
    if (!doc.exists) {
      throw Exception('Proposal not found');
    }

    final proposal = ProposalModel.fromJson({
      'id': doc.id,
      ...doc.data()!,
    });

    final now = DateTime.now();
    final phaseEndDate = proposal.phaseEndDate ?? now;

    final diff = phaseEndDate.difference(now);
    final days = (diff.inHours / 24).ceil();
    return Duration(days: days);
  }

  Future<double> getPhaseProgress(String proposalId) async {
    final doc = await _firestore.collection('proposals').doc(proposalId).get();
    if (!doc.exists) {
      throw Exception('Proposal not found');
    }

    final proposal = ProposalModel.fromJson({
      'id': doc.id,
      ...doc.data()!,
    });

    final now = DateTime.now();
    final phaseEndDate = proposal.phaseEndDate ?? now;
    final phaseDuration = defaultPhaseDurations[proposal.status] ?? 1;
    final phaseStartDate = phaseEndDate.subtract(Duration(days: phaseDuration));

    final totalDuration = phaseEndDate.difference(phaseStartDate).inSeconds;
    final elapsed = now.difference(phaseStartDate).inSeconds;

    return (elapsed / totalDuration).clamp(0.0, 1.0);
  }

  void dispose() {
    print('DEBUG: ProposalLifecycleService - Disposing...');
    _authSubscription?.cancel();
    _cancelProposalsListener();
  }
}
