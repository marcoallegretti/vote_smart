import 'package:cloud_firestore/cloud_firestore.dart';

enum NotificationType {
  reply,
  mention,
  upvote,
  moderation,
}

String notificationTypeToString(NotificationType type) {
  return type.toString().split('.').last;
}

NotificationType notificationTypeFromString(String typeString) {
  return NotificationType.values.firstWhere(
    (e) => e.toString().split('.').last == typeString,
    orElse: () => NotificationType.reply, // Default or throw error
  );
}

class CommentNotificationModel {
  final String id;
  final String userId; // User to notify
  final String commentId;
  final String proposalId;
  final String triggerUserId; // User who caused the notification
  final NotificationType type; // Reply, mention, etc.
  final DateTime createdAt;
  final bool isRead;

  CommentNotificationModel({
    required this.id,
    required this.userId,
    required this.commentId,
    required this.proposalId,
    required this.triggerUserId,
    required this.type,
    required this.createdAt,
    this.isRead = false,
  });

  factory CommentNotificationModel.fromJson(Map<String, dynamic> json, String id) {
    return CommentNotificationModel(
      id: id,
      userId: json['userId'] as String,
      commentId: json['commentId'] as String,
      proposalId: json['proposalId'] as String,
      triggerUserId: json['triggerUserId'] as String,
      type: notificationTypeFromString(json['type'] as String),
      createdAt: (json['createdAt'] as Timestamp).toDate(),
      isRead: json['isRead'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'commentId': commentId,
      'proposalId': proposalId,
      'triggerUserId': triggerUserId,
      'type': notificationTypeToString(type),
      'createdAt': Timestamp.fromDate(createdAt),
      'isRead': isRead,
    };
  }
}
