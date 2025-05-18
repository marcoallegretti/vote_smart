import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/data_models.dart';
import '../services/delegation_service.dart';
import '../services/audit_service.dart';
import '../services/database_service.dart';
import '../screens/delegation_screen.dart';

class DelegationManagerWidget extends StatefulWidget {
  final String? topicId;
  final String? topicTitle;
  final VoidCallback? onDelegationChanged;
  final DatabaseService databaseService;
  final AuditService auditService;

  const DelegationManagerWidget({
    super.key,
    this.topicId,
    this.topicTitle,
    this.onDelegationChanged,
    required this.databaseService,
    required this.auditService,
  });

  @override
  State<DelegationManagerWidget> createState() =>
      _DelegationManagerWidgetState();
}

class _DelegationManagerWidgetState extends State<DelegationManagerWidget> {
  late final DelegationService _delegationService;
  bool _isLoading = false;
  bool _hasDelegation = false;
  List<DelegationModel> _activeDelegations = [];

  @override
  void initState() {
    super.initState();
    _delegationService = DelegationService(
      firestore: FirebaseFirestore.instance,
      databaseService: widget.databaseService,
      auditService: widget.auditService,
    );
    _checkDelegationStatus();
  }

  Future<void> _checkDelegationStatus() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final List<DelegationInfo> activeDelegationsInfo = await _delegationService.getMyDelegations(
        topicId: widget.topicId,
      );
      final List<DelegationModel> activeDelegations = activeDelegationsInfo.map((info) => info.delegation).toList();

      final bool hasDelegation = activeDelegations.isNotEmpty;

      if (mounted) {
        setState(() {
          _hasDelegation = hasDelegation;
          _activeDelegations = activeDelegations;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error checking delegation status: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _navigateToDelegationScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => DelegationScreen(
          topicId: widget.topicId,
          databaseService: widget.databaseService,
          auditService: widget.auditService,
        ),
      ),
    );

    if (mounted) {
      _checkDelegationStatus();
      if (widget.onDelegationChanged != null) {
        widget.onDelegationChanged!();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.how_to_vote,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Liquid Democracy',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Spacer(),
                _isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _hasDelegation
                            ? Icons.check_circle
                            : Icons.info_outline,
                        color: _hasDelegation ? Colors.green : Colors.orange,
                      ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _hasDelegation
                  ? 'You have delegated your vote${widget.topicId != null ? ' for this topic' : ''}.'
                  : 'You can delegate your vote to someone you trust.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (_hasDelegation && _activeDelegations.isNotEmpty) ...[
              const SizedBox(height: 8),
              FutureBuilder<UserModel?>(
                future: _getUserInfo(_activeDelegations.first.delegateeId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Text('Loading delegate info...');
                  }

                  final user = snapshot.data;
                  return Text(
                    'Delegated to: ${user?.name ?? 'Unknown User'}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  );
                },
              ),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton.icon(
                  onPressed: _navigateToDelegationScreen,
                  icon: Icon(_hasDelegation ? Icons.edit : Icons.person_add),
                  label: Text(_hasDelegation
                      ? 'Manage Delegations'
                      : 'Delegate Your Vote'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.secondary,
                    foregroundColor: Theme.of(context).colorScheme.onSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<UserModel?> _getUserInfo(String userId) async {
    try {
      final firestore = FirebaseFirestore.instance;
      final doc = await firestore.collection('users').doc(userId).get();

      if (doc.exists) {
        return UserModel.fromJson({
          'id': doc.id,
          ...doc.data()!,
        });
      }

      return null;
    } catch (e) {
      print('Error getting user info: $e');
      return null;
    }
  }
}
