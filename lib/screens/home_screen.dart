import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/audit_service.dart';
import '../services/comment_service.dart';
import '../models/data_models.dart';
import '../widgets/discussion/comment_section.dart';
import 'auth_screen.dart';
import 'proposal_screen.dart';
import 'voting_screen.dart';
import 'delegation_management_screen.dart';

class HomeScreen extends StatefulWidget {
  final DatabaseService databaseService;
  final AuditService auditService;

  const HomeScreen({
    super.key,
    required this.databaseService,
    required this.auditService,
  });

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  int _selectedIndex = 0;
  late AuditService _auditService;
  late CommentService _commentService;

  // Local state for admin voting method selection
  VotingMethod? _selectedDefaultMethod;
  
  // State for available voting methods management
  Map<String, bool> _availableVotingMethods = {};
  bool _isLoadingAvailableMethods = false;
  bool _isSavingAvailableMethods = false;

  // Tab controllers for each section
  late TabController _dashboardTabController;
  late TabController _proposalsTabController;
  late TabController _profileTabController;

  @override
  void initState() {
    super.initState();
    _auditService = widget.auditService;
    _commentService = CommentService(); // Initialize comment service

    // Initialize tab controllers for each section
    _dashboardTabController = TabController(length: 3, vsync: this);
    _proposalsTabController = TabController(length: 4, vsync: this); // Added Discussions tab
    _profileTabController = TabController(length: 2, vsync: this);
    
    // Load available voting methods
    _loadAvailableVotingMethods();
  }
  
  // Load available voting methods from the database
  Future<void> _loadAvailableVotingMethods() async {
    setState(() {
      _isLoadingAvailableMethods = true;
    });
    
    try {
      final methods = await widget.databaseService.getAvailableVotingMethods();
      
      if (mounted) {
        setState(() {
          _availableVotingMethods = methods;
          _isLoadingAvailableMethods = false;
        });
      }
    } catch (e) {
      print('Error loading available voting methods: $e');
      if (mounted) {
        setState(() {
          _isLoadingAvailableMethods = false;
        });
      }
    }
  }
  
