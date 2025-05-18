import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/audit_service.dart';
import '../models/data_models.dart';
import '../widgets/proposal_timeline.dart';
import 'voting_screen.dart';
import '../widgets/discussion/comment_section.dart';
import '../services/comment_service.dart';

class ProposalScreen extends StatefulWidget {
  final String? proposalId;

  const ProposalScreen({super.key, this.proposalId});

  @override
  _ProposalScreenState createState() => _ProposalScreenState();
}

class _ProposalScreenState extends State<ProposalScreen>
    with SingleTickerProviderStateMixin {
  final DatabaseService _databaseService = DatabaseService();
  final AuditService _auditService = AuditService();
  final CommentService _commentService = CommentService();
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  String? _selectedTopicId;
  ProposalModel? _proposal;
  List<TopicModel> _topics = [];
  List<CommentModel> _comments = [];
  final List<UserModel> _supporters = [];
  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _isSupporting = false;
  final _commentController = TextEditingController();
  bool _isAddingVoteSession = false;
  
  // Variables for voting method selection
  VotingMethod? _selectedVotingMethod;
  Map<String, bool> _availableVotingMethods = {};
  bool _isLoadingVotingMethods = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    );

    _loadData();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _commentController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _isLoadingVotingMethods = true;
    });

    try {
      // Load topics
      final topics = await _databaseService.getAllTopics();
      
      // Load available voting methods
      final defaultMethod = await _databaseService.getDefaultVotingMethod();
      
      // Set all methods to available by default
      final availableMethods = <String, bool>{};
      for (var method in VotingMethod.values) {
        final methodName = method.toString().split('.').last;
        availableMethods[methodName] = true;
      }

      if (mounted) {
        setState(() {
          _topics = topics;
          _availableVotingMethods = availableMethods;
          _selectedVotingMethod = defaultMethod;
          _isLoadingVotingMethods = false;
        });
      }

      // If editing an existing proposal
      if (widget.proposalId != null) {
        _proposal = await _databaseService.getProposalById(widget.proposalId!);

        if (_proposal != null) {
          _titleController.text = _proposal!.title;
          _contentController.text = _proposal!.content;
          _selectedTopicId = _proposal!.topicId;

          // Load comments for the proposal
          _comments =
              await _databaseService.getCommentsForProposal(_proposal!.id);

          // Load supporter information
          for (var supporterId in _proposal!.supporters) {
            final supporter =
                await Provider.of<AuthService>(context, listen: false)
                    .getUserById(supporterId);
            if (supporter != null) {
              _supporters.add(supporter);
            }
          }
        }
      }

      _animationController.forward();
    } catch (e) {
      print('Error loading data: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _submitProposal() async {
    if (_formKey.currentState!.validate()) {
      if (_selectedTopicId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a topic')),
        );
        return;
      }

      setState(() {
        _isSubmitting = true;
      });

      try {
        if (_proposal == null) {
          // Create new proposal
          await _databaseService.createProposal(
            _titleController.text.trim(),
            _contentController.text.trim(),
            _selectedTopicId!,
            preferredVotingMethod: _selectedVotingMethod,
          );

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Proposal created successfully')),
            );
            Navigator.pop(context);
          }
        } else {
          // Update existing proposal logic would go here
          // Not implemented for MVP as it requires careful consideration of proposal lifecycle
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isSubmitting = false;
          });
        }
      }
    }
  }

  Future<void> _supportProposal() async {
    if (_proposal == null) return;

    setState(() {
      _isSupporting = true;
    });

    try {
      await _databaseService.supportProposal(_proposal!.id);
      await _loadData(); // Reload to update supporters

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You are now supporting this proposal')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSupporting = false;
        });
      }
    }
  }

  Future<void> _addComment() async {
    if (_proposal == null || _commentController.text.trim().isEmpty) return;

    try {
      await _databaseService.addComment(
        _proposal!.id,
        _commentController.text.trim(),
      );

      _commentController.clear();
      await _loadData(); // Reload to update comments
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _showCreateVoteSessionDialog() async {
    if (_proposal == null) return;

    setState(() {
      _isAddingVoteSession = true;
    });

    // Default to First Past The Post initially
    VotingMethod selectedMethod = VotingMethod.firstPastThePost;
    List<String> options = ['Yes', 'No', 'Abstain'];
    final optionsController = TextEditingController(text: 'Yes, No, Abstain');

    DateTime startDate = DateTime.now().add(const Duration(days: 1));
    DateTime endDate = DateTime.now().add(const Duration(days: 8));

    // Fetch available voting methods from settings
    Map<String, bool> availableMethods = {};
    for (var method in VotingMethod.values) {
      availableMethods[method.toString().split('.').last] = true;
    }

    try {
      // Get available methods
      final methodsDoc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('availableVotingMethods')
          .get();
      if (methodsDoc.exists) {
        final data = methodsDoc.data();
        if (data != null && data.containsKey('methods')) {
          final methods = data['methods'] as Map<String, dynamic>?;
          if (methods != null) {
            methods.forEach((key, value) {
              if (value is bool) {
                availableMethods[key] = value;
              }
            });
          }
        }
      }

      // First check if the proposal has a preferred voting method
      if (_proposal!.preferredVotingMethod != null) {
        // Use the proposer's preferred method
        selectedMethod = _proposal!.preferredVotingMethod!;
        print('Using proposer\'s preferred voting method: ${selectedMethod.toString().split('.').last}');
      } else {
        // If no preferred method, get default method for this topic
        final topicSettingsDoc = await FirebaseFirestore.instance
            .collection('settings')
            .doc('topicVoting_${_proposal!.topicId}')
            .get();
        if (topicSettingsDoc.exists) {
          final data = topicSettingsDoc.data();
          if (data != null && data.containsKey('method')) {
            final methodStr = data['method'] as String;
            try {
              selectedMethod = VotingMethod.values.firstWhere(
                (method) => method.toString().split('.').last == methodStr,
                orElse: () => VotingMethod.firstPastThePost,
              );
            } catch (e) {
              print('Error parsing topic voting method: $e');
            }
          }
        } else {
          // If no topic-specific setting, get platform default
          final defaultDoc = await FirebaseFirestore.instance
              .collection('settings')
              .doc('voting')
              .get();
          if (defaultDoc.exists) {
            final data = defaultDoc.data();
            if (data != null && data.containsKey('defaultMethod')) {
              final methodStr = data['defaultMethod'] as String;
              try {
                selectedMethod = VotingMethod.values.firstWhere(
                  (method) => method.toString().split('.').last == methodStr,
                  orElse: () => VotingMethod.firstPastThePost,
                );
              } catch (e) {
                print('Error parsing default voting method: $e');
              }
            }
          }
        }
      }
    } catch (e) {
      print('Error loading voting method settings: $e');
    }

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Create Vote Session'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Voting Method:'),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<VotingMethod>(
                    isExpanded: true,
                    value: selectedMethod,
                    items: VotingMethod.values.where((method) {
                      final methodName = method.toString().split('.').last;
                      return availableMethods[methodName] ?? false;
                    }).map((method) {
                      return DropdownMenuItem<VotingMethod>(
                        value: method,
                        child: Text(_getMethodName(method)),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          selectedMethod = value;
                        });
                      }
                    },
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Options (comma separated):'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: optionsController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'e.g. Yes, No, Abstain',
                    ),
                    onChanged: (value) {
                      options = value.split(',').map((e) => e.trim()).toList();
                    },
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .outline
                              .withOpacity(0.5)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'About ${_getMethodName(selectedMethod)}:',
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        const SizedBox(height: 8),
                        Text(_getMethodDescription(selectedMethod)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Start Date:'),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.calendar_today),
                              label: Text(_formatDate(startDate)),
                              onPressed: () async {
                                final pickedDate = await showDatePicker(
                                  context: context,
                                  initialDate: startDate,
                                  firstDate: DateTime.now(),
                                  lastDate: DateTime.now()
                                      .add(const Duration(days: 365)),
                                );
                                if (pickedDate != null) {
                                  setState(() {
                                    startDate = pickedDate;
                                  });
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('End Date:'),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.calendar_today),
                              label: Text(_formatDate(endDate)),
                              onPressed: () async {
                                final pickedDate = await showDatePicker(
                                  context: context,
                                  initialDate: endDate,
                                  firstDate: startDate,
                                  lastDate: DateTime.now()
                                      .add(const Duration(days: 365)),
                                );
                                if (pickedDate != null) {
                                  setState(() {
                                    endDate = pickedDate;
                                  });
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context, true);
                },
                child: const Text('Create'),
              ),
            ],
          );
        },
      ),
    ).then((shouldCreate) async {
      if (shouldCreate == true) {
        try {
          await _databaseService.createVoteSession(
            _proposal!.id,
            selectedMethod,
            options,
            startDate,
            endDate,
          );

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Vote session created successfully')),
          );

          // Reload the proposal to show updated status
          await _loadData();
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      }

      setState(() {
        _isAddingVoteSession = false;
      });
    });
  }

  Widget _buildProposalForm() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Create New Proposal',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 24),
            DropdownButtonFormField<String>(
              decoration: InputDecoration(
                labelText: 'Topic',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
              ),
              value: _selectedTopicId,
              items: _topics.map((topic) {
                return DropdownMenuItem<String>(
                  value: topic.id,
                  child: Text(topic.title),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedTopicId = value;
                });
              },
              hint: const Text('Select a topic'),
            ),
            const SizedBox(height: 16),
            // Voting Method Dropdown
            _isLoadingVotingMethods
                ? const Center(child: CircularProgressIndicator())
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Preferred Voting Method:'),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<VotingMethod>(
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.surface,
                      ),
                      value: _selectedVotingMethod,
                      items: VotingMethod.values.where((method) {
                        final methodName = method.toString().split('.').last;
                        return _availableVotingMethods[methodName] ?? false;
                      }).map((method) {
                        return DropdownMenuItem<VotingMethod>(
                          value: method,
                          child: Text(_getMethodName(method)),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedVotingMethod = value;
                        });
                      },
                      hint: const Text('Select a voting method'),
                    ),
                    const SizedBox(height: 8),
                    if (_selectedVotingMethod != null)
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceVariant,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(_getMethodDescription(_selectedVotingMethod!)),
                      ),
                  ]),
            const SizedBox(height: 16),
            TextFormField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a title';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _contentController,
              decoration: InputDecoration(
                labelText: 'Content',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
                alignLabelWithHint: true,
              ),
              maxLines: 10,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter content';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitProposal,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Submit Proposal'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProposalDetails(UserModel? currentUser) {
    if (_proposal == null) {
      return const Center(child: Text('Proposal details are not available.'));
    }
    bool isSupporter = _supporters.any((user) => user.id == currentUser?.id);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Proposal Timeline
          ProposalTimeline(proposal: _proposal!),
          const SizedBox(height: 16),

          // Status banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: _getStatusColor(_proposal!.status),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      _getStatusIcon(_proposal!.status),
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Status: ${_proposal!.status.toString().split('.').last}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                if (_proposal!.status == ProposalStatus.voting) ...[
                  FutureBuilder<VoteSessionModel?>(
                    future: _databaseService
                        .getVoteSessionByProposal(_proposal!.id),
                    builder: (context, snapshot) {
                      if (snapshot.hasData && snapshot.data != null) {
                        return ElevatedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => VotingScreen(
                                  sessionId: snapshot.data!.id,
                                  databaseService: _databaseService,
                                  auditService: _auditService,
                                ),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: _getStatusColor(_proposal!.status),
                          ),
                          child: const Text('Vote Now'),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Title and content
          Text(
            _proposal!.title,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          
          // Display preferred voting method if available
          if (_proposal!.preferredVotingMethod != null) ...[            
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.how_to_vote, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Preferred voting method: ${_getMethodName(_proposal!.preferredVotingMethod!)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.surface,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                _proposal!.content,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Actions section
          if (_proposal!.status == ProposalStatus.discussion ||
              _proposal!.status == ProposalStatus.support) ...[
            Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surface.withOpacity(0.7),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Supporters: ${_proposal!.supporters.length}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _supporters.map((supporter) {
                        return Chip(
                          label: Text(supporter.name),
                          avatar: CircleAvatar(
                            backgroundColor:
                                Theme.of(context).colorScheme.primary,
                            child: Text(
                              supporter.name.substring(0, 1).toUpperCase(),
                              style: TextStyle(
                                  color:
                                      Theme.of(context).colorScheme.onPrimary),
                            ),
                          ),
                          backgroundColor:
                              Theme.of(context).colorScheme.surface,
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    if (currentUser != null && !isSupporter) ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isSupporting ? null : _supportProposal,
                          icon: const Icon(Icons.thumb_up),
                          label: _isSupporting
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Support This Proposal'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                Theme.of(context).colorScheme.primary,
                            foregroundColor:
                                Theme.of(context).colorScheme.onPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],

          // Admin/Creator Actions
          if ((currentUser?.id == _proposal!.authorId ||
                  currentUser?.role == UserRole.admin) &&
              _proposal!.status != ProposalStatus.closed) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Actions',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  if (_proposal!.status == ProposalStatus.support &&
                      _proposal!.supporters.length >= 10) ...[
                    ElevatedButton.icon(
                      onPressed: () async {
                        await _databaseService.updateProposalStatus(
                          _proposal!.id,
                          ProposalStatus.frozen,
                        );
                        await _loadData();
                      },
                      icon: const Icon(Icons.lock),
                      label: const Text('Freeze Proposal'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.tertiary,
                        foregroundColor:
                            Theme.of(context).colorScheme.onTertiary,
                      ),
                    ),
                  ],
                  if ((currentUser?.id == _proposal!.authorId ||
                          currentUser?.role == UserRole.admin) &&
                      _proposal!.status == ProposalStatus.frozen) ...[
                    ElevatedButton.icon(
                      onPressed: _isAddingVoteSession
                          ? null
                          : _showCreateVoteSessionDialog,
                      icon: const Icon(Icons.how_to_vote),
                      label: _isAddingVoteSession
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Start Vote'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor:
                            Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],

          // Comments section
          const SizedBox(height: 16),
          Text(
            'Comments',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          if (currentUser != null) ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    decoration: InputDecoration(
                      hintText: 'Add a comment...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _addComment,
                  icon: const Icon(Icons.send),
                  color: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          ..._comments.map((comment) {
            return FutureBuilder<UserModel?>(
              future: Provider.of<AuthService>(context, listen: false)
                  .getUserById(comment.authorId),
              builder: (context, snapshot) {
                final commentUser = snapshot.data;
                return Card(
                  elevation: 0,
                  color: Theme.of(context).colorScheme.surface,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              backgroundColor:
                                  Theme.of(context).colorScheme.primary,
                              radius: 16,
                              child: Text(
                                commentUser?.name
                                        .substring(0, 1)
                                        .toUpperCase() ??
                                    'U',
                                style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onPrimary),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  commentUser?.name ?? 'Unknown User',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  _formatDate(comment.createdAt),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(comment.content),
                      ],
                    ),
                  ),
                );
              },
            );
          }),
          if (_comments.isEmpty) ...[
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'No comments yet. Be the first to comment!',
                  style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.6)),
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          Text('Discussion', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          if (currentUser != null && _proposal != null)
            CommentSection(
              proposal: _proposal!,
              commentService: _commentService,
              currentUserId: currentUser.id,
              currentUserRole: (currentUser.role as String?) ?? 'user',
            )
          else
            const Text('Login to participate in the discussion.'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
            widget.proposalId == null ? 'New Proposal' : 'Proposal Details'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: widget.proposalId == null
                  ? _buildProposalForm()
                  : _buildProposalDetails(
                      Provider.of<AuthService>(context, listen: false)
                          .currentUser),
            ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  Color _getStatusColor(ProposalStatus status) {
    switch (status) {
      case ProposalStatus.draft:
        return Colors.grey;
      case ProposalStatus.discussion:
        return Colors.blue;
      case ProposalStatus.support:
        return Colors.teal;
      case ProposalStatus.frozen:
        return Colors.purple;
      case ProposalStatus.voting:
        return Colors.orange;
      case ProposalStatus.closed:
        return Colors.red;
    }
  }

  IconData _getStatusIcon(ProposalStatus status) {
    switch (status) {
      case ProposalStatus.draft:
        return Icons.edit;
      case ProposalStatus.discussion:
        return Icons.forum;
      case ProposalStatus.support:
        return Icons.thumb_up;
      case ProposalStatus.frozen:
        return Icons.lock;
      case ProposalStatus.voting:
        return Icons.how_to_vote;
      case ProposalStatus.closed:
        return Icons.check_circle;
      default:
        return Icons.info;
    }
  }

  String _getMethodName(VotingMethod method) {
    switch (method) {
      case VotingMethod.firstPastThePost:
        return 'First Past The Post';
      case VotingMethod.approvalVoting:
        return 'Approval Voting';
      case VotingMethod.majorityRunoff:
        return 'Majority Runoff';
      case VotingMethod.schulze:
        return 'Schulze Method';
      case VotingMethod.instantRunoff:
        return 'Instant Runoff Voting';
      case VotingMethod.starVoting:
        return 'STAR Voting';
      case VotingMethod.rangeVoting:
        return 'Range Voting';
      case VotingMethod.majorityJudgment:
        return 'Majority Judgment';
      case VotingMethod.quadraticVoting:
        return 'Quadratic Voting';
      case VotingMethod.condorcet:
        return 'Condorcet Method';
      case VotingMethod.bordaCount:
        return 'Borda Count';
      case VotingMethod.cumulativeVoting:
        return 'Cumulative Voting';
      case VotingMethod.kemenyYoung:
        return 'Kemeny-Young Method';
      case VotingMethod.dualChoice:
        return 'Dual-Choice Voting';
      case VotingMethod.weightVoting:
        return 'Weight Voting';
      default:
        return 'Unknown Method';
    }
  }

  String _getMethodDescription(VotingMethod method) {
    switch (method) {
      case VotingMethod.firstPastThePost:
        return 'The simplest voting method where voters select one option, and the option with the most votes wins. Best for simple binary decisions.';
      case VotingMethod.approvalVoting:
        return 'Voters can select multiple options they approve of. The option with the most approvals wins. Good for selecting from multiple acceptable options.';
      case VotingMethod.majorityRunoff:
        return 'If no option receives a majority, a second round is held between the top two options. Ensures the winner has majority support.';
      case VotingMethod.schulze:
        return 'A complex ranking method that compares all possible pairs of options to find the strongest path. Good for decisions with many options.';
      case VotingMethod.instantRunoff:
        return 'Voters rank options in order of preference. The option with the fewest first-choice votes is eliminated, and those votes transfer to the voters\'s next choices.';
      case VotingMethod.starVoting:
        return 'Score Then Automatic Runoff: Voters score each option from 0-5, then the two highest-scoring options advance to an automatic runoff.';
      case VotingMethod.rangeVoting:
        return 'Voters rate each option on a scale (e.g., 0-10). The option with the highest average rating wins.';
      case VotingMethod.majorityJudgment:
        return 'Voters assign qualitative ratings to each option (e.g., "Excellent" to "Reject"). The option with the highest median rating wins.';
      case VotingMethod.quadraticVoting:
        return 'Voters have a budget of credits and can allocate them across options. The cost of votes increases quadratically, encouraging sincere voting.';
      case VotingMethod.condorcet:
        return 'A ranking method where the winner is the option that would win a head-to-head comparison against every other option.';
      case VotingMethod.bordaCount:
        return 'Voters rank options, and points are assigned based on rank (n points for first place, n-1 for second, etc.). The option with the most points wins.';
      case VotingMethod.cumulativeVoting:
        return 'Voters have multiple votes they can distribute among options as they choose. Good for expressing strength of preference.';
      case VotingMethod.kemenyYoung:
        return 'A ranking method that finds the ordering of options that minimizes the number of disagreements with voters\'s rankings.';
      case VotingMethod.dualChoice:
        return 'A two-round system where voters first select from all options, then choose between the top two in a second round.';
      case VotingMethod.weightVoting:
        return 'Votes are weighted based on predetermined factors. Can be used when some voters should have more influence than others.';
      default:
        return 'No description available.';
    }
  }
}
