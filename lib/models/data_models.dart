import 'package:cloud_firestore/cloud_firestore.dart';

// User role enum
enum UserRole { admin, moderator, user, proposer }

// Proposal status enum
enum ProposalStatus { draft, discussion, support, frozen, voting, closed }

// Vote session status enum
enum VoteSessionStatus { upcoming, active, closed }

// Voting method enum
enum VotingMethod {
  firstPastThePost,
  approvalVoting,
  majorityRunoff,
  schulze,
  instantRunoff,
  starVoting,
  rangeVoting,
  majorityJudgment,
  quadraticVoting,
  condorcet,
  bordaCount,
  cumulativeVoting,
  kemenyYoung,
  dualChoice,
  weightVoting
}

// User model
class UserModel {
  final String id;
  final String name;
  final String email;
  final UserRole role;
  final List<String> delegations;
  final DateTime createdAt;
  final DateTime updatedAt;

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.delegations = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    // Handle Timestamp conversions safely
    DateTime getDateTimeFromTimestamp(dynamic timestamp) {
      if (timestamp is Timestamp) {
        return timestamp.toDate();
      } else if (timestamp is DateTime) {
        return timestamp;
      }
      return DateTime.now(); // Default fallback
    }

    // Parse the role string safely
    UserRole parseRole(String? roleStr) {
      if (roleStr == null) return UserRole.user;

      try {
        return UserRole.values.firstWhere(
          (role) =>
              role.toString().split('.').last.toLowerCase() ==
              roleStr.toLowerCase(),
          orElse: () => UserRole.user,
        );
      } catch (e) {
        print('Error parsing role: $roleStr - $e');
        return UserRole.user;
      }
    }

    // Handle required fields with null safety
    final id = json['id'] as String? ?? '';
    final name = json['name'] as String? ?? 'Unknown User';
    final email = json['email'] as String? ?? 'no-email';

    if (id.isEmpty) {
      print('Warning: Creating UserModel with empty ID. JSON: $json');
    }

