import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';
import '../models/audit_model.dart'; // Adjust import path if necessary

final _logger = Logger();

class AuditService {
  final FirebaseFirestore _firestore;

  AuditService() : _firestore = FirebaseFirestore.instance;

  // Constructor for testing with mock instances
  AuditService.withInstance(this._firestore);

  Future<void> logAuditEvent({
    required AuditEventType eventType,
    required String actorUserId,
    String? targetUserId,
    String? entityId,
    String? entityType,
    Map<String, dynamic> details = const {},
  }) async {
    try {
      final docRef = _firestore.collection('audit_trails').doc();
      final entry = AuditLogEntry(
        id: docRef.id,
        timestamp: Timestamp.now(),
        eventType: eventType,
        actorUserId: actorUserId,
        targetUserId: targetUserId,
        entityId: entityId,
        entityType: entityType,
        details: details,
      );
      await docRef.set(entry.toJson());
      _logger.i('Audit event logged: ${auditEventTypeToString(eventType)} by $actorUserId');
    } catch (e, s) {
      _logger.e('Failed to log audit event', error: e, stackTrace: s);
      // Depending on policy, might rethrow or handle silently
      // For critical audit, rethrowing might be appropriate if logging failure is unacceptable
    }
  }
}
