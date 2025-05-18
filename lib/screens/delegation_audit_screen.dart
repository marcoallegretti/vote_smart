import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../models/audit_model.dart';
import '../models/data_models.dart';
import '../services/audit_service.dart';
import '../services/database_service.dart';
import '../widgets/loading_indicator.dart';

class DelegationAuditScreen extends StatefulWidget {
  final DatabaseService databaseService;
  final AuditService auditService;
  final String? delegationId;

  const DelegationAuditScreen({
    super.key,
    required this.databaseService,
    required this.auditService,
    this.delegationId,
  });

  @override
  State<DelegationAuditScreen> createState() => _DelegationAuditScreenState();
}

class _DelegationAuditScreenState extends State<DelegationAuditScreen> {
  bool _isLoading = true;
  List<AuditLogEntry> _auditEntries = [];
  final Map<String, UserModel> _userCache = {};
  final Map<String, DelegationModel> _delegationCache = {};
  final Map<String, TopicModel> _topicCache = {};
  final _dateFormat = DateFormat('MMM d, yyyy HH:mm:ss');

  @override
  void initState() {
    super.initState();
    _loadAuditTrail();
  }

  Future<void> _loadAuditTrail() async {
    setState(() {
      _isLoading = true;
    });

    try {
      Query query = FirebaseFirestore.instance
          .collection('audit_trails')
          .where('entityType', isEqualTo: 'DELEGATION')
          .orderBy('timestamp', descending: true)
          .limit(100);

      // If a specific delegation ID is provided, filter by it
      if (widget.delegationId != null) {
        query = query.where('entityId', isEqualTo: widget.delegationId);
      }

      final snapshot = await query.get();
      final entries = snapshot.docs.map((doc) {
        return AuditLogEntry.fromJson(
            doc.data() as Map<String, dynamic>, doc.id);
      }).toList();

      setState(() {
        _auditEntries = entries;
        _isLoading = false;
      });

      // Preload user and delegation data for display
      _preloadRelatedData();
    } catch (e) {
      print('Error loading audit trail: $e');
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackBar('Failed to load audit trail');
    }
  }