  // Save available voting methods to the database
  Future<void> _saveAvailableVotingMethods() async {
    setState(() {
      _isSavingAvailableMethods = true;
    });
    
    try {
      final success = await widget.databaseService.updateAvailableVotingMethods(_availableVotingMethods);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success 
              ? 'Available voting methods updated successfully' 
              : 'Failed to update available voting methods'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      print('Error saving available voting methods: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSavingAvailableMethods = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _dashboardTabController.dispose();
    _proposalsTabController.dispose();
    _profileTabController.dispose();
    super.dispose();
  }

  Widget _buildRoleBasedDashboard(UserModel user) {
    // Ensure the user has a valid role
    final role = user.role;
    print('Building dashboard for user with role: $role');

    // Based on the selected bottom navigation index
    switch (_selectedIndex) {
      case 0: // Dashboard
        return _buildDashboard(user);
      case 1: // Proposals
        return _buildProposalsSection(user);
      case 2: // Profile
        return _buildProfileSection(user);
      default:
        return _buildDashboard(user);
    }
  }

  Widget _buildDashboard(UserModel user) {
    // Build role-specific dashboard content
    switch (user.role) {
      case UserRole.admin:
        return _buildAdminDashboard(user);
      case UserRole.moderator:
        return _buildModeratorDashboard(user);
      case UserRole.proposer:
        return _buildProposerDashboard(user);
      case UserRole.user:
        return _buildUserDashboard(user);
    }
  }

  Widget _buildAdminDashboard(UserModel user) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Admin Dashboard',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        TabBar(
          controller: _dashboardTabController,
          labelColor: Theme.of(context).colorScheme.primary,
          unselectedLabelColor:
              Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
          indicatorColor: Theme.of(context).colorScheme.primary,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard), text: 'Overview'),
            Tab(icon: Icon(Icons.people), text: 'Users'),
            Tab(icon: Icon(Icons.settings), text: 'Settings'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _dashboardTabController,
            children: [
              _buildAdminOverviewTab(user),
              _buildUserManagementTab(),
              _buildAdminSettingsTab(),
            ],
          ),
        ),
      ],
    );
  }
  
  Widget _buildAdminOverviewTab(UserModel user) {
    return FutureBuilder<List<dynamic>>(
      future: Future.wait([
        widget.databaseService.getAllTopics(),
        widget.databaseService.getProposalsByStatus(ProposalStatus.support),
        widget.databaseService.getActiveVoteSessions(),
        Provider.of<AuthService>(context, listen: false).getAllUsers(),
      ]),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final topics = snapshot.data![0] as List<TopicModel>;
        final pendingProposals = snapshot.data![1] as List<ProposalModel>;
        final activeVotes = snapshot.data![2] as List<VoteSessionModel>;
        final users = snapshot.data![3] as List<UserModel>;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'System Overview',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildOverviewCard(
                      'Users',
                      users.length.toString(),
                      Icons.people,
                      Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildOverviewCard(
                      'Topics',
                      topics.length.toString(),
                      Icons.topic,
                      Colors.green,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildOverviewCard(
                      'Pending Proposals',
                      pendingProposals.length.toString(),
                      Icons.pending_actions,
                      Colors.orange,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildOverviewCard(
                      'Active Votes',
                      activeVotes.length.toString(),
                      Icons.how_to_vote,
                      Colors.purple,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'Quick Actions',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _buildActionButton(
                    'Add Topic',
                    Icons.add_circle,
                    Colors.green,
                    () => _showAddTopicDialog(),
                  ),
                  _buildActionButton(
                    'Manage Users',
                    Icons.manage_accounts,
                    Colors.blue,
                    () {
                      _dashboardTabController.animateTo(1); // Switch to Users tab
                    },
                  ),
                  _buildActionButton(
                    'Review Proposals',
                    Icons.fact_check,
                    Colors.orange,
                    () {
                      setState(() {
                        _selectedIndex = 1; // Switch to Proposals section
                      });
                    },
                  ),
                  _buildActionButton(
                    'Voting Settings',
                    Icons.settings,
                    Colors.purple,
                    () {
                      _dashboardTabController.animateTo(2); // Switch to Settings tab
                    },
                  ),
                ],
              ),
              if (pendingProposals.isNotEmpty) ...[  
                const SizedBox(height: 24),
                Text(
                  'Proposals Requiring Approval',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 16),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: pendingProposals.length > 3 ? 3 : pendingProposals.length,
                  itemBuilder: (context, index) {
                    final proposal = pendingProposals[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(proposal.title),
                        subtitle: Text('Supporters: ${proposal.supporters.length}'),
                        trailing: ElevatedButton(
                          onPressed: () async {
                            await widget.databaseService.updateProposalStatus(
                              proposal.id,
                              ProposalStatus.frozen,
                            );
                            setState(() {});
                          },
                          child: const Text('Approve'),
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ProposalScreen(proposalId: proposal.id),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
                if (pendingProposals.length > 3)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _selectedIndex = 1; // Switch to Proposals section
                      });
                    },
                    child: const Text('View All Pending Proposals'),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
  
  Widget _buildOverviewCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildActionButton(String label, IconData icon, Color color, VoidCallback onPressed) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, color: Theme.of(context).colorScheme.onPrimary),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }
  
  Widget _buildAdminSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'System Settings',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 24),
          _buildVotingSystemsManagementTab(),
        ],
      ),
    );
  }

  Widget _buildUserManagementTab() {
    return FutureBuilder<List<UserModel>>(
      future: Provider.of<AuthService>(context, listen: false).getAllUsers(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final users = snapshot.data!;

        return ListView.builder(
          itemCount: users.length,
          itemBuilder: (context, index) {
            final user = users[index];
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  child: Text(
                    user.name.substring(0, 1).toUpperCase(),
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimary),
                  ),
                ),
                title: Text(user.name,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text(user.email),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getRoleColor(user.role),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        user.role.toString().split('.').last,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () => _showChangeRoleDialog(user),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showChangeRoleDialog(UserModel user) {
    UserRole selectedRole = user.role;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Change User Role'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('User: ${user.name}'),
                const SizedBox(height: 16),
                const Text('Select new role:'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: UserRole.values.map((role) {
                    return ChoiceChip(
                      label: Text(
                        role.toString().split('.').last,
                        style: TextStyle(
                          color: selectedRole == role
                              ? Theme.of(context).colorScheme.onPrimary
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      selected: selectedRole == role,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            selectedRole = role;
                          });
                        }
                      },
                      selectedColor: Theme.of(context).colorScheme.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    );
                  }).toList(),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Cancel',
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.secondary),
                ),
              ),
              ElevatedButton(
                onPressed: () async {
                  try {
                    await Provider.of<AuthService>(context, listen: false)
                        .changeUserRole(user.id, selectedRole);
                    if (mounted) {
                      Navigator.pop(context);
                      setState(() {});
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: $e')),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                ),
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }


  void _showAddTopicDialog() {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Topic'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a title';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: descriptionController,
                decoration: const InputDecoration(labelText: 'Description'),
                maxLines: 3,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a description';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: Theme.of(context).colorScheme.secondary),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                try {
                  await widget.databaseService.createTopic(
                    titleController.text.trim(),
                    descriptionController.text.trim(),
                  );
                  if (mounted) {
                    Navigator.pop(context);
                    setState(() {});
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                  }
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
            ),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }


  Widget _buildModeratorDashboard(UserModel user) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Moderator Dashboard',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        Expanded(
          child: DefaultTabController(
            length: 2,
            child: Column(
              children: [
                TabBar(
                  tabs: const [
                    Tab(text: 'Proposals'),
                    Tab(text: 'Comments'),
                  ],
                  labelColor: Theme.of(context).colorScheme.primary,
                  unselectedLabelColor:
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                  indicatorColor: Theme.of(context).colorScheme.primary,
                ),
                const Expanded(
                  child: TabBarView(
                    children: [
                      Center(child: Text('Proposals to moderate')),
                      Center(child: Text('Comments to moderate')),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProposerDashboard(UserModel user) {
    if (user.id.isEmpty) {
      print('Warning: User ID is empty in proposer dashboard');
      return const Center(child: Text('Error: Invalid user ID'));
    }

    return FutureBuilder<List<ProposalModel>>(
      future: widget.databaseService.getProposalsByAuthor(user.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final proposals = snapshot.data ?? [];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'My Proposals',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ProposalScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('New Proposal'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: proposals.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.description_outlined,
                            size: 64,
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withOpacity(0.5),
                          ),
                          const SizedBox(height: 16),
                          const Text('No proposals yet'),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const ProposalScreen(),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  Theme.of(context).colorScheme.primary,
                              foregroundColor:
                                  Theme.of(context).colorScheme.onPrimary,
                            ),
                            child: const Text('Create Your First Proposal'),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: proposals.length,
                      itemBuilder: (context, index) {
                        final proposal = proposals[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          elevation: 2,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      ProposalScreen(proposalId: proposal.id),
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          proposal.title,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 18,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          color:
                                              _getStatusColor(proposal.status),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          proposal.status
                                              .toString()
                                              .split('.')
                                              .last,
                                          style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onPrimary,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    proposal.content.length > 100
                                        ? '${proposal.content.substring(0, 100)}...'
                                        : proposal.content,
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withOpacity(0.7),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.people,
                                        size: 16,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${proposal.supporters.length} supporters',
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        'Created: ${_formatDate(proposal.createdAt)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withOpacity(0.5),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildUserDashboard(UserModel user) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Welcome, ${user.name}',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Active Votes',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<VoteSessionModel>>(
            future: widget.databaseService.getActiveVoteSessions(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }

              final voteSessions = snapshot.data ?? [];

              if (voteSessions.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.how_to_vote_outlined,
                        size: 64,
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withOpacity(0.5),
                      ),
                      const SizedBox(height: 16),
                      const Text('No active votes at the moment'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const ProposalScreen(),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          foregroundColor:
                              Theme.of(context).colorScheme.onPrimary,
                        ),
                        child: const Text('Browse Proposals'),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                itemCount: voteSessions.length,
                itemBuilder: (context, index) {
                  final session = voteSessions[index];
                  return FutureBuilder<ProposalModel?>(
                    future: widget.databaseService
                        .getProposalById(session.proposalId),
                    builder: (context, proposalSnapshot) {
                      if (proposalSnapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const Card(
                          margin:
                              EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        );
                      }

                      final proposal = proposalSnapshot.data;
                      if (proposal == null) {
                        return const SizedBox.shrink();
                      }

                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        elevation: 2,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => VotingScreen(
                                  sessionId: session.id,
                                  databaseService: widget.databaseService,
                                  auditService: _auditService,
                                ),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.how_to_vote,
                                            size: 14,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onPrimary,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'VOTE NOW',
                                            style: TextStyle(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onPrimary,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .tertiary,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        _getVotingMethodName(session.method),
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onTertiary,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  proposal.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  proposal.content.length > 100
                                      ? '${proposal.content.substring(0, 100)}...'
                                      : proposal.content,
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withOpacity(0.7),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    FutureBuilder<bool>(
                                      future: widget.databaseService
                                          .hasUserVoted(session.id),
                                      builder: (context, votedSnapshot) {
                                        final hasVoted =
                                            votedSnapshot.data ?? false;
                                        return Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: hasVoted
                                                ? Theme.of(context)
                                                    .colorScheme
                                                    .secondary
                                                : Colors.grey.withOpacity(0.3),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                hasVoted
                                                    ? Icons.check
                                                    : Icons.pending_outlined,
                                                size: 14,
                                                color: hasVoted
                                                    ? Theme.of(context)
                                                        .colorScheme
                                                        .onSecondary
                                                    : Theme.of(context)
                                                        .colorScheme
                                                        .onSurface,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                hasVoted
                                                    ? 'Voted'
                                                    : 'Not voted',
                                                style: TextStyle(
                                                  color: hasVoted
                                                      ? Theme.of(context)
                                                          .colorScheme
                                                          .onSecondary
                                                      : Theme.of(context)
                                                          .colorScheme
                                                          .onSurface,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                    Text(
                                      'Ends: ${_formatDate(session.endDate)}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withOpacity(0.6),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _onBottomNavTapped(int index) {
    setState(() {
      _selectedIndex = index;
      if (index == 0) {
        // Reset dashboard tab controller to first tab
        _dashboardTabController.animateTo(0);
      } else if (index == 1) {
        // Reset proposals tab controller to first tab
        _proposalsTabController.animateTo(0);
      } else if (index == 2) {
        // Reset profile tab controller to first tab
        _profileTabController.animateTo(0);
      }
    });
  }
  
  // Proposals section implementation
  Widget _buildProposalsSection(UserModel user) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Proposals',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        TabBar(
          controller: _proposalsTabController,
          labelColor: Theme.of(context).colorScheme.primary,
          unselectedLabelColor:
              Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
          indicatorColor: Theme.of(context).colorScheme.primary,
          tabs: const [
            Tab(text: 'Active'),
            Tab(text: 'My Proposals'),
            Tab(text: 'Past'),
            Tab(text: 'Discussions'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _proposalsTabController,
            children: [
              _buildActiveProposalsTab(user),
              _buildMyProposalsTab(user),
              _buildPastProposalsTab(user),
              _buildDiscussionsTab(user),
            ],
          ),
        ),
      ],
    );
  }
  
  // My Proposals tab - shows proposals created by the current user
  Widget _buildMyProposalsTab(UserModel user) {
    // Only relevant for users with proposer role
    if (user.role != UserRole.proposer && user.role != UserRole.admin) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.info_outline,
              size: 64,
              color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            const Text('You need proposer privileges to create proposals'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _selectedIndex = 0; // Go back to dashboard
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
              child: const Text('Back to Dashboard'),
            ),
          ],
        ),
      );
    }
    
    return FutureBuilder<List<ProposalModel>>(
      future: widget.databaseService.getProposalsByAuthor(user.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final proposals = snapshot.data ?? [];

        if (proposals.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.description_outlined,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                ),
                const SizedBox(height: 16),
                const Text('You haven\'t created any proposals yet'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ProposalScreen(),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                  child: const Text('Create Your First Proposal'),
                ),
              ],
            ),
          );
        }

        // Group proposals by status
        final Map<ProposalStatus, List<ProposalModel>> groupedProposals = {};
        for (var proposal in proposals) {
          if (!groupedProposals.containsKey(proposal.status)) {
            groupedProposals[proposal.status] = [];
          }
          groupedProposals[proposal.status]!.add(proposal);
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'My Proposals',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ProposalScreen(),
                        ),
                      ).then((_) => setState(() {})); // Refresh after returning
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('New Proposal'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Display proposals grouped by status
              for (var status in ProposalStatus.values)
                if (groupedProposals.containsKey(status) && groupedProposals[status]!.isNotEmpty) ...[  
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _getStatusColor(status),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      status.toString().split('.').last,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: groupedProposals[status]!.length,
                    itemBuilder: (context, index) {
                      final proposal = groupedProposals[status]![index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          title: Text(
                            proposal.title,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(
                                proposal.content.length > 50
                                    ? '${proposal.content.substring(0, 50)}...'
                                    : proposal.content,
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(
                                    Icons.people,
                                    size: 16,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${proposal.supporters.length} supporters',
                                    style: TextStyle(
                                      color: Theme.of(context).colorScheme.primary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.arrow_forward),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ProposalScreen(proposalId: proposal.id),
                                ),
                              ).then((_) => setState(() {})); // Refresh after returning
                            },
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                ],
            ],
          ),
        );
      },
    );
  }

  // Past Proposals tab - shows closed proposals
  Widget _buildPastProposalsTab(UserModel user) {
    return FutureBuilder<List<ProposalModel>>(
      future: widget.databaseService.getProposalsByStatus(ProposalStatus.closed),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final proposals = snapshot.data ?? [];

        if (proposals.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.history,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                ),
                const SizedBox(height: 16),
                const Text('No past proposals available'),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16.0),
          itemCount: proposals.length,
          itemBuilder: (context, index) {
            final proposal = proposals[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ProposalScreen(proposalId: proposal.id),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              proposal.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: _getStatusColor(proposal.status),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'Closed',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        proposal.content.length > 100
                            ? '${proposal.content.substring(0, 100)}...'
                            : proposal.content,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.people,
                                size: 16,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${proposal.supporters.length} supporters',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            'Closed: ${_formatDate(proposal.updatedAt)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: () {
                          // Navigate to results screen for this proposal
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ProposalScreen(proposalId: proposal.id),
                            ),
                          );
                        },
                        icon: const Icon(Icons.bar_chart),
                        label: const Text('View Results'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.secondary,
                          foregroundColor: Theme.of(context).colorScheme.onSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Profile section implementation
  Widget _buildProfileSection(UserModel user) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Profile',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        TabBar(
          controller: _profileTabController,
          labelColor: Theme.of(context).colorScheme.primary,
          unselectedLabelColor:
              Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
          indicatorColor: Theme.of(context).colorScheme.primary,
          tabs: const [
            Tab(text: 'User Info'),
            Tab(text: 'Activity'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _profileTabController,
            children: [
              _buildUserInfoTab(user),
              _buildUserActivityTab(user),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUserInfoTab(UserModel user) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // User profile card
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    child: Text(
                      user.name.substring(0, 1).toUpperCase(),
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    user.name,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    user.email,
                    style: TextStyle(
                      fontSize: 16,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: _getRoleColor(user.role),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      user.role.toString().split('.').last,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Account Information',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),
          _buildInfoCard('Account Created', _formatDate(user.createdAt)),
          _buildInfoCard('Last Updated', _formatDate(user.updatedAt)),
          
          // Role-specific information
          const SizedBox(height: 24),
          Text(
            'Role Capabilities',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),
          _buildRoleCapabilitiesCard(user.role),
          
          // Delegations section if applicable
          if (user.delegations.isNotEmpty) ...[  
            const SizedBox(height: 24),
            Text(
              'Active Delegations',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('You have ${user.delegations.length} active delegations'),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => DelegationManagementScreen(
                              databaseService: widget.databaseService,
                              auditService: _auditService,
                            ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      ),
                      child: const Text('Manage Delegations'),
                    ),
                  ],
                ),
              ),
            ),
          ],
          
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () async {
              await Provider.of<AuthService>(context, listen: false).signOut();
              if (mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const AuthScreen()),
                );
              }
            },
            icon: const Icon(Icons.logout),
            label: const Text('Sign Out'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 50),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String label, String value) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            Text(value),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleCapabilitiesCard(UserRole role) {
    List<String> capabilities = [];
    
    switch (role) {
      case UserRole.admin:
        capabilities = [
          'Manage users and roles',
          'Create and manage topics',
          'Approve proposals',
          'Configure voting methods',
          'Access all platform features',
        ];
        break;
      case UserRole.moderator:
        capabilities = [
          'Review and moderate proposals',
          'Moderate comments',
          'Participate in votes',
          'Delegate votes',
        ];
        break;
      case UserRole.proposer:
        capabilities = [
          'Create new proposals',
          'Edit own proposals',
          'Participate in votes',
          'Delegate votes',
        ];
        break;
      case UserRole.user:
        capabilities = [
          'Participate in votes',
          'Support proposals',
          'Delegate votes',
          'Comment on proposals',
        ];
        break;
    }
    
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'As a ${role.toString().split('.').last}, you can:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...capabilities.map((capability) => Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check_circle, size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(capability)),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildUserActivityTab(UserModel user) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.timeline,
            size: 64,
            color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          const Text('Activity tracking coming soon!'),
          const SizedBox(height: 8),
          Text(
            'This feature will show your voting history,\ndelegation activity, and proposal interactions.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  // Discussions tab - shows proposals with active discussions
  Widget _buildDiscussionsTab(UserModel user) {
    return FutureBuilder<List<ProposalModel>>(
      future: widget.databaseService.getProposalsByStatus(ProposalStatus.discussion),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final discussionProposals = snapshot.data ?? [];

        if (discussionProposals.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.forum_outlined,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                ),
                const SizedBox(height: 16),
                const Text('No active discussions at the moment'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ProposalScreen(),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                  child: const Text('Create New Proposal'),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16.0),
          itemCount: discussionProposals.length,
          itemBuilder: (context, index) {
            final proposal = discussionProposals[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 16.0),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  // Proposal header
                  ListTile(
                    contentPadding: const EdgeInsets.all(16.0),
                    title: Text(
                      proposal.title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        proposal.content.length > 100
                            ? '${proposal.content.substring(0, 100)}...'
                            : proposal.content,
                      ),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _getStatusColor(proposal.status),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Discussion',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  // Comment section
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: ExpansionTile(
                      title: const Text('View Discussion'),
                      children: [
                        CommentSection(
                          proposal: proposal,
                          commentService: _commentService,
                          currentUserId: user.id,
                          currentUserRole: user.role.toString().split('.').last,
                        ),
                      ],
                    ),
                  ),
                  // Action buttons
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ProposalScreen(proposalId: proposal.id),
                              ),
                            );
                          },
                          icon: const Icon(Icons.visibility),
                          label: const Text('View Full Proposal'),
                        ),
                        ElevatedButton.icon(
                          onPressed: () async {
                            // Support the proposal
                            try {
                              await widget.databaseService.supportProposal(proposal.id);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Proposal supported!')),
                              );
                              setState(() {}); // Refresh the UI
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error: $e')),
                              );
                            }
                          },
                          icon: const Icon(Icons.thumb_up),
                          label: const Text('Support'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            foregroundColor: Theme.of(context).colorScheme.onPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildActiveProposalsTab(UserModel user) {
    return FutureBuilder<List<VoteSessionModel>>(
      future: widget.databaseService.getActiveVoteSessions(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final voteSessions = snapshot.data ?? [];

        if (voteSessions.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.how_to_vote_outlined,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                ),
                const SizedBox(height: 16),
                const Text('No active votes at the moment'),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16.0),
          itemCount: voteSessions.length,
          itemBuilder: (context, index) {
            final session = voteSessions[index];
            return FutureBuilder<ProposalModel?>(
              future: widget.databaseService.getProposalById(session.proposalId),
              builder: (context, proposalSnapshot) {
                if (proposalSnapshot.connectionState == ConnectionState.waiting) {
                  return const Card(
                    margin: EdgeInsets.only(bottom: 16.0),
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  );
                }

                final proposal = proposalSnapshot.data;
                if (proposal == null) {
                  return const SizedBox.shrink();
                }

                return Card(
                  margin: const EdgeInsets.only(bottom: 16.0),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 2,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => VotingScreen(
                            sessionId: session.id,
                            databaseService: widget.databaseService,
                            auditService: _auditService,
                          ),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.how_to_vote,
                                      size: 14,
                                      color: Theme.of(context).colorScheme.onPrimary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'VOTE NOW',
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.onPrimary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.tertiary,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  _getVotingMethodName(session.method),
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onTertiary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            proposal.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            proposal.content.length > 100
                                ? '${proposal.content.substring(0, 100)}...'
                                : proposal.content,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              FutureBuilder<bool>(
                                future: widget.databaseService.hasUserVoted(session.id),
                                builder: (context, votedSnapshot) {
                                  final hasVoted = votedSnapshot.data ?? false;
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: hasVoted
                                          ? Theme.of(context).colorScheme.secondary
                                          : Colors.grey.withOpacity(0.3),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          hasVoted ? Icons.check : Icons.pending_outlined,
                                          size: 14,
                                          color: hasVoted
                                              ? Theme.of(context).colorScheme.onSecondary
                                              : Theme.of(context).colorScheme.onSurface,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          hasVoted ? 'Voted' : 'Not voted',
                                          style: TextStyle(
                                            color: hasVoted
                                                ? Theme.of(context).colorScheme.onSecondary
                                                : Theme.of(context).colorScheme.onSurface,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                              Text(
                                'Ends: ${_formatDate(session.endDate)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, authService, _) {
        final user = authService.currentUser;
        if (user == null) {
          return const AuthScreen();
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Participatory Democracy'),
            actions: [
              IconButton(
                icon: const Icon(Icons.notifications_none),
                onPressed: () {
                  // Notification feature - to be implemented
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Notifications coming soon!')),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.logout),
                onPressed: () async {
                  await authService.signOut();
                  if (mounted) {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const AuthScreen()),
                    );
                  }
                },
                tooltip: 'Logout',
              ),
            ],
          ),
          body: _buildRoleBasedDashboard(user),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _selectedIndex,
            onTap: _onBottomNavTapped,
            selectedItemColor: Theme.of(context).colorScheme.primary,
            unselectedItemColor:
                Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
            items: [
              const BottomNavigationBarItem(
                icon: Icon(Icons.dashboard),
                label: 'Dashboard',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.description),
                label: 'Proposals',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.person),
                label: 'Profile',
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  String _getVotingMethodName(VotingMethod method) {
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
        return 'Instant Runoff';
      case VotingMethod.starVoting:
        return 'STAR Voting';
      case VotingMethod.rangeVoting:
        return 'Range Voting';
      case VotingMethod.majorityJudgment:
        return 'Majority Judgment';
      case VotingMethod.quadraticVoting:
        return 'Quadratic Voting';
      case VotingMethod.condorcet:
        return 'Condorcet';
      case VotingMethod.bordaCount:
        return 'Borda Count';
      case VotingMethod.cumulativeVoting:
        return 'Cumulative Voting';
      case VotingMethod.kemenyYoung:
        return 'Kemeny-Young';
      case VotingMethod.dualChoice:
        return 'Dual Choice';
      case VotingMethod.weightVoting:
        return 'Weight Voting';
    }
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
      default:
        return Colors.grey;
    }
  }

  Color _getRoleColor(UserRole role) {
    switch (role) {
      case UserRole.admin:
        return Colors.red;
      case UserRole.moderator:
        return Colors.orange;
      case UserRole.proposer:
        return Colors.green;
      case UserRole.user:
        return Colors.blue;
    }
  }

  // New method to build the voting systems management tab
  Widget _buildVotingSystemsManagementTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Available Voting Methods Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Available Voting Methods',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        _isSavingAvailableMethods
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : ElevatedButton.icon(
                                onPressed: _saveAvailableVotingMethods,
                                icon: const Icon(Icons.save),
                                label: const Text('Save Changes'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Theme.of(context).colorScheme.primary,
                                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                                ),
                              ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Control which voting methods are available for proposers to select when creating proposals.',
                      style: TextStyle(fontStyle: FontStyle.italic),
                    ),
                    const SizedBox(height: 16),
                    _isLoadingAvailableMethods
                        ? const Center(child: CircularProgressIndicator())
                        : ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: VotingMethod.values.length,
                            itemBuilder: (context, index) {
                              final method = VotingMethod.values[index];
                              final methodName = method.toString().split('.').last;
                              final isAvailable = _availableVotingMethods[methodName] ?? true;
                              
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                elevation: 0,
                                color: isAvailable 
                                    ? Theme.of(context).colorScheme.surfaceVariant
                                    : Theme.of(context).colorScheme.surface,
                                child: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _getMethodName(method),
                                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              _getMethodDescription(method),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Switch(
                                        value: isAvailable,
                                        onChanged: (value) {
                                          setState(() {
                                            _availableVotingMethods[methodName] = value;
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Recommended Voting Methods Card
            Card(
              elevation: 3,
              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.star, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          'Recommended Voting Methods',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'These methods are fully implemented and ready for use:',
                      style: TextStyle(fontStyle: FontStyle.italic),
                    ),
                    const SizedBox(height: 12),
                    _buildRecommendedMethodCard(
                      'Schulze Method',
                      'A Condorcet method that finds a winner through pairwise comparisons. The algorithm calculates the strongest paths between candidates using the Floyd-Warshall algorithm.',
                      VotingMethod.schulze,
                      Icons.trending_up,
                      Colors.purple,
                    ),
                    const SizedBox(height: 8),
                    _buildRecommendedMethodCard(
                      'Majority Runoff',
                      'If no option receives a majority, a second round is held between the top two options. Ensures the winner has majority support.',
                      VotingMethod.majorityRunoff,
                      Icons.how_to_vote,
                      Colors.blue,
                    ),
                    const SizedBox(height: 8),
                    _buildRecommendedMethodCard(
                      'Approval Voting',
                      'Voters can select multiple options they approve of. The option with the most approvals wins.',
                      VotingMethod.approvalVoting,
                      Icons.check_circle_outline,
                      Colors.green,
                    ),
                    const SizedBox(height: 8),
                    _buildRecommendedMethodCard(
                      'First Past The Post',
                      'The simplest voting method where voters select one option, and the option with the most votes wins.',
                      VotingMethod.firstPastThePost,
                      Icons.looks_one,
                      Colors.orange,
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Platform Default Voting Method Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Platform Default Voting Method',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 16),
                    FutureBuilder<VotingMethod>(
                      future: widget.databaseService.getDefaultVotingMethod(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }

                        // Use the result from the database service or default to First Past The Post
                        VotingMethod defaultMethod =
                            snapshot.data ?? VotingMethod.firstPastThePost;

                        // Initialize local state if not set
                        _selectedDefaultMethod ??= defaultMethod;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DropdownButtonFormField<VotingMethod>(
                              isExpanded: true,
                              value: _selectedDefaultMethod,
                              decoration: const InputDecoration(
                                labelText: 'Default Voting Method',
                                border: OutlineInputBorder(),
                                helperText:
                                    'This will be the default method for new vote sessions',
                              ),
                              items: VotingMethod.values.map((method) {
                                return DropdownMenuItem<VotingMethod>(
                                  value: method,
                                  child: Text(_getMethodName(method)),
                                );
                              }).toList(),
                              onChanged: (value) async {
                                if (value != null) {
                                  setState(() {
                                    _selectedDefaultMethod = value;
                                  });
                                  // Use the database service to update the default voting method
                                  final success = await widget.databaseService
                                      .updateDefaultVotingMethod(value);

                                  if (success) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'Default voting method updated successfully')),
                                    );
                                  } else {
                                    // Even if the server update failed, we'll still show the selected method in the UI
                                    // This provides a better user experience while we wait for Firebase permissions to be fixed
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                            'Settings saved locally. Server update will be available soon.'),
                                        duration: Duration(seconds: 5),
                                      ),
                                    );
                                  }
                                }
                              },
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'About this method:',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
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
                              child: Text(
                                _getMethodDescription(_selectedDefaultMethod ?? defaultMethod),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Topic-Specific Default Methods',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 16),
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('topics')
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }

                        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                          return const Center(child: Text('No topics found'));
                        }

                        return ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: snapshot.data!.docs.length,
                          itemBuilder: (context, index) {
                            final topicDoc = snapshot.data!.docs[index];
                            final topicData =
                                topicDoc.data() as Map<String, dynamic>;
                            final topicId = topicDoc.id;
                            final topicTitle = topicData['title'] as String? ??
                                'Unknown Topic';

                            return StreamBuilder<DocumentSnapshot>(
                              stream: FirebaseFirestore.instance
                                  .collection('settings')
                                  .doc('topicVoting_$topicId')
                                  .snapshots(),
                              builder: (context, settingsSnapshot) {
                                VotingMethod topicMethod =
                                    VotingMethod.firstPastThePost;

                                if (settingsSnapshot.hasData &&
                                    settingsSnapshot.data!.exists) {
                                  final data = settingsSnapshot.data!.data()
                                      as Map<String, dynamic>?;
                                  if (data != null &&
                                      data.containsKey('method')) {
                                    final methodStr = data['method'] as String;
                                    try {
                                      topicMethod =
                                          VotingMethod.values.firstWhere(
                                        (method) =>
                                            method.toString().split('.').last ==
                                            methodStr,
                                        orElse: () =>
                                            VotingMethod.firstPastThePost,
                                      );
                                    } catch (e) {
                                      print(
                                          'Error parsing topic voting method: $e');
                                    }
                                  }
                                }

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 16.0),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          topicTitle,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: DropdownButtonFormField<
                                            VotingMethod>(
                                          isExpanded: true,
                                          value: topicMethod,
                                          decoration: const InputDecoration(
                                            labelText: 'Method',
                                            border: OutlineInputBorder(),
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 8),
                                          ),
                                          items:
                                              VotingMethod.values.map((method) {
                                            return DropdownMenuItem<
                                                VotingMethod>(
                                              value: method,
                                              child: Text(
                                                  _getMethodName(method),
                                                  style: const TextStyle(
                                                      fontSize: 14)),
                                            );
                                          }).toList(),
                                          onChanged: (value) async {
                                            if (value != null) {
                                              try {
                                                await FirebaseFirestore.instance
                                                    .collection('settings')
                                                    .doc('topicVoting_$topicId')
                                                    .set({
                                                  'method': value
                                                      .toString()
                                                      .split('.')
                                                      .last,
                                                  'topicId': topicId,
                                                  'updatedAt': FieldValue
                                                      .serverTimestamp(),
                                                }, SetOptions(merge: true));

                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  SnackBar(
                                                      content: Text(
                                                          'Default method for "$topicTitle" updated')),
                                                );
                                              } catch (e) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  SnackBar(
                                                      content:
                                                          Text('Error: $e')),
                                                );
                                              }
                                            }
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Available Voting Methods',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 16),
                    StreamBuilder<DocumentSnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('settings')
                          .doc('availableVotingMethods')
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }

                        Map<String, bool> availableMethods = {};

                        // Initialize with all methods available by default
                        for (var method in VotingMethod.values) {
                          availableMethods[method.toString().split('.').last] =
                              true;
                        }

                        if (snapshot.hasData && snapshot.data!.exists) {
                          final data =
                              snapshot.data!.data() as Map<String, dynamic>?;
                          if (data != null && data.containsKey('methods')) {
                            final methods =
                                data['methods'] as Map<String, dynamic>?;
                            if (methods != null) {
                              methods.forEach((key, value) {
                                if (value is bool) {
                                  availableMethods[key] = value;
                                }
                              });
                            }
                          }
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Enable or disable voting methods that proposers can choose:',
                              style: TextStyle(fontStyle: FontStyle.italic),
                            ),
                            const SizedBox(height: 16),
                            Wrap(
  spacing: 16,
  runSpacing: 16,
  children: VotingMethod.values.map((method) {
    final methodName = method.toString().split('.').last;
    final isAvailable = availableMethods[methodName] ?? true;

    // Determine implementation status
    String statusLabel;
    Color statusColor;
    switch (method) {
      case VotingMethod.firstPastThePost:
      case VotingMethod.approvalVoting:
      case VotingMethod.majorityRunoff:
        statusLabel = 'COMPLETED';
        statusColor = Colors.green;
        break;
      default:
        statusLabel = 'PROTOTYPE';
        statusColor = Colors.orange;
    }

    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_getMethodName(method)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: statusColor.withOpacity(0.6)),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(
                color: statusColor,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
      selected: isAvailable,
      onSelected: (selected) async {
        try {
          availableMethods[methodName] = selected;
          await FirebaseFirestore.instance
              .collection('settings')
              .doc('availableVotingMethods')
              .set({
            'methods': availableMethods,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    '${_getMethodName(method)} is now ${selected ? 'available' : 'unavailable'}')),
          );
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      },
      selectedColor:
          Theme.of(context).colorScheme.primary.withOpacity(0.2),
      checkmarkColor: Theme.of(context).colorScheme.primary,
    );
  }).toList(),
),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
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

  // Helper method to build a recommended voting method card with icon and description
  Widget _buildRecommendedMethodCard(String title, String description, VotingMethod method, IconData icon, Color color) {
    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        onTap: () async {
          // Set this method as the default when clicked
          setState(() {
            _selectedDefaultMethod = method;
          });
          
          // Update the default voting method in the database
          final success = await widget.databaseService.updateDefaultVotingMethod(method);
          
          if (success) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$title set as the default voting method')),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Settings saved locally. Server update will be available soon.'),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: color.withOpacity(0.2),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          setState(() {
                            _selectedDefaultMethod = method;
                          });
                          await widget.databaseService.updateDefaultVotingMethod(method);
                        },
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text('Set as Default'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: color,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getMethodDescription(VotingMethod method) {
    switch (method) {
      case VotingMethod.firstPastThePost:
        return 'The simplest voting method where voters select one option, and the option with the most votes wins. Best for simple binary decisions. [FULLY IMPLEMENTED]';
      case VotingMethod.approvalVoting:
        return 'Voters can select multiple options they approve of. The option with the most approvals wins. Good for selecting from multiple acceptable options. [FULLY IMPLEMENTED]';
      case VotingMethod.majorityRunoff:
        return 'If no option receives a majority, a second round is held between the top two options. Ensures the winner has majority support. [FULLY IMPLEMENTED]';
      case VotingMethod.schulze:
        return 'A Condorcet method that finds a winner through pairwise comparisons. The algorithm calculates the strongest paths between candidates using the Floyd-Warshall algorithm. Excellent for complex decisions with many options. [FULLY IMPLEMENTED]';
      case VotingMethod.instantRunoff:
        return 'Voters rank options in order of preference. The option with the fewest first-choice votes is eliminated, and those votes transfer to the voters\'s next choices. [PROTOTYPE]';
      case VotingMethod.starVoting:
        return 'Score Then Automatic Runoff: Voters score each option from 0-5, then the two highest-scoring options advance to an automatic runoff. [PROTOTYPE]';
      case VotingMethod.rangeVoting:
        return 'Voters rate each option on a scale (e.g., 0-10). The option with the highest average rating wins. [PROTOTYPE]';
      case VotingMethod.majorityJudgment:
        return 'Voters assign qualitative ratings to each option (e.g., "Excellent" to "Reject"). The option with the highest median rating wins. [PROTOTYPE]';
      case VotingMethod.quadraticVoting:
        return 'Voters have a budget of credits and can allocate them across options. The cost of votes increases quadratically, encouraging sincere voting. [PROTOTYPE]';
      case VotingMethod.condorcet:
        return 'A ranking method where the winner is the option that would win a head-to-head comparison against every other option. [PROTOTYPE]';
      case VotingMethod.bordaCount:
        return 'Voters rank options, and points are assigned based on rank (n points for first place, n-1 for second, etc.). The option with the most points wins. [PROTOTYPE]';
      case VotingMethod.cumulativeVoting:
        return 'Voters have multiple votes they can distribute among options as they choose. Good for expressing strength of preference. [PROTOTYPE]';
      case VotingMethod.kemenyYoung:
        return 'A ranking method that finds the ordering of options that minimizes the number of disagreements with voters\'s rankings. [PROTOTYPE]';
      case VotingMethod.dualChoice:
        return 'A two-round system where voters first select from all options, then choose between the top two in a second round. [PROTOTYPE]';
      case VotingMethod.weightVoting:
        return 'Votes are weighted based on predetermined factors. Can be used when some voters should have more influence than others. [PROTOTYPE]';
      default:
        return 'No description available.';
    }
  }
}
