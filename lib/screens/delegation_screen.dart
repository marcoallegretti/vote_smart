import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';
import '../models/data_models.dart';
import '../services/delegation_service.dart';
import '../services/audit_service.dart';
import '../services/database_service.dart';
import '../widgets/loading_indicator.dart';
import 'delegation_visualization_screen.dart';
import 'delegation_audit_screen.dart';
import 'delegation_management_screen.dart';

class DelegationScreen extends StatefulWidget {
  final String? topicId;
  final String? topicTitle;
  final DatabaseService databaseService;
  final AuditService auditService;

  const DelegationScreen({
    super.key,
    this.topicId,
    this.topicTitle,
    required this.databaseService,
    required this.auditService,
  });

  @override
  State<DelegationScreen> createState() => _DelegationScreenState();
}

class _DelegationScreenState extends State<DelegationScreen>
    with SingleTickerProviderStateMixin {
  late final DelegationService _delegationService;
  final Logger _logger = Logger(); // Logger for this state
  bool _isLoading = false;
  List<DelegationModel> _myDelegations = [];
  List<DelegationModel> _delegationsToMe = [];
  final List<UserModel> _potentialDelegates = [];
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _delegationService = DelegationService(
      firestore: FirebaseFirestore.instance,
      databaseService: widget.databaseService,
      auditService: widget.auditService,
    );
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final List<DelegationInfo> myDelegationsInfo =
          await _delegationService.getMyDelegations(
        topicId: widget.topicId,
      );
      final List<DelegationInfo> delegationsToMeInfo =
          await _delegationService.getDelegationsToMe(
        topicId: widget.topicId,
      );

      final myDelegations =
          myDelegationsInfo.map((info) => info.delegation).toList();
      final delegationsToMe =
          delegationsToMeInfo.map((info) => info.delegation).toList();

      if (mounted) {
        setState(() {
          _myDelegations = myDelegations;
          _delegationsToMe = delegationsToMe;
          _isLoading = false;
        });
      }
    } catch (e) {
      _logger.i('Error loading delegations: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  
  void _navigateToVisualization() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => DelegationVisualizationScreen(
          databaseService: widget.databaseService,
          auditService: widget.auditService,
          topicId: widget.topicId,
        ),
      ),
    ).then((_) => _loadData());
  }
  
  void _navigateToAuditTrail() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => DelegationAuditScreen(
          databaseService: widget.databaseService,
          auditService: widget.auditService,
        ),
      ),
    ).then((_) => _loadData());
  }
  
  void _navigateToManagement() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => DelegationManagementScreen(
          databaseService: widget.databaseService,
          auditService: widget.auditService,
        ),
      ),
    ).then((_) => _loadData());
  }

  Widget _buildDelegationsList(
      List<DelegationModel> delegations, bool isOutgoing) {
    if (delegations.isEmpty) {
      return Center(
          child: Text(isOutgoing
              ? 'You have not delegated your vote to anyone.'
              : 'No one has delegated their vote to you.'));
    }
    return ListView.builder(
      itemCount: delegations.length,
      itemBuilder: (context, index) {
        final delegation = delegations[index];
        return DelegationCard(
          delegation: delegation,
          isOutgoing: isOutgoing,
          onRevoke: () => _revokeDelegation(delegation.id),
          logger: _logger, // Pass logger to DelegationCard
        );
      },
    );
  }

  void _revokeDelegation(String delegationId) async {
    final bool? confirmRevoke = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return RevokeDelegationDialog(
          delegationId: delegationId,
          delegationService: _delegationService,
          databaseService: widget.databaseService,
          auditService: widget.auditService,
        );
      },
    );

    if (confirmRevoke == true) {
      try {
        _showSuccessSnackBar('Delegation revoked successfully.');
        _loadData(); // Refresh the list
      } catch (e) {
        _logger.i('Error revoking delegation (in _DelegationScreenState): $e');
        _showErrorSnackBar('Failed to revoke delegation: $e');
      }
    }
  }

  void _showCreateDelegationDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return CreateDelegationDialog(
          potentialDelegates: _potentialDelegates,
          topicId: widget.topicId,
          databaseService: widget.databaseService,
          auditService: widget.auditService,
          onDelegationCreated: () {
            _loadData(); // Refresh data after new delegation
          },
        );
      },
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.green));
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red));
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.topicId != null
            ? 'Topic Delegations'
            : 'My Delegations'),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_tree),
            onPressed: _navigateToVisualization,
            tooltip: 'View Delegation Network',
          ),
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: _navigateToAuditTrail,
            tooltip: 'View Audit Trail',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _navigateToManagement,
            tooltip: 'Advanced Management',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'My Delegations'),
            Tab(text: 'Delegated to Me'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: LoadingIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildDelegationsList(_myDelegations, true),
                _buildDelegationsList(_delegationsToMe, false),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateDelegationDialog,
        tooltip: 'Create Delegation',
        child: const Icon(Icons.add),
      ),
    );
  }
}

