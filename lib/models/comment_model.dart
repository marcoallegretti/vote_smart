import 'package:cloud_firestore/cloud_firestore.dart';

class CommentModel {
  final String id;
  final String proposalId;
  final String authorId;
  final String content;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? parentCommentId; // Null for top-level comments
  final int depth; // 0 for top-level, increments for replies
  final List<String> upvotedBy;
  final List<String> downvotedBy;
  final bool isEdited;
  final bool isModerated;
  final String? moderationReason;
  final String? moderatedBy; // Added
  final DateTime? moderatedAt; // Added
  final List<String>? attachments; // URLs to attached media
  final bool isDeleted; // Added: soft delete
  final DateTime? deletedAt; // Added: when deleted

  CommentModel({
    required this.id,
    required this.proposalId,
    required this.authorId,
    required this.content,
    required this.createdAt,
    this.updatedAt,
    this.parentCommentId,
    required this.depth,
    this.upvotedBy = const [],
    this.downvotedBy = const [],
    this.isEdited = false,
    this.isModerated = false,
    this.moderationReason,
    this.moderatedBy, // Added
    this.moderatedAt, // Added
    this.attachments,
    this.isDeleted = false, // Added
    this.deletedAt, // Added
  });

  // Computed properties
  int get upvotes => upvotedBy.length;
  int get downvotes => downvotedBy.length;
  int get score => upvotes - downvotes;

  CommentModel copyWith({
    String? id,
    String? proposalId,
    String? authorId,
    String? content,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? parentCommentId,
    bool setParentCommentIdToNull = false, 
    int? depth,
    List<String>? upvotedBy,
    List<String>? downvotedBy,
    bool? isEdited,
    bool? isModerated,
    String? moderationReason,
    bool setModerationReasonToNull = false, 
    String? moderatedBy, // Added
    bool setModeratedByToNull = false, // Added
    DateTime? moderatedAt, // Added
    bool setModeratedAtToNull = false, // Added
    List<String>? attachments,
    bool setAttachmentsToNull = false,
    bool? isDeleted, // Added
    DateTime? deletedAt, // Added
  }) {
    return CommentModel(
      id: id ?? this.id,
      proposalId: proposalId ?? this.proposalId,
      authorId: authorId ?? this.authorId,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      parentCommentId: setParentCommentIdToNull ? null : parentCommentId ?? this.parentCommentId,
      depth: depth ?? this.depth,
      upvotedBy: upvotedBy ?? this.upvotedBy,
      downvotedBy: downvotedBy ?? this.downvotedBy,
      isEdited: isEdited ?? this.isEdited,
      isModerated: isModerated ?? this.isModerated,
      moderationReason: setModerationReasonToNull ? null : moderationReason ?? this.moderationReason,
      moderatedBy: setModeratedByToNull ? null : moderatedBy ?? this.moderatedBy, // Added
      moderatedAt: setModeratedAtToNull ? null : moderatedAt ?? this.moderatedAt, // Added
      attachments: setAttachmentsToNull ? null : attachments ?? this.attachments,
      isDeleted: isDeleted ?? this.isDeleted, // Added
      deletedAt: deletedAt ?? this.deletedAt, // Added
    );
  }

  factory CommentModel.fromJson(Map<String, dynamic> json, String id) {
    return CommentModel(
      id: id,
      proposalId: json['proposalId'] as String,
      authorId: json['authorId'] as String,
      content: json['content'] as String,
      createdAt: (json['createdAt'] as Timestamp).toDate(),
      updatedAt: json['updatedAt'] == null
          ? null
          : (json['updatedAt'] as Timestamp).toDate(),
      parentCommentId: json['parentCommentId'] as String?,
      depth: json['depth'] as int,
      upvotedBy: List<String>.from(json['upvotedBy'] ?? []),
      downvotedBy: List<String>.from(json['downvotedBy'] ?? []),
      isEdited: json['isEdited'] as bool? ?? false,
      isModerated: json['isModerated'] as bool? ?? false,
      moderationReason: json['moderationReason'] as String?,
      moderatedBy: json['moderatedBy'] as String?, // Added
      moderatedAt: (json['moderatedAt'] as Timestamp?)?.toDate(), // Added
      attachments: json['attachments'] == null
          ? null
          : List<String>.from(json['attachments']),
      isDeleted: json['isDeleted'] as bool? ?? false, // Added
      deletedAt: (json['deletedAt'] as Timestamp?)?.toDate(), // Added
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'proposalId': proposalId,
      'authorId': authorId,
      'content': content,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
      'parentCommentId': parentCommentId,
      'depth': depth,
      'upvotedBy': upvotedBy,
      'downvotedBy': downvotedBy,
      'isEdited': isEdited,
      'isModerated': isModerated,
      'moderationReason': moderationReason,
      'moderatedBy': moderatedBy, // Added
      'moderatedAt': moderatedAt != null ? Timestamp.fromDate(moderatedAt!) : null, // Added
      'attachments': attachments,
      'isDeleted': isDeleted, // Added
      'deletedAt': deletedAt != null ? Timestamp.fromDate(deletedAt!) : null, // Added
    };
  }
}
