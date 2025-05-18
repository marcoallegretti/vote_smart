import 'package:flutter/material.dart';
// import 'package:firebase_auth/firebase_auth.dart'; // Removed unused import
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../models/data_models.dart';
import '../services/delegation_service.dart';
import '../services/audit_service.dart';
import '../services/database_service.dart';
import 'advanced_delegate_selector.dart';
import 'loading_indicator.dart';

class CreateDelegationDialog extends StatefulWidget {
  final List<UserModel> potentialDelegates;
  final String? topicId;
  final String? topicTitle;
  final VoidCallback onDelegationCreated;
  final DatabaseService databaseService;
  final AuditService auditService;

  const CreateDelegationDialog({
    super.key,
    required this.potentialDelegates,
    this.topicId,
    this.topicTitle,
    required this.onDelegationCreated,
    required this.databaseService,
    required this.auditService,
  });

  @override
  State<CreateDelegationDialog> createState() => _CreateDelegationDialogState();
}

class _CreateDelegationDialogState extends State<CreateDelegationDialog> {
  late final DelegationService _delegationService;
  UserModel? _selectedDelegate;
  DateTime _validUntil = DateTime.now().add(const Duration(days: 30));
  bool _isCreating = false;
  bool _showAdvancedInfo = false;
  double _delegateWeight = 1.0;

  @override
  void initState() {
    super.initState();
    _delegationService = DelegationService.withInstance(
      firestoreInstance: FirebaseFirestore.instance,
      databaseService: widget.databaseService,
      auditService: widget.auditService,
    );
    _loadDelegateWeightInfo();
  }

  Future<void> _loadDelegateWeightInfo() async {
    if (_selectedDelegate != null) {
      try {
        final weight = await _delegationService
            .calculateRepresentedVoterCount(_selectedDelegate!.id);
        setState(() {
          _delegateWeight = weight;
        });
      } catch (e) {
        print('Error loading delegate weight: $e');
      }
    }
  }

  Future<void> _createDelegation() async {
    if (_selectedDelegate == null) {
      _showErrorSnackBar('Please select a delegate');
      return;
    }

    setState(() {
      _isCreating = true;
    });

    try {
      // Check for circular delegation
      final userId = _delegationService.currentUserId;
      if (userId != null) {
        final wouldCreateCircular =
            await _delegationService.wouldCreateCircularDelegation(
          _selectedDelegate!.id,
          topicId: widget.topicId,
        );

        if (wouldCreateCircular) {
          setState(() {
            _isCreating = false;
          });
          _showErrorSnackBar(
              'This delegation would create a circular chain, which is not allowed');
          return;
        }
      }

      await _delegationService.createDelegation(
        delegateeId: _selectedDelegate!.id,
        topicId: widget.topicId,
        validUntil: _validUntil,
      );

      if (mounted) {
        Navigator.of(context).pop();
        widget.onDelegationCreated();
      }
    } catch (e) {
      setState(() {
        _isCreating = false;
      });
      _showErrorSnackBar('Failed to create delegation: ${e.toString()}');
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

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _validUntil,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null && picked != _validUntil) {
      setState(() {
        _validUntil = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.how_to_vote,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Create Delegation${widget.topicId != null ? ' for ${widget.topicTitle}' : ''}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: _isCreating
                  ? const Center(child: LoadingIndicator())
                  : Column(
                      children: [
                        const Padding(
                          padding:
                              EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Text(
                            'Select a delegate to vote on your behalf. They will receive your voting power for all proposals unless you choose to vote directly.',
                            style: TextStyle(fontSize: 14),
                          ),
                        ),
                        Expanded(
                          child: AdvancedDelegateSelector(
                            onDelegateSelected: (delegate) {
                              setState(() {
                                _selectedDelegate = delegate;
                              });
                              _loadDelegateWeightInfo();
                            },
                            topicId: widget.topicId,
                            databaseService: widget.databaseService,
                            auditService: widget.auditService,
                          ),
                        ),
                      ],
                    ),
            ),
            if (_selectedDelegate != null) _buildSelectedDelegateInfo(),
            _buildValidityPeriod(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('CANCEL'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed:
                        _selectedDelegate != null ? _createDelegation : null,
                    child: const Text('CREATE DELEGATION'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedDelegateInfo() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primary,
                child: Text(
                  _selectedDelegate!.name.isNotEmpty
                      ? _selectedDelegate!.name[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedDelegate!.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      _selectedDelegate!.email,
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  _showAdvancedInfo ? Icons.visibility_off : Icons.visibility,
                  color: Theme.of(context).colorScheme.primary,
                ),
                onPressed: () {
                  setState(() {
                    _showAdvancedInfo = !_showAdvancedInfo;
                  });
                },
                tooltip: _showAdvancedInfo ? 'Hide Details' : 'Show Details',
              ),
            ],
          ),
          if (_showAdvancedInfo) ...[
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Vote Weight',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.equalizer,
                            size: 16,
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${_delegateWeight.toStringAsFixed(1)}x voting power',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Tooltip(
                  message:
                      'This delegate has ${_delegateWeight.toStringAsFixed(1)}x voting power due to other delegations they have received. Higher voting power indicates more trust from other users.',
                  child: const Icon(Icons.info_outline, size: 16),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildValidityPeriod() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Delegation Valid Until',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: _selectDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today),
                  const SizedBox(width: 8),
                  Text(
                    DateFormat('MMMM dd, yyyy').format(_validUntil),
                    style: const TextStyle(fontSize: 16),
                  ),
                  const Spacer(),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'You can revoke this delegation at any time',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
        ],
      ),
    );
  }
}