class DelegationCard extends StatelessWidget {
  final DelegationModel delegation;
  final bool isOutgoing;
  final VoidCallback onRevoke;
  final Logger logger;

  const DelegationCard({
    super.key,
    required this.delegation,
    required this.isOutgoing,
    required this.onRevoke,
    required this.logger,
  });

  Future<UserModel?> _getUserInfo(String userId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      if (doc.exists) {
        return UserModel.fromJson({
          'id': doc.id,
          ...doc.data()!,
        });
      }
      return null;
    } catch (e) {
      logger.i('Error getting user info: $e');
      return null;
    }
  }

  Future<TopicModel?> _getTopicInfo(String topicId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('topics')
          .doc(topicId)
          .get();
      if (doc.exists) {
        return TopicModel.fromJson({
          'id': doc.id,
          ...doc.data()!,
        });
      }
      return null;
    } catch (e) {
      logger.i('Error getting topic info: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat.yMMMd();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: FutureBuilder<TopicModel?>(
                    // Corrected: Added '!' as topicId is checked for null
                    future: delegation.topicId != null
                        ? _getTopicInfo(delegation.topicId!)
                        : Future.value(null),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Text('Topic: Loading...',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold));
                      }
                      return Text(
                        'Topic: ${snapshot.data?.title ?? 'All Topics'}',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      );
                    },
                  ),
                ),
                if (isOutgoing)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: onRevoke,
                    tooltip: 'Revoke Delegation',
                  ),
              ],
            ),
            const SizedBox(height: 12),
            FutureBuilder<UserModel?>(
              future: _getUserInfo(
                  isOutgoing ? delegation.delegateeId : delegation.delegatorId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const CircularProgressIndicator();
                }
                if (snapshot.hasError) {
                  logger.i('Error loading user details: ${snapshot.error}');
                  return Text('Error: ${snapshot.error}');
                }
                final user = snapshot.data;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    child:
                        Text(user?.name.substring(0, 1).toUpperCase() ?? '?'),
                  ),
                  title: Text(user?.name ?? 'Unknown User'),
                  subtitle: Text(user?.email ?? ''),
                );
              },
            ),
            const Divider(),
            Row(
              children: [
                const Icon(Icons.calendar_today, size: 16),
                const SizedBox(width: 8),
                Text(
                    'Valid Until: ${dateFormat.format(delegation.validUntil)}'),
              ],
            ),
            // Reverted: Removed '!' for comparison as linter suggests type promotion
            if (delegation.weight < 1.0)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                // Reverted: Removed '!' for calculation as linter suggests type promotion
                child: Text(
                    'Vote Weight: ${(delegation.weight * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.secondary)),
              )
          ],
        ),
      ),
    );
  }
}

class CreateDelegationDialog extends StatefulWidget {
  final List<UserModel> potentialDelegates;
  final String? topicId;
  final DatabaseService databaseService;
  final AuditService auditService;
  final VoidCallback onDelegationCreated;

  const CreateDelegationDialog({
    super.key,
    required this.potentialDelegates,
    this.topicId,
    required this.databaseService,
    required this.auditService,
    required this.onDelegationCreated,
  });

  @override
  CreateDelegationDialogState createState() => CreateDelegationDialogState();
}