  Future<void> _preloadRelatedData() async {
    final userIds = <String>{};
    final delegationIds = <String>{};
    final topicIds = <String>{};

    // Collect all user IDs and delegation IDs
    for (final entry in _auditEntries) {
      if (entry.actorUserId.isNotEmpty) userIds.add(entry.actorUserId);
      if (entry.targetUserId != null && entry.targetUserId!.isNotEmpty) {
        userIds.add(entry.targetUserId!);
      }
      if (entry.entityId != null && entry.entityType == 'DELEGATION') {
        delegationIds.add(entry.entityId!);
      }

      // Extract topic IDs from details if available
      if (entry.details.containsKey('topicId') &&
          entry.details['topicId'] != null &&
          entry.details['topicId'] is String &&
          entry.details['topicId'].isNotEmpty) {
        topicIds.add(entry.details['topicId']);
      }
    }

    // Fetch users in batch
    for (final userId in userIds) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .get();
        if (doc.exists && doc.data() != null) {
          final user = UserModel.fromJson({'id': doc.id, ...doc.data()!});
          if (mounted) {
            setState(() {
              _userCache[userId] = user;
            });
          }
        }
      } catch (e) {
        print('Error fetching user $userId: $e');
      }
    }

    // Fetch delegations in batch
    for (final delegationId in delegationIds) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('delegations')
            .doc(delegationId)
            .get();
        if (doc.exists && doc.data() != null) {
          final delegation =
              DelegationModel.fromJson({'id': doc.id, ...doc.data()!});
          if (mounted) {
            setState(() {
              _delegationCache[delegationId] = delegation;
            });
          }
        }
      } catch (e) {
        print('Error fetching delegation $delegationId: $e');
      }
    }

    // Fetch topics in batch
    for (final topicId in topicIds) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('topics')
            .doc(topicId)
            .get();
        if (doc.exists && doc.data() != null) {
          final topic = TopicModel.fromJson({'id': doc.id, ...doc.data()!});
          if (mounted) {
            setState(() {
              _topicCache[topicId] = topic;
            });
          }
        }
      } catch (e) {
        print('Error fetching topic $topicId: $e');
      }
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.delegationId != null
            ? 'Delegation Audit Trail'
            : 'Delegation Audit Trails'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAuditTrail,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: LoadingIndicator())
          : _auditEntries.isEmpty
              ? _buildEmptyState()
              : _buildAuditList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.history,
            size: 64,
            color: Colors.grey,
          ),
          const SizedBox(height: 16),
          Text(
            'No audit records found',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Delegation activity will be recorded here',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildAuditList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _auditEntries.length,
      itemBuilder: (context, index) {
        return _buildAuditCard(_auditEntries[index]);
      },
    );
  }

  Widget _buildAuditCard(AuditLogEntry entry) {
    final timestamp = _dateFormat.format(entry.timestamp.toDate());
    final eventTypeStr = auditEventTypeToString(entry.eventType);

    Color cardColor;
    IconData eventIcon;

    switch (entry.eventType) {
      case AuditEventType.DELEGATION_CREATED:
        cardColor = Colors.green.shade50;
        eventIcon = Icons.add_circle;
        break;
      case AuditEventType.DELEGATION_REVOKED:
        cardColor = Colors.red.shade50;
        eventIcon = Icons.cancel;
        break;
      case AuditEventType.DELEGATION_UPDATED:
        cardColor = Colors.blue.shade50;
        eventIcon = Icons.edit;
        break;
      case AuditEventType.DELEGATION_EXPIRED:
        cardColor = Colors.orange.shade50;
        eventIcon = Icons.timer_off;
        break;
      default:
        cardColor = Colors.grey.shade50;
        eventIcon = Icons.info;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(eventIcon, color: Theme.of(context).primaryColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    eventTypeStr.replaceAll('_', ' '),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                Text(
                  timestamp,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const Divider(),
            _buildUserInfo('Actor', entry.actorUserId),
            if (entry.targetUserId != null)
              _buildUserInfo('Target', entry.targetUserId!),
            const SizedBox(height: 8),
            _buildDetailsSection(entry),
          ],
        ),
      ),
    );
  }

  Widget _buildUserInfo(String label, String userId) {
    final user = _userCache[userId];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Expanded(
            child: user != null
                ? Text('${user.name} (${user.email})')
                : Text(userId),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsSection(AuditLogEntry entry) {
    final List<Widget> detailWidgets = [];

    // Add delegation info if available
    if (entry.entityId != null &&
        _delegationCache.containsKey(entry.entityId)) {
      final delegation = _delegationCache[entry.entityId]!;

      // Add delegator info
      if (_userCache.containsKey(delegation.delegatorId)) {
        detailWidgets.add(_buildDetailRow(
            'Delegator', _userCache[delegation.delegatorId]!.name));
      }

      // Add delegatee info
      if (_userCache.containsKey(delegation.delegateeId)) {
        detailWidgets.add(_buildDetailRow(
            'Delegatee', _userCache[delegation.delegateeId]!.name));
      }

      // Add topic info if available
      if (delegation.topicId != null &&
          _topicCache.containsKey(delegation.topicId)) {
        detailWidgets.add(
            _buildDetailRow('Topic', _topicCache[delegation.topicId]!.title));
      } else if (delegation.topicId == null) {
        detailWidgets.add(_buildDetailRow('Topic', 'General (All Topics)'));
      }

      // Add weight info
      detailWidgets
          .add(_buildDetailRow('Weight', delegation.weight.toString()));

      // Add valid until info
      detailWidgets.add(_buildDetailRow(
          'Valid Until', _dateFormat.format(delegation.validUntil)));
    }

    // Add any additional details from the entry
    entry.details.forEach((key, value) {
      if (key != 'topicId' && value != null) {
        // Skip topicId as we already handled it
        detailWidgets.add(_buildDetailRow(
            key.replaceFirst(key[0], key[0].toUpperCase()).replaceAll('_', ' '),
            value.toString()));
      }
    });

    if (detailWidgets.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Details:',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        ...detailWidgets,
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 4, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
}
