import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/data_models.dart';
import '../services/delegation_service.dart';
import '../services/audit_service.dart';
import '../services/database_service.dart';
import '../widgets/loading_indicator.dart';
import '../widgets/create_delegation_dialog.dart';
import 'delegation_visualization_screen.dart';
import 'delegation_audit_screen.dart';

class DelegationManagementScreen extends StatefulWidget {
  final DatabaseService databaseService;
  final AuditService auditService;

  const DelegationManagementScreen({
    super.key,
    required this.databaseService,
    required this.auditService,
  });

  @override
  State<DelegationManagementScreen> createState() =>
      _DelegationManagementScreenState();
}

class _DelegationManagementScreenState extends State<DelegationManagementScreen>
    with SingleTickerProviderStateMixin {
  late final DelegationService _delegationService;
  bool _isLoading = false;
  List<DelegationModel> _myDelegations = [];
  List<DelegationModel> _delegationsToMe = [];
  List<UserModel> _potentialDelegates = [];
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _delegationService = DelegationService.withInstance(
      firestoreInstance: FirebaseFirestore.instance,
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
      // Fetch DelegationInfo lists first
      final List<DelegationInfo> myDelegationsInfo = await _delegationService.getMyDelegations();
      final List<DelegationInfo> delegationsToMeInfo = await _delegationService.getDelegationsToMe();
      
      // Transform to List<DelegationModel>
      final myDelegations = myDelegationsInfo.map((info) => info.delegation).toList();
      final delegationsToMe = delegationsToMeInfo.map((info) => info.delegation).toList();

      final potentialDelegates = await _delegationService.getPotentialDelegates();
      
      if (mounted) {
        setState(() {
          _myDelegations = myDelegations;
          _delegationsToMe = delegationsToMe;
          _potentialDelegates = potentialDelegates;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading delegations: $e');
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackBar('Failed to load delegations');
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

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _revokeDelegation(DelegationModel delegation) async {
    try {
      setState(() {
        _isLoading = true;
      });

      await _delegationService.revokeDelegation(delegation.id);

      _showSuccessSnackBar('Delegation revoked successfully');
      _loadData(); // Reload data
    } catch (e) {
      print('Error revoking delegation: $e');
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackBar('Failed to revoke delegation');
    }
  }

  void _showCreateDelegationDialog() {
    showDialog(
      context: context,
      builder: (context) => CreateDelegationDialog(
        potentialDelegates: _potentialDelegates,
        onDelegationCreated: () {
          _loadData();
          _showSuccessSnackBar('Delegation created successfully');
        },
        databaseService: widget.databaseService,
        auditService: widget.auditService,
      ),
    );
  }

  void _navigateToVisualization() {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (context) => DelegationVisualizationScreen(
              databaseService: widget.databaseService,
              auditService: widget.auditService,
            ),
          ),
        )
        .then((_) => _loadData());
  }
  
  void _navigateToAuditTrail() {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (context) => DelegationAuditScreen(
              databaseService: widget.databaseService,
              auditService: widget.auditService,
            ),
          ),
        )
        .then((_) => _loadData());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Delegation Management'),
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
                _buildMyDelegationsTab(),
                _buildDelegationsToMeTab(),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateDelegationDialog,
        tooltip: 'Create Delegation',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildMyDelegationsTab() {
    if (_myDelegations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.how_to_vote,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              'You haven\'t delegated to anyone yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _showCreateDelegationDialog,
              icon: const Icon(Icons.add),
              label: const Text('Create Delegation'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _myDelegations.length,
      itemBuilder: (context, index) {
        final delegation = _myDelegations[index];
        return DelegationCard(
          delegation: delegation,
          isOutgoing: true,
          onRevoke: () => _revokeDelegation(delegation),
          onViewAudit: () => _navigateToSpecificAuditTrail(delegation.id),
        );
      },
    );
  }

  Widget _buildDelegationsToMeTab() {
    if (_delegationsToMe.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.how_to_vote,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              'No one has delegated to you yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _delegationsToMe.length,
      itemBuilder: (context, index) {
        final delegation = _delegationsToMe[index];
        return DelegationCard(
          delegation: delegation,
          isOutgoing: false,
          onRevoke: null, // Can't revoke delegations to you
          onViewAudit: () => _navigateToSpecificAuditTrail(delegation.id),
        );
      },
    );
  }
  
  void _navigateToSpecificAuditTrail(String delegationId) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (context) => DelegationAuditScreen(
              databaseService: widget.databaseService,
              auditService: widget.auditService,
              delegationId: delegationId,
            ),
          ),
        )
        .then((_) => _loadData());
  }
}

class DelegationCard extends StatelessWidget {
  final DelegationModel delegation;
  final bool isOutgoing;
  final VoidCallback? onRevoke;
  final VoidCallback? onViewAudit;

  const DelegationCard({
    super.key,
    required this.delegation,
    required this.isOutgoing,
    this.onRevoke,
    this.onViewAudit,
  });

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM d, yyyy');
    final validUntil = dateFormat.format(delegation.validUntil);
    final isExpired = delegation.validUntil.isBefore(DateTime.now());

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isExpired
            ? BorderSide(color: Colors.red.shade300, width: 1)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isOutgoing ? Icons.arrow_forward : Icons.arrow_back,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  isOutgoing ? 'Delegated to' : 'Delegated from',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                if (isExpired)
                  Chip(
                    label: const Text('Expired'),
                    backgroundColor: Colors.red.shade100,
                    labelStyle: TextStyle(color: Colors.red.shade800),
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

                final user = snapshot.data;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    child: Text(user?.name.substring(0, 1) ?? '?'),
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
                Text('Valid until: $validUntil'),
              ],
            ),
            if (delegation.topicId != null) ...[
              const SizedBox(height: 8),
              FutureBuilder<TopicModel?>(
                future: _getTopicInfo(delegation.topicId!),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const CircularProgressIndicator();
                  }

                  final topic = snapshot.data;
                  return Row(
                    children: [
                      const Icon(Icons.topic, size: 16),
                      const SizedBox(width: 8),
                      Text('Topic: ${topic?.title ?? 'Unknown'}'),
                    ],
                  );
                },
              ),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (onViewAudit != null)
                  TextButton.icon(
                    onPressed: onViewAudit,
                    icon: const Icon(Icons.history),
                    label: const Text('Audit Trail'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.blue,
                    ),
                  ),
                const SizedBox(width: 8),
                if (onRevoke != null && !isExpired)
                  TextButton.icon(
                    onPressed: onRevoke,
                    icon: const Icon(Icons.cancel),
                    label: const Text('Revoke'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red,
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

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        return UserModel.fromJson({
          'id': doc.id,
          ...data,
        });
      }

      return null;
    } catch (e) {
      print('Error getting user info: $e');
      return null;
    }
  }

  Future<TopicModel?> _getTopicInfo(String topicId) async {
    try {
      final firestore = FirebaseFirestore.instance;
      final doc = await firestore.collection('topics').doc(topicId).get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        return TopicModel.fromJson({
          'id': doc.id,
          ...data,
        });
      }

      return null;
    } catch (e) {
      print('Error getting topic info: $e');
      return null;
    }
  }
}