class CreateDelegationDialogState extends State<CreateDelegationDialog> {
  late final DelegationService _delegationService;
  final Logger _logger = Logger();
  String? _selectedDelegateId;
  DateTime _validUntil = DateTime.now().add(const Duration(days: 30));
  double _selectedWeight = 1.0;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _delegationService = DelegationService.withInstance(
      firestoreInstance: FirebaseFirestore.instance,
      databaseService: widget.databaseService,
      auditService: widget.auditService,
    );
  }

  Future<void> _createDelegation() async {
    if (_selectedDelegateId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please select a delegate'),
            backgroundColor: Colors.red),
      );
      return;
    }
    setState(() {
      _isLoading = true;
    });
    try {
      await _delegationService.createDelegation(
        delegateeId: _selectedDelegateId!,
        topicId: widget.topicId,
        validUntil: _validUntil,
        weight: _selectedWeight,
      );
      widget.onDelegationCreated();
      Navigator.of(context).pop(); // Close dialog on success
    } catch (e) {
      _logger.i('Error creating delegation: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to create delegation: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _validUntil,
      firstDate: DateTime.now(),
      lastDate:
          DateTime.now().add(const Duration(days: 365 * 5)), // 5 years max
    );
    if (picked != null && picked != _validUntil && mounted) {
      setState(() {
        _validUntil = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create New Delegation'),
      content: _isLoading
          ? const LoadingIndicator()
          : SingleChildScrollView(
              child: ListBody(
                children: <Widget>[
                  if (widget.topicId != null) ...[
                    //Text('Topic: ${widget.topicTitle ?? widget.topicId}'),
                    //const SizedBox(height: 16),
                  ],
                  DropdownButtonFormField<String>(
                    decoration:
                        const InputDecoration(labelText: 'Select Delegate'),
                    value: _selectedDelegateId,
                    items: widget.potentialDelegates.map((UserModel user) {
                      return DropdownMenuItem<String>(
                        value: user.id,
                        child: Text(user.name),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      setState(() {
                        _selectedDelegateId = newValue;
                      });
                    },
                    hint: const Text('Choose a delegate'),
                  ),
                  const SizedBox(height: 20),
                  ListTile(
                    title: Text(
                        'Valid Until: ${DateFormat.yMMMd().format(_validUntil)}'),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () => _selectDate(context),
                  ),
                  const SizedBox(height: 20),
                  Text(
                      'Vote Weight: ${(_selectedWeight * 100).toStringAsFixed(0)}%'),
                  Slider(
                    value: _selectedWeight,
                    min: 0.1,
                    max: 1.0,
                    divisions: 9,
                    label: '${(_selectedWeight * 100).toStringAsFixed(0)}%',
                    onChanged: (double value) {
                      setState(() {
                        _selectedWeight = value;
                      });
                    },
                  ),
                ],
              ),
            ),
      actions: <Widget>[
        TextButton(
          child: const Text('Cancel'),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        ElevatedButton(
          onPressed: _selectedDelegateId == null || _isLoading
              ? null
              : _createDelegation,
          child: const Text('Delegate'),
        ),
      ],
    );
  }
}

class RevokeDelegationDialog extends StatefulWidget {
  final String delegationId;
  final DelegationService delegationService;
  final DatabaseService databaseService;
  final AuditService auditService;

  const RevokeDelegationDialog({
    super.key,
    required this.delegationId,
    required this.delegationService,
    required this.databaseService,
    required this.auditService,
  });

  @override
  RevokeDelegationDialogState createState() => RevokeDelegationDialogState();
}

class RevokeDelegationDialogState extends State<RevokeDelegationDialog> {
  bool _isRevoking = false;

  Future<void> _confirmRevoke() async {
    setState(() {
      _isRevoking = true;
    });
    
    try {
      await widget.delegationService.revokeDelegation(widget.delegationId);
      if (mounted) {
        Navigator.of(context).pop(true); // Return true to indicate success
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error revoking delegation: $e')),
        );
        Navigator.of(context).pop(false); // Return false to indicate failure
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Confirm Revoke'),
      content: _isRevoking
          ? const Column(mainAxisSize: MainAxisSize.min, children: [
              LoadingIndicator(),
              SizedBox(height: 10),
              Text('Revoking...')
            ])
          : const Text('Are you sure you want to revoke this delegation?'),
      actions: <Widget>[
        TextButton(
          onPressed: _isRevoking
              ? null
              : () {
                  Navigator.of(context).pop(false);
                },
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          onPressed: _isRevoking ? null : _confirmRevoke,
          child: const Text('Revoke'),
        ),
      ],
    );
  }
}
