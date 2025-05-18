import 'package:cloud_firestore/cloud_firestore.dart';

enum AuditEventType {
  // Delegation Events
  DELEGATION_CREATED,
  DELEGATION_REVOKED,
  DELEGATION_UPDATED, // For changes like weight or validUntil
  DELEGATION_EXPIRED, // If we implement active logging for this

  // Vote Events
  VOTE_CAST,
  VOTE_PROPAGATED, // Could signify the result of a propagation
  VOTE_RETRACTED,

  // User Management (Placeholder for future)
  // USER_REGISTERED,
  // USER_PROFILE_UPDATED,
}

String auditEventTypeToString(AuditEventType type) {
  return type.toString().split('.').last;
}

AuditEventType auditEventTypeFromString(String typeString) {
  return AuditEventType.values.firstWhere(
    (e) => e.toString().split('.').last == typeString,
    orElse: () => throw ArgumentError('Unknown AuditEventType string: $typeString'),
  );
}

class AuditLogEntry {
  final String id; // Document ID
  final Timestamp timestamp;
  final AuditEventType eventType;
  final String actorUserId; // User who performed the action
  final String? targetUserId; // User/entity directly affected
  final String? entityId; // ID of the primary entity (delegationId, proposalId, voteId)
  final String? entityType; // e.g., "DELEGATION", "PROPOSAL", "VOTE"
  final Map<String, dynamic> details; // Event-specific data

  AuditLogEntry({
    required this.id,
    required this.timestamp,
    required this.eventType,
    required this.actorUserId,
    this.targetUserId,
    this.entityId,
    this.entityType,
    this.details = const {},
  });

  factory AuditLogEntry.fromJson(Map<String, dynamic> json, String id) {
    return AuditLogEntry(
      id: id,
      timestamp: json['timestamp'] as Timestamp,
      eventType: auditEventTypeFromString(json['eventType'] as String),
      actorUserId: json['actorUserId'] as String,
      targetUserId: json['targetUserId'] as String?,
      entityId: json['entityId'] as String?,
      entityType: json['entityType'] as String?,
      details: Map<String, dynamic>.from(json['details'] ?? {}),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp,
      'eventType': auditEventTypeToString(eventType),
      'actorUserId': actorUserId,
      'targetUserId': targetUserId,
      'entityId': entityId,
      'entityType': entityType,
      'details': details,
    };
  }
}
