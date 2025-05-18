import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/data_models.dart';

/// A service to seed the database with test data.
/// This provides a consistent set of users, topics, proposals, votes, and delegations
/// for testing and development purposes.
class DataSeeder {
  final FirebaseFirestore _firestore;
  bool _isSeeding = false;

  // User IDs for reference
  final Map<String, String> _userIds = {
    'admin': '', // Will be populated with existing admin user
    'moderator': '', // Will be populated with existing moderator user
    'proposer': '', // Will be populated with existing proposer user
    'proposer1': 'proposer_01', // Additional proposer users for testing
    'proposer2': 'proposer_02',
    'proposer3': 'proposer_03',
    'user': '', // Will be populated with existing standard user
    'user1': 'user_01', // Additional users for testing
    'user2': 'user_02',
    'user3': 'user_03',
    'user4': 'user_04',
    'user5': 'user_05',
    'user6': 'user_06',
    'user7': 'user_07',
  };

  // Topic IDs for reference
  final Map<String, String> _topicIds = {};

  // Proposal IDs for reference
  final Map<String, String> _proposalIds = {};

  DataSeeder({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Checks if seeding is in progress
  bool get isSeeding => _isSeeding;

  /// Seeds the database with test data
  Future<void> seedDatabase() async {
    if (_isSeeding) {
      debugPrint('Seeding already in progress');
      return;
    }

    _isSeeding = true;
    debugPrint('Starting database seeding...');

    try {
      // Clear existing data if needed
      // await _clearExistingData();

      // Seed in order of dependencies
      await _seedUsers();
      await _seedTopics();
      await _seedProposals();
      await _seedVoteSessions();
      await _seedVotes();
      await _seedDelegations();
      await _seedComments();

      debugPrint('Database seeding completed successfully');
    } catch (e) {
      debugPrint('Error seeding database: $e');
      rethrow;
    } finally {
      _isSeeding = false;
    }
  }

  /// Clears all seeded data from the database
  /// This preserves the default users (admin, moderator, proposer, user)
  Future<void> clearSeededData() async {
    debugPrint('Clearing seeded data...');
    _isSeeding = true;

    try {
      // Delete collections in reverse order of dependencies
      await _deleteCollection('comments');
      await _deleteCollection('votes');
      await _deleteCollection('delegations');
      await _deleteCollection('voteSessions');
      await _deleteCollection('proposals');
      await _deleteCollection('topics');

      // We don't delete users since we want to keep the default users
      // Instead, we only delete the additional users created by the seeder
      final additionalUserIds = [
        _userIds['proposer1'],
        _userIds['proposer2'],
        _userIds['proposer3'],
        _userIds['user1'],
        _userIds['user2'],
        _userIds['user3'],
        _userIds['user4'],
        _userIds['user5'],
        _userIds['user6'],
        _userIds['user7'],
      ];

      for (final userId in additionalUserIds) {
        if (userId != null && userId.isNotEmpty) {
          await _firestore.collection('users').doc(userId).delete();
        }
      }

      debugPrint('Seeded data cleared successfully');
    } catch (e) {
      debugPrint('Error clearing seeded data: $e');
      rethrow;
    } finally {
      _isSeeding = false;
    }
  }

  /// Helper method to delete a collection
  Future<void> _deleteCollection(String collectionPath) async {
    final collection =
        await _firestore.collection(collectionPath).limit(500).get();

    final batch = _firestore.batch();
    for (final doc in collection.docs) {
      batch.delete(doc.reference);
    }

    if (collection.docs.isNotEmpty) {
      await batch.commit();
      // Recursively delete if there are more documents
      await _deleteCollection(collectionPath);
    }
  }

  /// Seeds the database with test users
  Future<void> _seedUsers() async {
    debugPrint('Seeding users...');

    // Fetch existing users from the database
    await _fetchExistingUsers();

    // Create additional proposer users for testing
    await _createUser(
      id: _userIds['proposer1']!,
      name: 'Patricia Proposer',
      email: 'proposer1@example.com',
      role: UserRole.proposer,
    );
    await _createUser(
      id: _userIds['proposer2']!,
      name: 'Quincy Initiator',
      email: 'proposer2@example.com',
      role: UserRole.proposer,
    );
    await _createUser(
      id: _userIds['proposer3']!,
      name: 'Rachel Creator',
      email: 'proposer3@example.com',
      role: UserRole.proposer,
    );

    // Create additional regular users for testing
    await _createUser(
      id: _userIds['user1']!,
      name: 'David Voter',
      email: 'user1@example.com',
      role: UserRole.user,
    );
    await _createUser(
      id: _userIds['user2']!,
      name: 'Eve Participant',
      email: 'user2@example.com',
      role: UserRole.user,
    );
    await _createUser(
      id: _userIds['user3']!,
      name: 'Frank Citizen',
      email: 'user3@example.com',
      role: UserRole.user,
    );
    await _createUser(
      id: _userIds['user4']!,
      name: 'Grace Member',
      email: 'user4@example.com',
      role: UserRole.user,
    );
    await _createUser(
      id: _userIds['user5']!,
      name: 'Henry Elector',
      email: 'user5@example.com',
      role: UserRole.user,
    );
    await _createUser(
      id: _userIds['user6']!,
      name: 'Ivy Constituent',
      email: 'user6@example.com',
      role: UserRole.user,
    );
    await _createUser(
      id: _userIds['user7']!,
      name: 'Jack Public',
      email: 'user7@example.com',
      role: UserRole.user,
    );

    debugPrint('Users seeded successfully');
  }

  /// Fetches existing users from the database
  Future<void> _fetchExistingUsers() async {
    debugPrint('Fetching existing users...');

    // Fetch admin user
    final adminQuery = await _firestore
        .collection('users')
        .where('email', isEqualTo: 'admin@example.com')
        .limit(1)
        .get();

    if (adminQuery.docs.isNotEmpty) {
      _userIds['admin'] = adminQuery.docs.first.id;
      debugPrint('Found admin user: ${_userIds['admin']}');
    } else {
      debugPrint('Admin user not found!');
    }

    // Fetch moderator user
    final moderatorQuery = await _firestore
        .collection('users')
        .where('email', isEqualTo: 'moderator@example.com')
        .limit(1)
        .get();

    if (moderatorQuery.docs.isNotEmpty) {
      _userIds['moderator'] = moderatorQuery.docs.first.id;
      debugPrint('Found moderator user: ${_userIds['moderator']}');
    } else {
      debugPrint('Moderator user not found!');
    }

    // Fetch proposer user
    final proposerQuery = await _firestore
        .collection('users')
        .where('email', isEqualTo: 'proposer@example.com')
        .limit(1)
        .get();

    if (proposerQuery.docs.isNotEmpty) {
      _userIds['proposer'] = proposerQuery.docs.first.id;
      debugPrint('Found proposer user: ${_userIds['proposer']}');
    } else {
      debugPrint('Proposer user not found!');
    }

    // Fetch standard user
    final userQuery = await _firestore
        .collection('users')
        .where('email', isEqualTo: 'user@example.com')
        .limit(1)
        .get();

    if (userQuery.docs.isNotEmpty) {
      _userIds['user'] = userQuery.docs.first.id;
      debugPrint('Found standard user: ${_userIds['user']}');
    } else {
      debugPrint('Standard user not found!');
    }
  }

  /// Helper method to create a user
  Future<void> _createUser({
    required String id,
    required String name,
    required String email,
    required UserRole role,
  }) async {
    final docRef = _firestore.collection('users').doc(id);

    final user = UserModel(
      id: id,
      name: name,
      email: email,
      role: role,
      delegations: [],
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await docRef.set(user.toJson());
  }

  /// Seeds the database with test topics
  Future<void> _seedTopics() async {
    debugPrint('Seeding topics...');

    // Topic 1: Community Initiatives
    final topic1 = await _createTopic(
      title: 'Community Initiatives',
      description:
          'Proposals related to local community projects and improvements.',
    );
    _topicIds['community'] = topic1.id;

    // Topic 2: Platform Governance
    final topic2 = await _createTopic(
      title: 'Platform Governance',
      description:
          'Discussions and proposals about how this voting platform itself should operate.',
    );
    _topicIds['platform'] = topic2.id;

    // Topic 3: Environmental Policies
    final topic3 = await _createTopic(
      title: 'Environmental Policies',
      description:
          'Proposals concerning environmental protection and sustainability efforts.',
    );
    _topicIds['environment'] = topic3.id;

    debugPrint('Topics seeded successfully');
  }

  /// Helper method to create a topic
  Future<TopicModel> _createTopic({
    required String title,
    required String description,
  }) async {
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
  }

  /// Seeds the database with test proposals
  Future<void> _seedProposals() async {
    debugPrint('Seeding proposals...');

    // 1. Draft Proposals
    // P_Draft_1
    final draftProposal1 = await _createProposal(
      title: 'DRAFT: Community Garden Location',
      content:
          'We need to decide on a location for our new community garden project. Several options are available.',
      authorId: _userIds['proposer']!,
      topicId: _topicIds['community']!,
      status: ProposalStatus.draft,
      supporters: [_userIds['proposer']!],
    );
    _proposalIds['draft1'] = draftProposal1.id;

    // P_Draft_2
    final draftProposal2 = await _createProposal(
      title: 'DRAFT: Platform Feature Prioritization',
      content:
          'We need to prioritize the next set of features for our platform. Please vote on what should be developed next.',
      authorId: _userIds['user1']!,
      topicId: _topicIds['platform']!,
      status: ProposalStatus.draft,
      supporters: [_userIds['user1']!],
    );
    _proposalIds['draft2'] = draftProposal2.id;

    // 2. Discussion Phase Proposals
    final discussionProposal1 = await _createProposal(
      title: 'Proposal for Monthly Community Workshops',
      content:
          'I suggest we organize monthly workshops on various topics of interest to our community. These could include gardening, coding, art, and more. This would foster skill-sharing and community building.',
      authorId: _userIds['proposer2']!,
      topicId: _topicIds['community']!,
      status: ProposalStatus.discussion,
      supporters: [_userIds['proposer2']!],
    );
    _proposalIds['discussion1'] = discussionProposal1.id;

    final discussionProposal2 = await _createProposal(
      title: 'Proposal for Platform Accessibility Improvements',
      content:
          'We should make our platform more accessible to users with disabilities. This includes adding screen reader support, keyboard navigation, and high contrast options.',
      authorId: _userIds['user2']!,
      topicId: _topicIds['platform']!,
      status: ProposalStatus.discussion,
      supporters: [_userIds['user2']!, _userIds['user3']!],
    );
    _proposalIds['discussion2'] = discussionProposal2.id;

    // 3. Support Phase Proposals
    final supportProposal1 = await _createProposal(
      title: 'Suggestion for New Comment Moderation Rules',
      content:
          'As our platform grows, we need clearer guidelines for comment moderation. I propose implementing a three-strike system for inappropriate comments, with transparent review processes.',
      authorId: _userIds['proposer']!,
      topicId: _topicIds['platform']!,
      status: ProposalStatus.support,
      supporters: [_userIds['proposer']!, _userIds['user1']!],
    );
    _proposalIds['support1'] = supportProposal1.id;

    final supportProposal2 = await _createProposal(
      title: 'Proposal for Community Composting Program',
      content:
          'I propose establishing a community composting program to reduce waste and create nutrient-rich soil for local gardens. This would involve setting up collection points and educational workshops.',
      authorId: _userIds['user2']!,
      topicId: _topicIds['environment']!,
      status: ProposalStatus.support,
      supporters: [_userIds['user2']!],
    );
    _proposalIds['support2'] = supportProposal2.id;

    final supportProposal3 = await _createProposal(
      title: 'Annual Charity Bake-off Event',
      content:
          'I propose organizing an annual charity bake-off event to raise funds for local causes. This would be a fun community event that brings people together while supporting important initiatives.',
      authorId: _userIds['user3']!,
      topicId: _topicIds['community']!,
      status: ProposalStatus.support,
      supporters: [
        _userIds['user3']!,
        _userIds['user2']!,
        _userIds['user']!,
        _userIds['user4']!
      ],
    );
    _proposalIds['support3'] = supportProposal3.id;

    // 3. Voting Phase Proposals (Active)
    // These will be created in _seedVoteSessions() since that method handles
    // both creating the proposal and the associated vote session

    // 4. Closed Proposals
    // These will also be created in _seedVoteSessions() with past dates

    debugPrint('Proposals seeded successfully');
  }

  /// Helper method to create a proposal
  Future<ProposalModel> _createProposal({
    required String title,
    required String content,
    required String authorId,
    required String topicId,
    required ProposalStatus status,
    required List<String> supporters,
  }) async {
    final docRef = _firestore.collection('proposals').doc();

    final proposal = ProposalModel(
      id: docRef.id,
      title: title,
      content: content,
      authorId: authorId,
      topicId: topicId,
      status: status,
      supporters: supporters,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await docRef.set(proposal.toJson());
    return proposal;
  }

  /// Seeds the database with test vote sessions
  Future<void> _seedVoteSessions() async {
    debugPrint('Seeding vote sessions...');
    final now = DateTime.now();

    // 1. Active Voting Proposals
    // P_Voting_Active_1 (FPTP)
    final activeProposal1 = await _createProposal(
      title: 'Choose the Color for the Community Center Walls',
      content:
          'The community center is due for repainting, and we would like community input on the color choice. Please vote for your preferred color from the options provided.',
      authorId: _userIds['proposer1']!,
      topicId: _topicIds['community']!,
      status: ProposalStatus.voting,
      supporters: [
        _userIds['proposer1']!,
        _userIds['user1']!,
        _userIds['user2']!
      ],
    );
    _proposalIds['voting_active1'] = activeProposal1.id;

    await _createVoteSession(
      proposalId: activeProposal1.id,
      method: VotingMethod.firstPastThePost,
      options: ['Blue', 'Green', 'Yellow'],
      startDate: now.subtract(const Duration(days: 2)),
      endDate: now.add(const Duration(days: 5)),
    );

    // P_Voting_Active_2 (Approval)
    final activeProposal2 = await _createProposal(
      title: 'Approve New Features for Q3',
      content:
          'We have budget for implementing new features in Q3. Please vote for all the features you would like to see implemented. Multiple selections are allowed.',
      authorId: _userIds['proposer']!,
      topicId: _topicIds['platform']!,
      status: ProposalStatus.voting,
      supporters: [
        _userIds['proposer']!,
        _userIds['user3']!,
        _userIds['user4']!,
        _userIds['user5']!
      ],
    );
    _proposalIds['voting_active2'] = activeProposal2.id;

    await _createVoteSession(
      proposalId: activeProposal2.id,
      method: VotingMethod.approvalVoting,
      options: ['Dark Mode', 'Enhanced Search', 'User Groups'],
      startDate: now.subtract(const Duration(days: 1)),
      endDate: now.add(const Duration(days: 6)),
    );

    // P_Voting_Active_3 (Majority Runoff)
    final activeProposal3 = await _createProposal(
      title: 'Select the Primary Focus for Green Initiative Funding',
      content:
          'We have secured funding for environmental initiatives. Please vote for the project you believe should be our primary focus. If no option receives a majority, a runoff vote will be held.',
      authorId: _userIds['user']!,
      topicId: _topicIds['environment']!,
      status: ProposalStatus.voting,
      supporters: [
        _userIds['user']!,
        _userIds['user1']!,
        _userIds['user6']!,
        _userIds['user7']!
      ],
    );
    _proposalIds['voting_active3'] = activeProposal3.id;

    await _createVoteSession(
      proposalId: activeProposal3.id,
      method: VotingMethod.majorityRunoff,
      options: [
        'Solar Panel Subsidies',
        'Tree Planting Drive',
        'Recycling Awareness Campaign',
        'Water Conservation Program'
      ],
      startDate: now,
      endDate: now.add(const Duration(days: 7)),
    );

    // 2. Upcoming Voting Proposal
    final upcomingProposal = await _createProposal(
      title: 'Vote on Next Platform AMA Guest Speaker',
      content:
          'We will be hosting an AMA (Ask Me Anything) session next month. Please vote for your preferred guest speaker from the options provided.',
      authorId: _userIds['moderator']!,
      topicId: _topicIds['platform']!,
      status: ProposalStatus.voting,
      supporters: [
        _userIds['moderator']!,
        _userIds['user2']!,
        _userIds['user3']!
      ],
    );
    _proposalIds['voting_upcoming'] = upcomingProposal.id;

    await _createVoteSession(
      proposalId: upcomingProposal.id,
      method: VotingMethod.firstPastThePost,
      options: ['Tech Lead', 'UX Designer', 'Security Expert'],
      startDate: now.add(const Duration(days: 3)),
      endDate: now.add(const Duration(days: 10)),
    );

    // 3. Closed Voting Proposals
    // P_Closed_1 (FPTP - Clear Winner)
    final closedProposal1 = await _createProposal(
      title: 'PAST: Fundraiser Event Choice for Spring',
      content:
          'We need to decide on a fundraiser event for the spring season. Please vote for your preferred option.',
      authorId: _userIds['proposer']!,
      topicId: _topicIds['community']!,
      status: ProposalStatus.closed,
      supporters: [
        _userIds['proposer']!,
        _userIds['user4']!,
        _userIds['user5']!,
        _userIds['user6']!
      ],
    );
    _proposalIds['closed1'] = closedProposal1.id;

    await _createVoteSession(
      proposalId: closedProposal1.id,
      method: VotingMethod.firstPastThePost,
      options: ['Charity Run', 'Talent Show', 'Art Auction'],
      startDate: now.subtract(const Duration(days: 10)),
      endDate: now.subtract(const Duration(days: 3)),
    );

    // P_Closed_2 (Approval - Multiple Approved)
    final closedProposal2 = await _createProposal(
      title: 'PAST: Which Communication Channels to Keep?',
      content:
          'We need to streamline our communication channels. Please vote for all the channels you find useful and would like to keep.',
      authorId: _userIds['user']!,
      topicId: _topicIds['platform']!,
      status: ProposalStatus.closed,
      supporters: [
        _userIds['user']!,
        _userIds['user1']!,
        _userIds['user2']!,
        _userIds['user7']!
      ],
    );
    _proposalIds['closed2'] = closedProposal2.id;

    await _createVoteSession(
      proposalId: closedProposal2.id,
      method: VotingMethod.approvalVoting,
      options: ['Forum', 'Discord', 'Newsletter'],
      startDate: now.subtract(const Duration(days: 12)),
      endDate: now.subtract(const Duration(days: 5)),
    );

    // P_Closed_3 (Majority Runoff - Went to Runoff)
    final closedProposal3 = await _createProposal(
      title: 'PAST: Mascot for the Eco Club',
      content:
          'The Eco Club needs a mascot. Please vote for your preferred mascot from the options provided.',
      authorId: _userIds['proposer1']!,
      topicId: _topicIds['environment']!,
      status: ProposalStatus.closed,
      supporters: [
        _userIds['proposer1']!,
        _userIds['user3']!,
        _userIds['user4']!,
        _userIds['user5']!
      ],
    );
    _proposalIds['closed3'] = closedProposal3.id;

    await _createVoteSession(
      proposalId: closedProposal3.id,
      method: VotingMethod.majorityRunoff,
      options: ['Robbie the Robin', 'Sammy the Squirrel', 'Ollie the Owl'],
      startDate: now.subtract(const Duration(days: 15)),
      endDate: now.subtract(const Duration(days: 8)),
    );

    debugPrint('Vote sessions seeded successfully');
  }

  /// Helper method to create a vote session
  Future<VoteSessionModel> _createVoteSession({
    required String proposalId,
    required VotingMethod method,
    required List<String> options,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
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

    // Update proposal status to match vote session status
    // This is redundant if the proposal status was already set correctly,
    // but ensures consistency
    if (status == VoteSessionStatus.closed) {
      await _updateProposalStatus(proposalId, ProposalStatus.closed);
    } else {
      await _updateProposalStatus(proposalId, ProposalStatus.voting);
    }

    return voteSession;
  }

  /// Helper method to update a proposal's status
  Future<void> _updateProposalStatus(
      String proposalId, ProposalStatus newStatus) async {
    await _firestore.collection('proposals').doc(proposalId).update({
      'status': newStatus.toString().split('.').last,
      'updatedAt': DateTime.now(),
    });
  }

  /// Seeds the database with test votes
  Future<void> _seedVotes() async {
    debugPrint('Seeding votes...');

    // 1. Votes for Active Proposals
    // P_Voting_Active_1 (FPTP) - Color choice
    await _createVote(
      userId: _userIds['user1']!,
      proposalId: _proposalIds['voting_active1']!,
      choice: 'Blue',
      weight: 1.0,
      isDelegated: false,
    );
    await _createVote(
      userId: _userIds['user2']!,
      proposalId: _proposalIds['voting_active1']!,
      choice: 'Green',
      weight: 1.0,
      isDelegated: false,
    );
    await _createVote(
      userId: _userIds['user3']!,
      proposalId: _proposalIds['voting_active1']!,
      choice: 'Yellow',
      weight: 1.0,
      isDelegated: false,
    );
    await _createVote(
      userId: _userIds['proposer2']!,
      proposalId: _proposalIds['voting_active1']!,
      choice: 'Blue',
      weight: 1.0,
      isDelegated: false,
    );

    // P_Voting_Active_2 (Approval) - Feature selection
    await _createVote(
      userId: _userIds['user4']!,
      proposalId: _proposalIds['voting_active2']!,
      choice: '["Dark Mode", "Enhanced Search"]',
      weight: 1.0,
      isDelegated: false,
    );
    await _createVote(
      userId: _userIds['user5']!,
      proposalId: _proposalIds['voting_active2']!,
      choice: '["Dark Mode", "User Groups"]',
      weight: 1.0,
      isDelegated: false,
    );
    await _createVote(
      userId: _userIds['proposer']!,
      proposalId: _proposalIds['voting_active2']!,
      choice: '["Enhanced Search"]',
      weight: 1.0,
      isDelegated: false,
    );

    // P_Voting_Active_3 (Majority Runoff) - Green Initiative
    await _createVote(
      userId: _userIds['user6']!,
      proposalId: _proposalIds['voting_active3']!,
      choice: 'Solar Panel Subsidies',
      weight: 1.0,
      isDelegated: false,
    );
    await _createVote(
      userId: _userIds['user7']!,
      proposalId: _proposalIds['voting_active3']!,
      choice: 'Tree Planting Drive',
      weight: 1.0,
      isDelegated: false,
    );
    await _createVote(
      userId: _userIds['proposer3']!,
      proposalId: _proposalIds['voting_active3']!,
      choice: 'Water Conservation Program',
      weight: 1.0,
      isDelegated: false,
    );

    // 2. Votes for Closed Proposals
    // P_Closed_1 (FPTP - Clear Winner) - Fundraiser Event
    // Make "Charity Run" the clear winner
    await _createVote(
      userId: _userIds['user1']!,
      proposalId: _proposalIds['closed1']!,
      choice: 'Charity Run',
      weight: 1.0,
      isDelegated: false,
    );
    await _createVote(
      userId: _userIds['user2']!,
      proposalId: _proposalIds['closed1']!,
      choice: 'Charity Run',
      weight: 1.0,
      isDelegated: false,
    );
    await _createVote(
      userId: _userIds['user3']!,
      proposalId: _proposalIds['closed1']!,
      choice: 'Charity Run',
      weight: 1.0,
      isDelegated: false,
    );
    await _createVote(
      userId: _userIds['user4']!,
      proposalId: _proposalIds['closed1']!,
      choice: 'Talent Show',
      weight: 1.0,
      isDelegated: false,
    );
    await _createVote(
      userId: _userIds['user5']!,
      proposalId: _proposalIds['closed1']!,
      choice: 'Art Auction',
      weight: 1.0,
      isDelegated: false,
    );

    // P_Closed_2 (Approval - Multiple Approved) - Communication Channels
    // Make "Forum" and "Newsletter" both highly approved
    await _createVote(
      userId: _userIds['user1']!,
      proposalId: _proposalIds['closed2']!,
      choice: '["Forum", "Newsletter"]',
      weight: 1.0,
      isDelegated: false,
    );
    await _createVote(
      userId: _userIds['user2']!,
      proposalId: _proposalIds['closed2']!,
      choice: '["Forum", "Discord"]',
      weight: 1.0,
      isDelegated: false,
    );
    await _createVote(
      userId: _userIds['user3']!,
      proposalId: _proposalIds['closed2']!,
      choice: '["Forum", "Newsletter"]',
      weight: 1.0,
      isDelegated: false,
    );
    await _createVote(
      userId: _userIds['user4']!,
      proposalId: _proposalIds['closed2']!,
      choice: '["Newsletter"]',
      weight: 1.0,
      isDelegated: false,
    );
    await _createVote(
      userId: _userIds['user5']!,
      proposalId: _proposalIds['closed2']!,
      choice: '["Discord"]',
      weight: 1.0,
      isDelegated: false,
    );

    // P_Closed_3 (Majority Runoff - Went to Runoff) - Mascot
    // Ensure no option gets >50% in the first "round"
    await _createVote(
      userId: _userIds['user1']!,
      proposalId: _proposalIds['closed3']!,
      choice: 'Robbie the Robin',
      weight: 1.0,
      isDelegated: false,
    );
    await _createVote(
      userId: _userIds['user2']!,
      proposalId: _proposalIds['closed3']!,
      choice: 'Sammy the Squirrel',
      weight: 1.0,
      isDelegated: false,
    );
    await _createVote(
      userId: _userIds['user3']!,
      proposalId: _proposalIds['closed3']!,
      choice: 'Ollie the Owl',
      weight: 1.0,
      isDelegated: false,
    );
    await _createVote(
      userId: _userIds['user4']!,
      proposalId: _proposalIds['closed3']!,
      choice: 'Ollie the Owl',
      weight: 1.0,
      isDelegated: false,
    );
    await _createVote(
      userId: _userIds['user5']!,
      proposalId: _proposalIds['closed3']!,
      choice: 'Robbie the Robin',
      weight: 1.0,
      isDelegated: false,
    );

    // 3. Votes with different weights
    await _createVote(
      userId: _userIds['proposer1']!,
      proposalId: _proposalIds['closed3']!,
      choice: 'Ollie the Owl',
      weight: 2.0, // Higher weight
      isDelegated: false,
    );
    await _createVote(
      userId: _userIds['proposer2']!,
      proposalId: _proposalIds['closed2']!,
      choice: '["Forum", "Newsletter", "Discord"]',
      weight: 1.5, // Higher weight
      isDelegated: false,
    );

    // 4. Delegated votes (will be created after delegations are set up)
    // These will be handled in _seedDelegations() method

    debugPrint('Votes seeded successfully');
  }

  /// Helper method to create a vote
  Future<void> _createVote({
    required String userId,
    required String proposalId,
    required dynamic choice,
    required double weight,
    required bool isDelegated,
    String? delegatedBy,
  }) async {
    final docRef = _firestore.collection('votes').doc();

    final vote = VoteModel(
      id: docRef.id,
      userId: userId,
      proposalId: proposalId,
      choice: choice,
      weight: weight,
      isDelegated: isDelegated,
      delegatedBy: delegatedBy,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await docRef.set(vote.toJson());
  }

  /// Seeds the database with test delegations
  Future<void> _seedDelegations() async {
    print('Seeding delegations...');
    final now = DateTime.now();

    // Make the standard user (user@example.com) have the most interesting delegation relationships
    // This is the user that's accessible via the "User" login button on the login screen

    // 1. Multiple users delegate to the standard user (incoming delegations)
    // user_01 (David) delegates to standard user (general delegation)
    await _createDelegation(
      delegatorId: _userIds['user1']!,
      delegateeId: _userIds['user']!, // Standard user
      topicId: null, // General delegation
      validUntil: now.add(const Duration(days: 30)),
    );

    // user_03 (Frank) delegates to standard user for a specific topic
    await _createDelegation(
      delegatorId: _userIds['user3']!,
      delegateeId: _userIds['user']!, // Standard user
      topicId: _topicIds['education'], // Topic-specific delegation
      validUntil: now.add(const Duration(days: 45)),
    );

    // user_05 (Henry) delegates to standard user (expired delegation)
    await _createDelegation(
      delegatorId: _userIds['user5']!,
      delegateeId: _userIds['user']!, // Standard user
      topicId: null, // General delegation
      validUntil: now.subtract(const Duration(days: 5)), // Expired
    );

    // 2. Standard user delegates to others (outgoing delegations)
    // Standard user delegates to moderator for a specific topic
    await _createDelegation(
      delegatorId: _userIds['user']!, // Standard user
      delegateeId: _userIds['moderator']!,
      topicId: _topicIds['platform'], // Topic-specific delegation
      validUntil: now.add(const Duration(days: 60)),
    );

    // Standard user delegates to proposer (general delegation)
    await _createDelegation(
      delegatorId: _userIds['user']!, // Standard user
      delegateeId: _userIds['proposer']!,
      topicId: null, // General delegation
      validUntil: now.add(const Duration(days: 90)),
    );

    // 3. Other delegation relationships for completeness
    // user_02 (Eve) delegates to proposer user
    await _createDelegation(
      delegatorId: _userIds['user2']!,
      delegateeId: _userIds['proposer']!,
      topicId: null, // General delegation
      validUntil: now.add(const Duration(days: 60)),
    );

    // user_04 (Grace) delegates to user_07 (Jack)
    await _createDelegation(
      delegatorId: _userIds['user4']!,
      delegateeId: _userIds['user7']!,
      topicId: null, // General delegation
      validUntil: now.add(const Duration(days: 90)),
    );

    // user_06 (Ivy) delegates to admin_user_01 (Admin User)
    await _createDelegation(
      delegatorId: _userIds['user6']!,
      delegateeId: _userIds['admin']!,
      topicId: null, // General delegation
      validUntil: now.add(const Duration(days: 120)),
    );

    // Create some delegated votes based on the delegations
    // For standard user: Create a delegated vote from user_01 (David)
    await _createVote(
      userId: _userIds['user']!, // The standard user is the voter
      proposalId: _proposalIds['voting_active1']!,
      choice: 'Green', // Standard user's vote
      weight: 1.0,
      isDelegated: true,
      delegatedBy: _userIds['user1']!, // Delegated from David
    );

    // For delegation2: user_02 (Eve) delegates to proposer user
    // Create a delegated vote for a proposal that proposer user has voted on
    await _createVote(
      userId: _userIds['proposer']!, // The delegatee is the voter
      proposalId: _proposalIds['voting_active2']!,
      choice: '["Enhanced Search"]', // Same choice as proposer's own vote
      weight: 1.0,
      isDelegated: true,
      delegatedBy: _userIds['user2']!, // Delegated from Eve
    );

    // For delegation3: user_03 (Frank) delegates to moderator user for Topic "Platform Governance"
    // Create a delegated vote for a platform governance proposal that moderator has voted on
    await _createVote(
      userId: _userIds['moderator']!, // The delegatee is the voter
      proposalId: _proposalIds['voting_active1']!,
      choice: 'Blue', // Same choice as moderator's own vote
      weight: 1.0,
      isDelegated: true,
      delegatedBy: _userIds['user3']!, // Delegated from Frank
    );

    debugPrint('Delegations seeded successfully');
  }

  /// Helper method to create a delegation
  Future<DelegationModel> _createDelegation({
    required String delegatorId,
    required String delegateeId,
    String? topicId,
    required DateTime validUntil,
  }) async {
    final docRef = _firestore.collection('delegations').doc();

    final delegation = DelegationModel(
      id: docRef.id,
      delegatorId: delegatorId,
      delegateeId: delegateeId,
      topicId: topicId,
      active: validUntil.isAfter(DateTime.now()),
      validUntil: validUntil,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await docRef.set(delegation.toJson());

    // Update user's delegations array
    await _firestore.collection('users').doc(delegatorId).update({
      'delegations': FieldValue.arrayUnion([delegateeId]),
      'updatedAt': DateTime.now(),
    });

    return delegation;
  }

  /// Seeds the database with test comments
  Future<void> _seedComments() async {
    if (_userIds.isEmpty || _proposalIds.isEmpty) {
      debugPrint('Users or Proposals not seeded yet. Skipping comment seeding.');
      return;
    }
    debugPrint('Seeding comments...');

    final List<String> proposalKeys = _proposalIds.keys.toList();
    final List<String> userKeys = _userIds.keys.toList();

    if (proposalKeys.isEmpty || userKeys.isEmpty) {
      debugPrint('No proposals or users available to seed comments.');
      return;
    }

    // Seed comments for the first 2 proposals, if available
    for (int i = 0; i < proposalKeys.length && i < 2; i++) {
      String currentProposalId = _proposalIds[proposalKeys[i]]!;
      debugPrint('Seeding comments for proposal: ${proposalKeys[i]} ($currentProposalId)');

      // --- Top Level Comments --- (depth 0)
      final c1 = await _createComment(
        proposalId: currentProposalId,
        authorId: _userIds[userKeys[i % userKeys.length]]!, // Vary author
        content: 'This is a great starting point for discussion on ${proposalKeys[i]}!',
        depth: 0,
        createdAt: DateTime.now().subtract(const Duration(hours: 5)),
        upvotedBy: [_userIds[userKeys[(i + 1) % userKeys.length]]!],
      );

      final c2 = await _createComment(
        proposalId: currentProposalId,
        authorId: _userIds[userKeys[(i + 1) % userKeys.length]]!,
        content: 'I have a few questions regarding the implementation details.',
        depth: 0,
        createdAt: DateTime.now().subtract(const Duration(hours: 4, minutes: 30)),
        downvotedBy: [_userIds[userKeys[i % userKeys.length]]!],
      );

      await _createComment(
        proposalId: currentProposalId,
        authorId: _userIds[userKeys[(i + 2) % userKeys.length]]!,
        content: 'Looking forward to seeing how this develops.',
        depth: 0,
        createdAt: DateTime.now().subtract(const Duration(hours: 4)),
        upvotedBy: [
          _userIds[userKeys[i % userKeys.length]]!,
          _userIds[userKeys[(i + 1) % userKeys.length]]!
        ],
      );

      // --- Replies to c1 --- (depth 1)
      final c1Reply1 = await _createComment(
        proposalId: currentProposalId,
        authorId: _userIds[userKeys[(i + 2) % userKeys.length]]!,
        content: 'Indeed! I agree with your sentiment on c1.',
        parentCommentId: c1.id,
        depth: 1,
        createdAt: DateTime.now().subtract(const Duration(hours: 3)),
        upvotedBy: [_userIds[userKeys[i % userKeys.length]]!],
      );

      // --- Reply to c1_reply1 --- (depth 2)
      await _createComment(
        proposalId: currentProposalId,
        authorId: _userIds[userKeys[i % userKeys.length]]!,
        content: 'Thanks for the agreement on my reply to c1!',
        parentCommentId: c1Reply1.id,
        depth: 2,
        createdAt: DateTime.now().subtract(const Duration(hours: 2, minutes: 30)),
      );

      // --- Reply to c2 --- (depth 1)
      await _createComment(
        proposalId: currentProposalId,
        authorId: _userIds[userKeys[i % userKeys.length]]!,
        content: 'I can try to answer some of your questions about c2.',
        parentCommentId: c2.id,
        depth: 1,
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
        downvotedBy: [_userIds[userKeys[(i + 1) % userKeys.length]]!],
      );
    }

    debugPrint('Comments and replies seeded successfully.');
  }

  /// Helper method to create a comment
  Future<DocumentReference> _createComment({
    required String proposalId,
    required String authorId,
    required String content,
    String? parentCommentId,
    required int depth,
    List<String>? upvotedBy,
    List<String>? downvotedBy,
    DateTime? createdAt,
  }) async {
    final commentData = {
      'proposalId': proposalId,
      'authorId': authorId,
      'content': content,
      'parentCommentId': parentCommentId,
      'depth': depth,
      'upvotedBy': upvotedBy ?? [],
      'downvotedBy': downvotedBy ?? [],
      'createdAt': createdAt ?? Timestamp.now(),
      'updatedAt': null,
      'isEdited': false,
      'isModerated': false,
      'moderationReason': null,
      'moderatedBy': null, // Added
      'moderatedAt': null, // Added
      'attachments': null,
    };
    return _firestore.collection('comments').add(commentData);
  }
}