    return UserModel(
      id: id,
      name: name,
      email: email,
      role: parseRole(json['role'] as String?),
      delegations: List<String>.from(json['delegations'] ?? []),
      createdAt: getDateTimeFromTimestamp(json['createdAt']),
      updatedAt: getDateTimeFromTimestamp(json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'role': role.toString().split('.').last,
      'delegations': delegations,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  UserModel copyWith({
    String? id,
    String? name,
    String? email,
    UserRole? role,
    List<String>? delegations,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
      delegations: delegations ?? this.delegations,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

// Topic model
class TopicModel {
  final String id;
  final String title;
  final String description;
  final DateTime createdAt;
  final DateTime updatedAt;

  TopicModel({
    required this.id,
    required this.title,
    required this.description,
    required this.createdAt,
    required this.updatedAt,
  });

  factory TopicModel.fromJson(Map<String, dynamic> json) {
    // Handle potentially missing id
    String id = '';
    if (json['id'] != null) {
      id = json['id'].toString();
    } else {
      print('Warning: Topic missing ID in Firestore. Using empty string.');
    }
    
    // Handle timestamps that might be missing or of different types
    DateTime createdAt = DateTime.now();
    if (json['createdAt'] != null) {
      if (json['createdAt'] is Timestamp) {
        createdAt = (json['createdAt'] as Timestamp).toDate();
      } else if (json['createdAt'] is DateTime) {
        createdAt = json['createdAt'] as DateTime;
      }
    }
    
    DateTime updatedAt = DateTime.now();
    if (json['updatedAt'] != null) {
      if (json['updatedAt'] is Timestamp) {
        updatedAt = (json['updatedAt'] as Timestamp).toDate();
      } else if (json['updatedAt'] is DateTime) {
        updatedAt = json['updatedAt'] as DateTime;
      }
    }
    
    return TopicModel(
      id: id,
      title: json['title'] as String? ?? 'Untitled Topic',
      description: json['description'] as String? ?? 'No description provided',
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}

// Proposal model
class ProposalModel {
  final String id;
  final String title;
  final String content;
  final String authorId;
  final String topicId;
  final ProposalStatus status;
  final List<String> supporters;
  final VotingMethod? preferredVotingMethod; // Proposer's preferred voting method
  final DateTime? voteStartDate;
  final DateTime? phaseEndDate; // When the current phase ends
  final Map<String, dynamic>? votingResults; // Store voting results
  final String? closedReason; // Reason for closure if not successful
  final DateTime createdAt;
  final DateTime updatedAt;

  ProposalModel({
    required this.id,
    required this.title,
    required this.content,
    required this.authorId,
    required this.topicId,
    required this.status,
    this.supporters = const [],
    this.preferredVotingMethod,
    this.voteStartDate,
    this.phaseEndDate,
    this.votingResults,
    this.closedReason,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ProposalModel.fromJson(Map<String, dynamic> json) {
    // Handle Timestamp conversions safely
    DateTime getDateTimeFromTimestamp(dynamic timestamp) {
      if (timestamp is Timestamp) {
        return timestamp.toDate();
      } else if (timestamp is DateTime) {
        return timestamp;
      }
      return DateTime.now(); // Default fallback
    }

    // Parse proposal status
    ProposalStatus parseStatus(String? statusStr) {
      if (statusStr == null) return ProposalStatus.draft;
      return ProposalStatus.values.firstWhere(
        (e) =>
            e.toString().split('.').last.toLowerCase() ==
            statusStr.toLowerCase(),
        orElse: () => ProposalStatus.draft,
      );
    }

    // Parse required fields with null safety
    final id = json['id'] as String? ?? '';
    final authorId = json['authorId'] as String? ?? '';
    final topicId = json['topicId'] as String? ?? '';

    if (id.isEmpty || authorId.isEmpty || topicId.isEmpty) {
      print(
          'Warning: Creating ProposalModel with empty required fields. JSON: $json');
    }

    // Parse voting method if present
    VotingMethod? parseVotingMethod(String? methodStr) {
      if (methodStr == null) return null;
      try {
        return VotingMethod.values.firstWhere(
          (method) => method.toString().split('.').last.toLowerCase() == methodStr.toLowerCase(),
        );
      } catch (e) {
        return null;
      }
    }
    
    return ProposalModel(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Untitled Proposal',
      content: json['content'] as String? ?? '',
      authorId: json['authorId'] as String? ?? '',
      topicId: json['topicId'] as String? ?? '',
      status: parseStatus(json['status'] as String?),
      supporters: List<String>.from(json['supporters'] ?? []),
      preferredVotingMethod: parseVotingMethod(json['preferredVotingMethod'] as String?),
      voteStartDate: json['voteStartDate'] != null
          ? getDateTimeFromTimestamp(json['voteStartDate'])
          : null,
      phaseEndDate: json['phaseEndDate'] != null
          ? getDateTimeFromTimestamp(json['phaseEndDate'])
          : null,
      votingResults: json['votingResults'] as Map<String, dynamic>?,
      closedReason: json['closedReason'] as String?,
      createdAt: getDateTimeFromTimestamp(json['createdAt']),
      updatedAt: getDateTimeFromTimestamp(json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'authorId': authorId,
      'topicId': topicId,
      'status': status.toString().split('.').last,
      'supporters': supporters,
      'preferredVotingMethod': preferredVotingMethod?.toString().split('.').last,
      'voteStartDate': voteStartDate,
      'phaseEndDate': phaseEndDate,
      'votingResults': votingResults,
      'closedReason': closedReason,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  ProposalModel copyWith({
    String? id,
    String? title,
    String? content,
    String? authorId,
    String? topicId,
    ProposalStatus? status,
    List<String>? supporters,
    VotingMethod? preferredVotingMethod,
    DateTime? voteStartDate,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ProposalModel(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      authorId: authorId ?? this.authorId,
      topicId: topicId ?? this.topicId,
      status: status ?? this.status,
      supporters: supporters ?? this.supporters,
      preferredVotingMethod: preferredVotingMethod ?? this.preferredVotingMethod,
      voteStartDate: voteStartDate ?? this.voteStartDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

// Vote Session model
class VoteSessionModel {
  final String id;
  final String proposalId;
  final VotingMethod method;
  final List<String> options;
  final DateTime startDate;
  final DateTime endDate;
  final VoteSessionStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  VoteSessionModel({
    required this.id,
    required this.proposalId,
    required this.method,
    required this.options,
    required this.startDate,
    required this.endDate,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory VoteSessionModel.fromJson(Map<String, dynamic> json) {
    return VoteSessionModel(
      id: json['id'] as String,
      proposalId: json['proposalId'] as String,
      method: VotingMethod.values.firstWhere(
        (method) => method.toString().split('.').last == json['method'],
        orElse: () => VotingMethod.firstPastThePost,
      ),
      options: List<String>.from(json['options'] ?? []),
      startDate: (json['startDate'] as Timestamp).toDate(),
      endDate: (json['endDate'] as Timestamp).toDate(),
      status: VoteSessionStatus.values.firstWhere(
        (status) => status.toString().split('.').last == json['status'],
        orElse: () => VoteSessionStatus.upcoming,
      ),
      createdAt: (json['createdAt'] as Timestamp).toDate(),
      updatedAt: (json['updatedAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'proposalId': proposalId,
      'method': method.toString().split('.').last,
      'options': options,
      'startDate': startDate,
      'endDate': endDate,
      'status': status.toString().split('.').last,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}

// Vote model
class VoteModel {
  final String id;
  final String userId;
  final String proposalId;
  final dynamic choice; // Can be a single string, list of strings, map of ranks, etc.
  final bool isDelegated;
  final String? delegatedBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final double weight;
  final String? topicId;

  VoteModel({
    required this.id,
    required this.userId,
    required this.proposalId,
    required this.choice,
    this.isDelegated = false,
    this.delegatedBy,
    required this.createdAt,
    required this.updatedAt,
    this.weight = 1.0,
    this.topicId,
  });

  factory VoteModel.fromJson(Map<String, dynamic> json) {
    // Handle Timestamp conversions safely
    DateTime getDateTimeFromTimestamp(dynamic timestamp) {
      if (timestamp is Timestamp) {
        return timestamp.toDate();
      } else if (timestamp is DateTime) {
        return timestamp;
      }
      // Fallback for older data or if not a Timestamp/DateTime
      try {
        if (timestamp is Map && timestamp.containsKey('_seconds')) {
          return Timestamp(timestamp['_seconds'], timestamp['_nanoseconds']).toDate();
        }
      } catch (_){}
      return DateTime.now(); // Default fallback if parsing fails
    }

    return VoteModel(
      id: json['id'] as String,
      userId: json['userId'] as String,
      proposalId: json['proposalId'] as String,
      choice: json['choice'], // Keep as dynamic, handle specific types in consuming code
      isDelegated: json['isDelegated'] as bool? ?? false,
      delegatedBy: json['delegatedBy'] as String?,
      createdAt: getDateTimeFromTimestamp(json['createdAt']),
      updatedAt: getDateTimeFromTimestamp(json['updatedAt']),
      weight: (json['weight'] as num?)?.toDouble() ?? 1.0, // Default to 1.0 if null or not present
      topicId: json['topicId'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'proposalId': proposalId,
      'choice': choice,
      'isDelegated': isDelegated,
      'delegatedBy': delegatedBy,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'weight': weight,
      'topicId': topicId,
    };
  }
}

// Delegation model
class DelegationModel {
  final String id;
  final String delegatorId; // User who delegates their vote
  final String delegateeId; // User who receives the delegation
  final bool active;
  final String? topicId; // Optional: Delegation can be topic-specific
  final double weight; // Voting weight of this delegation (e.g., 1.0 for full, 0.5 for half)
  final DateTime validUntil; // Expiration date for delegation
  final DateTime createdAt;
  final DateTime updatedAt;

  DelegationModel({
    required this.id,
    required this.delegatorId,
    required this.delegateeId,
    this.active = true,
    this.topicId,
    this.weight = 1.0, // Default to full weight
    required this.validUntil,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DelegationModel.fromJson(Map<String, dynamic> json) {
    return DelegationModel(
      id: json['id'] as String,
      delegatorId: json['delegatorId'] as String,
      delegateeId: json['delegateeId'] as String,
      active: json['active'] as bool? ?? true,
      topicId: json['topicId'] as String?,
      weight: (json['weight'] as num?)?.toDouble() ?? 1.0, // Parse weight, default to 1.0
      validUntil: (json['validUntil'] as Timestamp).toDate(),
      createdAt: (json['createdAt'] as Timestamp).toDate(),
      updatedAt: (json['updatedAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'delegatorId': delegatorId,
      'delegateeId': delegateeId,
      'active': active,
      'topicId': topicId,
      'weight': weight, // Add weight to JSON
      'validUntil': validUntil,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}

// DelegationInfo model - Combines DelegationModel with UserModel for delegator and delegatee
class DelegationInfo {
  final DelegationModel delegation;
  final UserModel delegatorUser;
  final UserModel delegateeUser;

  DelegationInfo({
    required this.delegation,
    required this.delegatorUser,
    required this.delegateeUser,
  });

  // Optional: Add fromJson/toJson if needed for direct serialization,
  // but often this class is constructed in the service layer.
}

// Group model
class GroupModel {
  final String id;
  final String name;
  final List<String> memberIds;
  final String? description;
  final DateTime createdAt;
  final DateTime updatedAt;

  GroupModel({
    required this.id,
    required this.name,
    required this.memberIds,
    this.description,
    required this.createdAt,
    required this.updatedAt,
  });

  factory GroupModel.fromJson(Map<String, dynamic> json) {
    return GroupModel(
      id: json['id'] as String,
      name: json['name'] as String,
      memberIds: List<String>.from(json['memberIds'] ?? []),
      description: json['description'] as String?,
      createdAt: (json['createdAt'] as Timestamp).toDate(),
      updatedAt: (json['updatedAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'memberIds': memberIds,
      'description': description,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}

// Comment model
class CommentModel {
  final String id;
  final String proposalId;
  final String authorId;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;

  CommentModel({
    required this.id,
    required this.proposalId,
    required this.authorId,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CommentModel.fromJson(Map<String, dynamic> json) {
    return CommentModel(
      id: json['id'] as String,
      proposalId: json['proposalId'] as String,
      authorId: json['authorId'] as String,
      content: json['content'] as String,
      createdAt: (json['createdAt'] as Timestamp).toDate(),
      updatedAt: (json['updatedAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'proposalId': proposalId,
      'authorId': authorId,
      'content': content,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
