import 'package:flutter/material.dart';
import '../models/data_models.dart';
import '../services/delegation_service.dart';
import '../services/audit_service.dart';
import '../services/database_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'loading_indicator.dart';

class AdvancedDelegateSelector extends StatefulWidget {
  final Function(UserModel?) onDelegateSelected;
  final String? currentSelectedDelegateId;
  final String? topicId;
  final DatabaseService databaseService;
  final AuditService auditService;

  const AdvancedDelegateSelector({
    super.key,
    required this.onDelegateSelected,
    this.currentSelectedDelegateId,
    this.topicId,
    required this.databaseService,
    required this.auditService,
  });

  @override
  State<AdvancedDelegateSelector> createState() =>
      _AdvancedDelegateSelectorState();
}

class _AdvancedDelegateSelectorState extends State<AdvancedDelegateSelector> {
  late final DelegationService _delegationService;
  bool _isLoading = true;
  List<UserModel> _potentialDelegates = [];
  List<UserModel> _filteredDelegates = [];
  String _searchQuery = '';
  UserModel? _selectedDelegate;

  @override
  void initState() {
    super.initState();
    _delegationService = DelegationService.withInstance(
      firestoreInstance: FirebaseFirestore.instance,
      databaseService: widget.databaseService,
      auditService: widget.auditService,
    );
    _loadPotentialDelegates();
  }

  Future<void> _loadPotentialDelegates() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final List<UserModel> delegates =
          await _delegationService.getPotentialDelegates();

      setState(() {
        _potentialDelegates = delegates;
        _filteredDelegates = delegates;

        // Set initial selection if provided
        if (widget.currentSelectedDelegateId != null) {
          _selectedDelegate = _potentialDelegates.firstWhere(
            (user) => user.id == widget.currentSelectedDelegateId,
            orElse: () => UserModel(
              id: '',
              name: '',
              email: '',
              role: UserRole.user,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );

          if (_selectedDelegate?.id.isEmpty ?? true) {
            _selectedDelegate = null;
          }
        }

        _isLoading = false;
      });
    } catch (e) {
      print('Error loading potential delegates: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _filterDelegates(String query) {
    setState(() {
      _searchQuery = query;
      if (query.trim().isEmpty) {
        _filteredDelegates = _potentialDelegates;
      } else {
        _filteredDelegates = _potentialDelegates
            .where((user) =>
                user.name.toLowerCase().contains(query.toLowerCase()) ||
                user.email.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  void _selectDelegate(UserModel delegate) async {
    setState(() {
      _isLoading = true;
    });

    // Check for circular delegation
    final userId = _delegationService.currentUserId;
    if (userId != null) {
      final wouldCreateCircular =
          await _delegationService.wouldCreateCircularDelegation(
        delegate.id,
        topicId: widget.topicId,
      );

      if (wouldCreateCircular) {
        setState(() {
          _isLoading = false;
        });

        // Show warning dialog
        _showCircularDelegationWarning(delegate);
        return;
      }
    }

    setState(() {
      _selectedDelegate = delegate;
      _isLoading = false;
    });

    widget.onDelegateSelected(delegate);
  }

  void _showCircularDelegationWarning(UserModel delegate) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Circular Delegation Detected'),
        content: Text(
          'Selecting ${delegate.name} would create a circular delegation chain, '
          'which is not allowed in liquid democracy. Please select another delegate.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search delegates...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            ),
            onChanged: _filterDelegates,
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: LoadingIndicator())
              : _filteredDelegates.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      itemCount: _filteredDelegates.length,
                      itemBuilder: (context, index) {
                        final delegate = _filteredDelegates[index];
                        final isSelected = _selectedDelegate?.id == delegate.id;

                        return _buildDelegateItem(delegate, isSelected);
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    if (_searchQuery.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 64,
              color: Colors.grey,
            ),
            SizedBox(height: 16),
            Text(
              'No potential delegates found',
              style: TextStyle(fontSize: 16),
            ),
          ],
        ),
      );
    } else {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.search_off,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              'No results found for "$_searchQuery"',
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildDelegateItem(UserModel delegate, bool isSelected) {
    final theme = Theme.of(context);

    return FutureBuilder<double>(
      future: _delegationService.calculateRepresentedVoterCount(delegate.id),
      builder: (context, snapshot) {
        final voteWeight = snapshot.data ?? 1.0;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          color: isSelected ? theme.colorScheme.primaryContainer : null,
          child: InkWell(
            onTap: () => _selectDelegate(delegate),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: theme.colorScheme.primary,
                    child: Text(
                      delegate.name.isNotEmpty
                          ? delegate.name[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                        color: theme.colorScheme.onPrimary,
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
                          delegate.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: isSelected
                                ? theme.colorScheme.onPrimaryContainer
                                : null,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          delegate.email,
                          style: TextStyle(
                            fontSize: 14,
                            color: isSelected
                                ? theme.colorScheme.onPrimaryContainer
                                    .withOpacity(0.8)
                                : theme.textTheme.bodySmall?.color,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.how_to_vote,
                          size: 16,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${voteWeight.toStringAsFixed(1)}x',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isSelected)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(
                        Icons.check_circle,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
