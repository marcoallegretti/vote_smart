import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/data_models.dart';
import '../services/database_service.dart';
import '../services/delegation_service.dart';
import '../services/voting_service.dart';
import '../services/audit_service.dart';
import '../widgets/result_widgets.dart';
import '../widgets/ranking_results_widget.dart';
import '../widgets/score_results_widget.dart';
import '../screens/results_screen.dart';

/// Implementation status of voting methods
enum ImplementationStatus {
  completed, // Fully implemented and tested
  prototype, // Prototype implementation, not fully tested
}

class VotingScreen extends StatefulWidget {
  final String sessionId;
  final DatabaseService databaseService;
  final AuditService auditService;

  const VotingScreen({
    super.key, 
    required this.sessionId,
    required this.databaseService,
    required this.auditService,
  });

  @override
  _VotingScreenState createState() => _VotingScreenState();
}

class _VotingScreenState extends State<VotingScreen>
    with TickerProviderStateMixin {
  late final DelegationService _delegationService; 
  late AnimationController _animationController;

  VoteSessionModel? _session;
  ProposalModel? _proposal;
  bool _isLoading = true;
  bool _hasVoted = false;
  bool _isSubmitting = false;
  List<Map<String, dynamic>> _allVotes = [];
  Map<String, dynamic>? _results;

  // Voting method state variables
  // Single choice (First Past The Post)
  String? _selectedOption;

  // Multiple choices (Approval Voting)
  List<String> _selectedOptions = [];

  // Ranking methods (Schulze, IRV, Condorcet, Borda, Kemeny-Young)
  Map<String, int> _rankings = {};

  // Range Voting and STAR Voting
  Map<String, double> _ratings = {};

  // Majority Judgment
  Map<String, String> _judgments = {};
  final List<String> _judgmentOptions = [
    'Excellent',
    'Very Good',
    'Good',
    'Acceptable',
    'Poor',
    'Reject'
  ];

  // Quadratic Voting
  Map<String, int> _quadraticVotes = {};
  int _remainingCredits = 100;

  // Cumulative Voting
  Map<String, int> _cumulativeVotes = {};
  int _remainingVotes = 10;

  // Weight Voting
  Map<String, double> _weights = {};

  @override
  void initState() {
    super.initState();
    _delegationService = DelegationService.withInstance(
      firestoreInstance: FirebaseFirestore.instance, 
      databaseService: widget.databaseService,
      auditService: widget.auditService,
    );
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _loadData();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _showResultsDialog() {
    if (_session == null || _results == null || _proposal == null) return;

    // Show a quick results dialog with option to see detailed view
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Voting Results',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                _proposal?.title ?? 'Vote',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color:
                      Theme.of(context).colorScheme.tertiary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.how_to_vote,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Voting Method: ${_getMethodName(_session!.method)}',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                    ),
                    _getImplementationStatusBadge(_session!.method),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: _buildQuickResultsContent(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _showDetailedResults();
                    },
                    icon: const Icon(Icons.analytics),
                    label: const Text('Detailed Analysis'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final session = await widget.databaseService.getVoteSessionById(widget.sessionId);
      if (session == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Session not found')),
          );
        }
        return;
      }

      // Load proposal
      _proposal =
          await widget.databaseService.getProposalById(session.proposalId);

      if (_proposal == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Proposal not found')),
          );
        }
        return;
      }

      // Check if user has already voted
      _hasVoted = await widget.databaseService.hasUserVoted(session.id);


      // Initialize voting method state
      _initializeVotingState();

      // If user has voted, load all votes and calculate results
      if (_hasVoted) {
        await _loadVotes();
      }

      setState(() {
        _session = session;
      });
    } catch (e) {
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

  Future<void> _loadVotes() async {
    try {
      // Load all votes for this session
      if (_session == null) {
        print('Error: Session is null in _loadVotes.');
        return;
      }
      final votes = await widget.databaseService.getVotesForSession(_session!.id);

      // Convert to format needed for calculations
      _allVotes = votes
          .map((vote) => {
                'userId': vote.userId,
                'choice': vote.choice,
                'isDelegated': vote.isDelegated,
              })
          .toList();

      // Calculate results based on voting method
      if (_allVotes.isNotEmpty) {
        // Ensure proposalId is available. _session.proposalId should be the ID of the proposal document.
        // If _session is not null (checked above), and proposalId is a non-nullable field on VoteSessionModel,
        // then _session.proposalId can be directly accessed.
        _results = await VotingService.calculateResults(
          _session!.method,
          _allVotes,
          _delegationService,
          _session!.proposalId,
        );
      }
    } catch (e) {
      print('Error loading votes: $e');
      if (mounted) {
        setState(() {
          _results = {"error": "Error loading votes: $e"};
        });
      }
    }
  }

  void _initializeVotingState() {
    if (_session == null) return;

    switch (_session!.method) {
      case VotingMethod.approvalVoting:
        _selectedOptions = [];
        break;
      case VotingMethod.schulze:
      case VotingMethod.instantRunoff:
      case VotingMethod.condorcet:
      case VotingMethod.bordaCount:
      case VotingMethod.kemenyYoung:
        _rankings = {};
        for (var option in _session!.options) {
          _rankings[option] = 0;
        }
        break;
      case VotingMethod.starVoting:
      case VotingMethod.rangeVoting:
        _ratings = {};
        for (var option in _session!.options) {
          _ratings[option] = 0.0;
        }
        break;
      case VotingMethod.majorityJudgment:
        _judgments = {};
        for (var option in _session!.options) {
          _judgments[option] = _judgmentOptions.last;
        }
        break;
      case VotingMethod.quadraticVoting:
        _quadraticVotes = {};
        for (var option in _session!.options) {
          _quadraticVotes[option] = 0;
        }
        _remainingCredits = 100;
        break;
      case VotingMethod.cumulativeVoting:
        _cumulativeVotes = {};
        for (var option in _session!.options) {
          _cumulativeVotes[option] = 0;
        }
        _remainingVotes = 10;
        break;
      case VotingMethod.weightVoting:
        _weights = {};
        for (var option in _session!.options) {
          _weights[option] = 0.0;
        }
        break;
      default:
        // First Past The Post and simple methods
        _selectedOption = null;
        break;
    }
  }

  Future<void> _submitVote() async {
    if (_session == null) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      dynamic choice;

      // Prepare the vote data based on the voting method
      switch (_session!.method) {
        case VotingMethod.firstPastThePost:
        case VotingMethod.majorityRunoff:
        case VotingMethod.dualChoice:
          choice = _selectedOption;
          break;
        case VotingMethod.approvalVoting:
          choice = _selectedOptions;
          break;
        case VotingMethod.schulze:
        case VotingMethod.instantRunoff:
        case VotingMethod.condorcet:
        case VotingMethod.bordaCount:
        case VotingMethod.kemenyYoung:
          choice = _rankings;
          break;
        case VotingMethod.starVoting:
        case VotingMethod.rangeVoting:
          choice = _ratings;
          break;
        case VotingMethod.majorityJudgment:
          choice = _judgments;
          break;
        case VotingMethod.quadraticVoting:
          choice = _quadraticVotes;
          break;
        case VotingMethod.cumulativeVoting:
          choice = _cumulativeVotes;
          break;
        case VotingMethod.weightVoting:
          choice = _weights;
          break;
      }

      // Cast the vote using positional arguments as suggested by lint errors
      await widget.databaseService.castVote(
        _session!.id, // First positional argument: Likely sessionId
        choice,       // Second positional argument: The user's choice
        // TODO: Add weight if session.method is weightVoting and _weights map is populated
        // weight: _session!.method == VotingMethod.weightVoting ? (_weights[choice] ?? 1.0) : 1.0,
      );

      // Load votes and calculate results
      await _loadVotes();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your vote has been recorded')),
      );

      setState(() {
        _hasVoted = true;
      });

      // Show results dialog after a short delay
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) {
          _showResultsDialog();
        }
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Widget _buildVotingInterface() {
    if (_session == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _proposal?.title ?? 'Vote',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        if (_proposal != null)
          Text(
            _proposal!.content,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        const SizedBox(height: 24),
        // Voting method information card
        Card(
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
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
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              'Voting Method: ${_getMethodName(_session!.method)}',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _getImplementationStatusBadge(_session!.method),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(_getMethodDescription(_session!.method)),
                const SizedBox(height: 8),
                ExpansionTile(
                  title: const Text('How to vote with this method'),
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  children: [
                    Text(_getMethodInstructions(_session!.method)),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        // Voting interface
        Text(
          'Your Vote',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 16),
        _hasVoted
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.check_circle,
                      size: 64,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'You have already voted in this session',
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () => _showResultsDialog(),
                      icon: const Icon(Icons.bar_chart),
                      label: const Text('View Results'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor:
                            Theme.of(context).colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                      ),
                    ),
                  ],
                ),
              )
            : _buildVotingMethod(),
        if (!_hasVoted)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24.0),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _canSubmitVote()
                    ? (_isSubmitting ? null : _submitVote)
                    : null,
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
                    : const Text('Submit Vote'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildVotingMethod() {
    if (_session == null) return const SizedBox.shrink();

    // This switch is exhaustive - all enum values are covered
    return switch (_session!.method) {
      VotingMethod.firstPastThePost ||
      VotingMethod.majorityRunoff ||
      VotingMethod.dualChoice =>
        _buildSingleChoiceVoting(),
      VotingMethod.approvalVoting => _buildApprovalVoting(),
      VotingMethod.schulze ||
      VotingMethod.instantRunoff ||
      VotingMethod.condorcet ||
      VotingMethod.bordaCount ||
      VotingMethod.kemenyYoung =>
        _buildRankingVoting(),
      VotingMethod.starVoting ||
      VotingMethod.rangeVoting =>
        _buildRangeVoting(),
      VotingMethod.majorityJudgment => _buildMajorityJudgmentVoting(),
      VotingMethod.quadraticVoting => _buildQuadraticVoting(),
      VotingMethod.cumulativeVoting => _buildCumulativeVoting(),
      VotingMethod.weightVoting => _buildWeightVoting(),
    };
  }

  Widget _buildSingleChoiceVoting() {
    return Column(
      children: _session!.options.map((option) {
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: RadioListTile<String>(
            title: Text(option),
            value: option,
            groupValue: _selectedOption,
            onChanged: (value) {
              setState(() {
                _selectedOption = value;
              });
            },
            activeColor: Theme.of(context).colorScheme.primary,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildApprovalVoting() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select all options you approve',
          style: TextStyle(color: Theme.of(context).colorScheme.secondary),
        ),
        const SizedBox(height: 8),
        ..._session!.options.map((option) {
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: CheckboxListTile(
              title: Text(option),
              value: _selectedOptions.contains(option),
              onChanged: (value) {
                setState(() {
                  if (value == true) {
                    _selectedOptions.add(option);
                  } else {
                    _selectedOptions.remove(option);
                  }
                });
              },
              activeColor: Theme.of(context).colorScheme.primary,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildRankingVoting() {
    // Temporarily sort options by their current rank
    final sortedOptions = _session!.options.toList()
      ..sort((a, b) => (_rankings[a] ?? 0).compareTo(_rankings[b] ?? 0));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Drag to rank options (1 = highest preference)',
          style: TextStyle(color: Theme.of(context).colorScheme.secondary),
        ),
        const SizedBox(height: 16),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          onReorder: (oldIndex, newIndex) {
            setState(() {
              if (oldIndex < newIndex) {
                newIndex -= 1;
              }
              final item = sortedOptions.removeAt(oldIndex);
              sortedOptions.insert(newIndex, item);

              // Update rankings
              for (int i = 0; i < sortedOptions.length; i++) {
                _rankings[sortedOptions[i]] = i + 1;
              }
            });
          },
          children: sortedOptions.asMap().entries.map((entry) {
            final option = entry.value;
            final rank = _rankings[option] ?? 0;

            return Card(
              key: ValueKey(option),
              margin: const EdgeInsets.only(bottom: 12),
              elevation: 0,
              color: rank == 0
                  ? Theme.of(context).colorScheme.surface.withOpacity(0.5)
                  : Theme.of(context).colorScheme.surface,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: CircleAvatar(
                  backgroundColor: rank == 0
                      ? Theme.of(context).colorScheme.primary.withOpacity(0.3)
                      : Theme.of(context).colorScheme.primary,
                  child: Text(
                    rank == 0 ? '-' : rank.toString(),
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimary),
                  ),
                ),
                title: Text(option),
                trailing: const Icon(Icons.drag_handle),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildRangeVoting() {
    final isStarVoting = _session!.method == VotingMethod.starVoting;
    final maxValue = isStarVoting ? 5.0 : 10.0;
    final divisions = isStarVoting ? 5 : 10;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isStarVoting
              ? 'Rate each option from 0 to 5 stars'
              : 'Rate each option from 0 to 10',
          style: TextStyle(color: Theme.of(context).colorScheme.secondary),
        ),
        const SizedBox(height: 16),
        ..._session!.options.map((option) {
          return Card(
            margin: const EdgeInsets.only(bottom: 20),
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: _ratings[option] ?? 0.0,
                          min: 0.0,
                          max: maxValue,
                          divisions: divisions,
                          label: (_ratings[option] ?? 0.0).toStringAsFixed(1),
                          onChanged: (value) {
                            setState(() {
                              _ratings[option] = value;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (isStarVoting)
                        Row(
                          children: List.generate(5, (index) {
                            return IconButton(
                              icon: Icon(
                                index < (_ratings[option] ?? 0.0)
                                    ? Icons.star
                                    : Icons.star_border,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              onPressed: () {
                                setState(() {
                                  _ratings[option] = index + 1.0;
                                });
                              },
                            );
                          }),
                        )
                      else
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              (_ratings[option] ?? 0.0).toStringAsFixed(1),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onPrimary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildMajorityJudgmentVoting() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select a judgment for each option',
          style: TextStyle(color: Theme.of(context).colorScheme.secondary),
        ),
        const SizedBox(height: 16),
        ..._session!.options.map((option) {
          return Card(
            margin: const EdgeInsets.only(bottom: 20),
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _judgmentOptions.map((judgment) {
                      final isSelected = _judgments[option] == judgment;
                      return ChoiceChip(
                        label: Text(
                          judgment,
                          style: TextStyle(
                            color: isSelected
                                ? Theme.of(context).colorScheme.onPrimary
                                : null,
                            fontWeight: isSelected ? FontWeight.bold : null,
                          ),
                        ),
                        selected: isSelected,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() {
                              _judgments[option] = judgment;
                            });
                          }
                        },
                        backgroundColor: Theme.of(context).colorScheme.surface,
                        selectedColor: _getJudgmentColor(judgment),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildQuadraticVoting() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Distribute your credits (remaining: $_remainingCredits)',
          style: TextStyle(color: Theme.of(context).colorScheme.secondary),
        ),
        Text(
          'Each vote costs votes² credits',
          style: TextStyle(color: Theme.of(context).colorScheme.secondary),
        ),
        const SizedBox(height: 16),
        ..._session!.options.map((option) {
          final votes = _quadraticVotes[option] ?? 0;
          final cost = votes * votes;

          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: votes > 0
                            ? () {
                                setState(() {
                                  _quadraticVotes[option] = votes - 1;
                                  _remainingCredits += (votes * votes) -
                                      ((votes - 1) * (votes - 1));
                                });
                              }
                            : null,
                      ),
                      Expanded(
                        child: Slider(
                          value: votes.toDouble(),
                          min: 0,
                          max: 10,
                          divisions: 10,
                          label: votes.toString(),
                          onChanged: (value) {
                            final newVotes = value.toInt();
                            if (newVotes != votes) {
                              final newCost = newVotes * newVotes;
                              final additionalCost = newCost - cost;

                              if (_remainingCredits >= additionalCost ||
                                  additionalCost < 0) {
                                setState(() {
                                  _quadraticVotes[option] = newVotes;
                                  _remainingCredits -= additionalCost;
                                });
                              }
                            }
                          },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: _remainingCredits >=
                                (votes + 1) * (votes + 1) - (votes * votes)
                            ? () {
                                setState(() {
                                  _quadraticVotes[option] = votes + 1;
                                  _remainingCredits -=
                                      ((votes + 1) * (votes + 1)) -
                                          (votes * votes);
                                });
                              }
                            : null,
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Votes: $votes',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        Text('Cost: $cost credits'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildCumulativeVoting() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Distribute your votes (remaining: $_remainingVotes)',
          style: TextStyle(color: Theme.of(context).colorScheme.secondary),
        ),
        const SizedBox(height: 16),
        ..._session!.options.map((option) {
          final votes = _cumulativeVotes[option] ?? 0;

          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: votes > 0
                            ? () {
                                setState(() {
                                  _cumulativeVotes[option] = votes - 1;
                                  _remainingVotes += 1;
                                });
                              }
                            : null,
                      ),
                      Expanded(
                        child: Slider(
                          value: votes.toDouble(),
                          min: 0,
                          max: 10,
                          divisions: 10,
                          label: votes.toString(),
                          onChanged: (value) {
                            final newVotes = value.toInt();
                            if (newVotes != votes) {
                              final diff = newVotes - votes;

                              if (_remainingVotes >= diff || diff < 0) {
                                setState(() {
                                  _cumulativeVotes[option] = newVotes;
                                  _remainingVotes -= diff;
                                });
                              }
                            }
                          },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: _remainingVotes > 0
                            ? () {
                                setState(() {
                                  _cumulativeVotes[option] = votes + 1;
                                  _remainingVotes -= 1;
                                });
                              }
                            : null,
                      ),
                    ],
                  ),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16.0, vertical: 8.0),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$votes votes',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildWeightVoting() {
    double currentTotal = 0;
    for (var option in _session!.options) {
      currentTotal += _weights[option] ?? 0;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Distribute weights (total should equal 1.0)',
          style: TextStyle(color: Theme.of(context).colorScheme.secondary),
        ),
        Text(
          'Current total: ${currentTotal.toStringAsFixed(2)}',
          style: TextStyle(
            color: (currentTotal - 1.0).abs() < 0.01
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.error,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        ..._session!.options.map((option) {
          final weight = _weights[option] ?? 0.0;

          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: weight,
                          min: 0.0,
                          max: 1.0,
                          divisions: 20,
                          label: weight.toStringAsFixed(2),
                          onChanged: (value) {
                            setState(() {
                              _weights[option] = value;
                            });
                          },
                        ),
                      ),
                      SizedBox(
                        width: 60,
                        child: Text(
                          weight.toStringAsFixed(2),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  bool _canSubmitVote() {
    if (_session == null) return false;

    switch (_session!.method) {
      case VotingMethod.firstPastThePost:
      case VotingMethod.majorityRunoff:
      case VotingMethod.dualChoice:
        return _selectedOption != null;
      case VotingMethod.approvalVoting:
        return _selectedOptions.isNotEmpty;
      case VotingMethod.schulze:
      case VotingMethod.instantRunoff:
      case VotingMethod.condorcet:
      case VotingMethod.bordaCount:
      case VotingMethod.kemenyYoung:
        // Check if all options have been ranked
        for (var rank in _rankings.values) {
          if (rank == 0) return false;
        }
        return true;
      case VotingMethod.starVoting:
      case VotingMethod.rangeVoting:
        // At least one option should have a non-zero rating
        return _ratings.values.any((rating) => rating > 0);
      case VotingMethod.majorityJudgment:
        // All options should have a judgment
        return _judgments.length == _session!.options.length;
      case VotingMethod.quadraticVoting:
        // At least one option should have votes
        return _quadraticVotes.values.any((votes) => votes > 0);
      case VotingMethod.cumulativeVoting:
        // All votes should be distributed
        return _remainingVotes == 0;
      case VotingMethod.weightVoting:
        // Weights should sum up to 1.0 (with a small margin of error)
        double total = 0;
        for (var weight in _weights.values) {
          total += weight;
        }
        return (total - 1.0).abs() < 0.01;
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_hasVoted ? 'Results' : 'Vote'),
        actions: [
          if (_hasVoted)
            IconButton(
              icon: const Icon(Icons.bar_chart),
              onPressed: () {
                _showResultsDialog();
              },
              tooltip: 'View results',
            ),
          if (_hasVoted)
            IconButton(
              icon: const Icon(Icons.analytics),
              onPressed: () {
                _showDetailedResults();
              },
              tooltip: 'View detailed analysis',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: _buildVotingInterface(),
            ),
    );
  }

  /// Determines the implementation status of a voting method.
  ///
  /// Returns whether a voting method is fully implemented and tested (completed)
  /// or just a prototype implementation (prototype).
  ImplementationStatus _getMethodImplementationStatus(VotingMethod method) {
    switch (method) {
      case VotingMethod.firstPastThePost:
      case VotingMethod.approvalVoting:
      case VotingMethod.majorityRunoff:
      case VotingMethod.schulze:
        return ImplementationStatus.completed;
      default:
        return ImplementationStatus.prototype;
    }
  }

  /// Returns a badge widget indicating the implementation status of a voting method.
  Widget _getImplementationStatusBadge(VotingMethod method) {
    final status = _getMethodImplementationStatus(method);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: status == ImplementationStatus.completed
            ? Colors.green.withOpacity(0.2)
            : Colors.amber.withOpacity(0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: status == ImplementationStatus.completed
              ? Colors.green
              : Colors.amber,
          width: 1,
        ),
      ),
      child: Text(
        status == ImplementationStatus.completed ? 'Implemented' : 'Prototype',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: status == ImplementationStatus.completed
              ? Colors.green.shade800
              : Colors.amber.shade800,
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
        return 'Voters rank options in order of preference. The option with the fewest first-choice votes is eliminated, and votes transfer to the voters\'s next choices.';
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
        return 'A ranking method that finds the ordering of options that minimizes the number of disagreements with voters\' rankings.';
      case VotingMethod.dualChoice:
        return 'This is a two-round system. In the first round, select ONE option. In the second round, you will choose between the top two options from the first round.';
      case VotingMethod.weightVoting:
        return 'Votes are weighted based on predetermined factors. Can be used when some voters should have more influence than others.';
    }
  }

  String _getMethodInstructions(VotingMethod method) {
    switch (method) {
      case VotingMethod.firstPastThePost:
        return 'Select ONE option that you prefer the most. The option with the most votes wins.';
      case VotingMethod.approvalVoting:
        return 'Select ALL options that you approve of. You can select as many as you like. The option with the most approvals wins.';
      case VotingMethod.majorityRunoff:
        return 'Select ONE option. If no option gets more than 50% of votes, a second round will be held between the top two options.';
      case VotingMethod.schulze:
        return 'Rank ALL options in your order of preference (1 = most preferred). The winner is determined through a series of pairwise comparisons.';
      case VotingMethod.instantRunoff:
        return 'Rank ALL options in order of preference. The option with the fewest first-choice votes will be eliminated, and those votes will transfer to the voters\' next choices.';
      case VotingMethod.starVoting:
        return 'Rate EACH option on a scale from 0-5 stars. The two highest-rated options advance to an automatic runoff where the option preferred by more voters wins.';
      case VotingMethod.rangeVoting:
        return 'Rate EACH option on a scale from 0-10. The option with the highest average rating wins.';
      case VotingMethod.majorityJudgment:
        return 'Assign a qualitative rating to EACH option (Excellent, Very Good, Good, Acceptable, Poor, or Reject). The option with the highest median rating wins.';
      case VotingMethod.quadraticVoting:
        return 'You have a budget of credits to allocate across options. The cost of votes increases quadratically (1 vote = 1 credit, 2 votes = 4 credits, 3 votes = 9 credits, etc.). Allocate your credits to express the strength of your preferences.';
      case VotingMethod.condorcet:
        return 'Rank ALL options in your order of preference. The winner is the option that would win a one-on-one comparison against every other option.';
      case VotingMethod.bordaCount:
        return 'Rank ALL options in your order of preference. Points are assigned based on rank (n points for first place, n-1 for second, etc.). The option with the most points wins.';
      case VotingMethod.cumulativeVoting:
        return 'You have multiple votes to distribute among the options as you choose. You can put all your votes on one option or spread them across multiple options.';
      case VotingMethod.kemenyYoung:
        return 'Rank ALL options in your order of preference. The system finds the ranking that minimizes the number of disagreements with voters\' rankings.';
      case VotingMethod.dualChoice:
        return 'This is a two-round system. In the first round, select ONE option. In the second round, you will choose between the top two options from the first round.';
      case VotingMethod.weightVoting:
        return 'Your vote is weighted based on predetermined factors. Cast your vote for ONE option, and the system will apply the appropriate weight.';
    }
  }

  Color _getJudgmentColor(String judgment) {
    switch (judgment) {
      case 'Excellent':
        return Colors.green;
      case 'Very Good':
        return Colors.lightGreen;
      case 'Good':
        return Colors.lime;
      case 'Acceptable':
        return Colors.amber;
      case 'Poor':
        return Colors.orange;
      case 'Reject':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  void _showDetailedResults() {
    if (_session == null || _results == null || _proposal == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ResultsScreen(
          sessionId: widget.sessionId,
          session: _session!,
          proposal: _proposal!,
          results: _results!,
          delegationService: _delegationService,
        ),
      ),
    );
  }

  Widget _buildQuickResultsContent() {
    if (_results == null || _session == null) {
      return const Center(child: Text('No results available'));
    }

    final winner = _results!['winner'] as String?;
    final counts = _results!['counts'] as Map<String, dynamic>?;
    final totalVotes = _results!['totalVotes'] as int? ?? 0;
    final majorityAchieved = _results!['majorityAchieved'] as bool? ?? false;
    final runoffNeeded = _results!['runoffNeeded'] as bool? ?? false;
    final runoffCandidates = _results!['runoffCandidates'] as List<dynamic>?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (winner != null)
          ResultWinnerCard(
            winner: winner,
            subtitle: counts?[winner] != null
                ? '${counts![winner]} votes (${((counts[winner] as int) / totalVotes * 100).toStringAsFixed(1)}%)'
                : null,
          ),
        const SizedBox(height: 16),
        ResultSummaryCard(
          totalVotes: totalVotes,
          majorityAchieved: majorityAchieved,
          runoffNeeded: runoffNeeded,
          runoffCandidates: runoffCandidates?.cast<String>().toList(),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.bar_chart,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Quick Results',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildVoteCountsDisplay(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVoteCountsDisplay() {
    if (_session == null) return const SizedBox.shrink();

    return FutureBuilder<List<VoteModel>>(
      future: widget.databaseService.getVotesForSession(widget.sessionId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final votes = snapshot.data!;
        final counts = votes.fold(
          <String, int>{},
          (counts, vote) {
            final choice = vote.choice;
            if (choice is String) {
              counts[choice] = (counts[choice] ?? 0) + 1;
            } else if (choice is List<String>) {
              for (var option in choice) {
                counts[option] = (counts[option] ?? 0) + 1;
              }
            }
            return counts;
          },
        );

        final winner = _results!['winner'] as String?;
        final totalVotes = votes.length;

        switch (_session!.method) {
          case VotingMethod.firstPastThePost:
          case VotingMethod.majorityRunoff:
          case VotingMethod.dualChoice:
          case VotingMethod.approvalVoting:
            final sortedOptions = counts.entries.toList()
              ..sort((a, b) => (b.value).compareTo(a.value));

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Bar chart
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var entry in sortedOptions)
                      ResultBar(
                        option: entry.key,
                        value: entry.value.toDouble(),
                        maxValue: sortedOptions.first.value.toDouble(),
                        label:
                            '${entry.value} votes (${((entry.value / totalVotes) * 100).toStringAsFixed(1)}%)',
                        isWinner: entry.key == winner,
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                // Pie chart
                ResultPieChart(
                  counts: Map.fromEntries(
                    counts.entries.map(
                      (e) => MapEntry(e.key, e.value),
                    ),
                  ),
                  winner: winner,
                ),
              ],
            );

          case VotingMethod.schulze:
          case VotingMethod.instantRunoff:
          case VotingMethod.condorcet:
          case VotingMethod.bordaCount:
          case VotingMethod.kemenyYoung:
            // Use the specialized ranking visualization for ranking-based methods
            return RankingResultsDisplay(
              results: _results!,
              winner: winner,
              methodName: _getMethodName(_session!.method),
            );

          case VotingMethod.starVoting:
          case VotingMethod.rangeVoting:
          case VotingMethod.majorityJudgment:
          case VotingMethod.quadraticVoting:
          case VotingMethod.cumulativeVoting:
          case VotingMethod.weightVoting:
            // Use the specialized score visualization for score-based methods
            return ScoreResultsDisplay(
              results: _results!,
              winner: winner,
              methodName: _getMethodName(_session!.method),
            );
        }
      },
    );
  }

}
