import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'dart:io';

import '../models/data_models.dart';
import '../services/database_service.dart';
import '../services/delegation_service.dart';
import '../widgets/result_widgets.dart';
import '../widgets/ranking_results_widget.dart';
import '../widgets/score_results_widget.dart';
import '../widgets/comparison_chart_widget.dart';

/// A dedicated screen for displaying comprehensive voting results
class ResultsScreen extends StatefulWidget {
  final String sessionId;
  final VoteSessionModel session;
  final ProposalModel proposal;
  final Map<String, dynamic> results;
  final DelegationService delegationService;

  const ResultsScreen({
    super.key,
    required this.sessionId,
    required this.session,
    required this.proposal,
    required this.results,
    required this.delegationService,
  });

  @override
  _ResultsScreenState createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final DatabaseService _databaseService = DatabaseService();

  List<Map<String, dynamic>> _allVotes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadVotes();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadVotes() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Load all votes for this session
      final votes = await _databaseService.getVotesForSession(widget.sessionId);

      // Convert to format needed for calculations
      _allVotes = votes
          .map((vote) => {
                'userId': vote.userId,
                'choice': vote.choice,
                'isDelegated': vote.isDelegated,
              })
          .toList();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading votes: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _exportResults() async {
    final pdf = pw.Document();

    // Add title page
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Center(
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text(
                  'Voting Results',
                  style: pw.TextStyle(
                    fontSize: 28,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 16),
                pw.Text(
                  widget.proposal.title,
                  style: pw.TextStyle(
                    fontSize: 20,
                  ),
                ),
                pw.SizedBox(height: 40),
                pw.Text(
                  'Method: ${_getMethodName(widget.session.method)}',
                  style: pw.TextStyle(
                    fontSize: 16,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  'Total Votes: ${widget.results['totalVotes'] ?? 0}',
                  style: pw.TextStyle(
                    fontSize: 16,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  'Winner: ${widget.results['winner'] ?? 'No winner'}',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    // Add results details
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Header(
                level: 0,
                child: pw.Text('Detailed Results'),
              ),
              pw.SizedBox(height: 20),
              pw.Text(
                'Voting Method: ${_getMethodName(widget.session.method)}',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                _getMethodDescription(widget.session.method),
                style: pw.TextStyle(
                  fontSize: 12,
                ),
              ),
              pw.SizedBox(height: 20),
              pw.Header(
                level: 1,
                child: pw.Text('Vote Distribution'),
              ),
              pw.SizedBox(height: 12),
              _buildPdfResultsTable(),
            ],
          );
        },
      ),
    );

    // Save the PDF
    final output = await getTemporaryDirectory();
    final file = File('${output.path}/voting_results.pdf');
    await file.writeAsBytes(await pdf.save());

    // Share the PDF
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'Voting Results: ${widget.proposal.title}',
    );
  }

  pw.Widget _buildPdfResultsTable() {
    final counts = widget.results['counts'] as Map<String, dynamic>?;
    if (counts == null) return pw.Container();

    final sortedOptions = counts.entries.toList()
      ..sort((a, b) => (b.value as num).compareTo(a.value as num));

    final totalVotes = widget.results['totalVotes'] as int? ?? 0;

    return pw.Table(
      border: pw.TableBorder.all(),
      children: [
        // Header row
        pw.TableRow(
          decoration: const pw.BoxDecoration(
            color: PdfColor.fromInt(0xFFE0E0E0),
          ),
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.all(8),
              child: pw.Text(
                'Option',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(8),
              child: pw.Text(
                'Votes',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(8),
              child: pw.Text(
                'Percentage',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
            ),
          ],
        ),
        // Data rows
        ...sortedOptions.map((entry) {
          final percentage = totalVotes > 0
              ? ((entry.value as num) / totalVotes * 100).toStringAsFixed(1)
              : '0.0';

          return pw.TableRow(
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.all(8),
                child: pw.Text(entry.key),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(8),
                child: pw.Text(entry.value.toString()),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(8),
                child: pw.Text('$percentage%'),
              ),
            ],
          );
        }),
      ],
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
        return 'The simplest voting method where voters select one option, and the option with the most votes wins.';
      case VotingMethod.approvalVoting:
        return 'Voters can select multiple options they approve of. The option with the most approvals wins.';
      case VotingMethod.majorityRunoff:
        return 'If no option receives a majority, a second round is held between the top two options.';
      case VotingMethod.schulze:
        return 'A complex ranking method that compares all possible pairs of options to find the strongest path.';
      case VotingMethod.instantRunoff:
        return 'Voters rank options in order of preference. The option with the fewest first-choice votes is eliminated, and votes transfer to the voters\'s next choices.';
      case VotingMethod.starVoting:
        return 'Score Then Automatic Runoff: Voters score each option from 0-5, then the two highest-scoring options advance to an automatic runoff.';
      case VotingMethod.rangeVoting:
        return 'Voters rate each option on a scale. The option with the highest average rating wins.';
      case VotingMethod.majorityJudgment:
        return 'Voters assign qualitative ratings to each option. The option with the highest median rating wins.';
      case VotingMethod.quadraticVoting:
        return 'Voters have a budget of credits and can allocate them across options. The cost of votes increases quadratically.';
      case VotingMethod.condorcet:
        return 'A ranking method where the winner is the option that would win a head-to-head comparison against every other option.';
      case VotingMethod.bordaCount:
        return 'Voters rank options, and points are assigned based on rank. The option with the most points wins.';
      case VotingMethod.cumulativeVoting:
        return 'Voters have multiple votes they can distribute among options as they choose.';
      case VotingMethod.kemenyYoung:
        return 'A ranking method that finds the ordering of options that minimizes the number of disagreements with voters\'s rankings.';
      case VotingMethod.dualChoice:
        return 'A two-round system where voters first select from all options, then choose between the top two in a second round.';
      case VotingMethod.weightVoting:
        return 'Votes are weighted based on predetermined factors.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final winner = widget.results['winner'] as String?;

    return Scaffold(
      appBar: AppBar(
        title: Text('Results: ${widget.proposal.title}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _exportResults,
            tooltip: 'Export and share results',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Summary'),
            Tab(text: 'Details'),
            Tab(text: 'Analytics'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                // Summary Tab
                _buildSummaryTab(winner, theme),

                // Details Tab
                _buildDetailsTab(winner, theme),

                // Analytics Tab
                _buildAnalyticsTab(theme),
              ],
            ),
    );
  }

  Widget _buildSummaryTab(String? winner, ThemeData theme) {
    final totalVotes = widget.results['totalVotes'] as int? ?? 0;
    final majorityAchieved =
        widget.results['majorityAchieved'] as bool? ?? false;
    final runoffNeeded = widget.results['runoffNeeded'] as bool? ?? false;
    final runoffCandidates =
        widget.results['runoffCandidates'] as List<dynamic>?;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            elevation: 4,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Voting Method',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.how_to_vote,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _getMethodName(widget.session.method),
                        style: theme.textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(_getMethodDescription(widget.session.method)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (winner != null)
            ResultWinnerCard(
              winner: winner,
              subtitle: widget.results['counts']?[winner] != null
                  ? '${widget.results['counts'][winner]} votes (${((widget.results['counts'][winner] as int) / totalVotes * 100).toStringAsFixed(1)}%)'
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
          Card(
            elevation: 4,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Quick Results',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildVoteCountsDisplay(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsTab(String? winner, ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Detailed Results',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          _buildDetailedResults(winner, theme),
        ],
      ),
    );
  }

  Widget _buildAnalyticsTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Analytics',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          _buildVotingAnalytics(theme),
        ],
      ),
    );
  }

  Widget _buildVoteCountsDisplay() {
    final counts = widget.results['counts'] as Map<String, dynamic>?;
    if (counts == null) return const SizedBox.shrink();

    final winner = widget.results['winner'] as String?;
    final totalVotes = widget.results['totalVotes'] as int? ?? 0;

    switch (widget.session.method) {
      case VotingMethod.firstPastThePost:
      case VotingMethod.majorityRunoff:
      case VotingMethod.dualChoice:
      case VotingMethod.approvalVoting:
        final sortedOptions = counts.entries.toList()
          ..sort((a, b) => (b.value as int).compareTo(a.value as int));

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
                    value: (entry.value as int).toDouble(),
                    maxValue: (sortedOptions.first.value as int).toDouble(),
                    label:
                        '${entry.value} votes (${((entry.value as int) / totalVotes * 100).toStringAsFixed(1)}%)',
                    isWinner: entry.key == winner,
                  ),
              ],
            ),
            const SizedBox(height: 24),
            // Pie chart
            ResultPieChart(
              counts: Map.fromEntries(
                counts.entries.map(
                  (e) => MapEntry(e.key, e.value as int),
                ),
              ),
              winner: winner,
              interactive: true,
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
          results: widget.results,
          winner: winner,
          methodName: _getMethodName(widget.session.method),
        );

      case VotingMethod.starVoting:
      case VotingMethod.rangeVoting:
      case VotingMethod.majorityJudgment:
      case VotingMethod.quadraticVoting:
      case VotingMethod.cumulativeVoting:
      case VotingMethod.weightVoting:
        // Use the specialized score visualization for score-based methods
        return ScoreResultsDisplay(
          results: widget.results,
          winner: winner,
          methodName: _getMethodName(widget.session.method),
        );
    }
  }

  Widget _buildDetailedResults(String? winner, ThemeData theme) {
    final counts = widget.results['counts'] as Map<String, dynamic>?;
    if (counts == null) {
      return const Center(child: Text('No detailed results available'));
    }

    final totalVotes = widget.results['totalVotes'] as int? ?? 0;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Vote Distribution',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            DataTable(
              columns: const [
                DataColumn(label: Text('Option')),
                DataColumn(label: Text('Votes'), numeric: true),
                DataColumn(label: Text('Percentage'), numeric: true),
              ],
              rows: counts.entries.map((entry) {
                final percentage = totalVotes > 0
                    ? ((entry.value as num) / totalVotes * 100)
                        .toStringAsFixed(1)
                    : '0.0';

                return DataRow(
                  selected: entry.key == winner,
                  cells: [
                    DataCell(Text(
                      entry.key,
                      style: TextStyle(
                        fontWeight: entry.key == winner
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: entry.key == winner
                            ? theme.colorScheme.primary
                            : null,
                      ),
                    )),
                    DataCell(Text(entry.value.toString())),
                    DataCell(Text('$percentage%')),
                  ],
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVotingAnalytics(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          elevation: 4,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Participation Statistics',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        'Total Votes',
                        '${widget.results['totalVotes'] ?? 0}',
                        Icons.how_to_vote,
                        theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildStatCard(
                        'Delegated Votes',
                        '${_allVotes.where((v) => v['isDelegated'] == true).length}',
                        Icons.people,
                        theme.colorScheme.secondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Card(
          elevation: 4,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Method Comparison',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'This shows how the same votes would perform under different voting methods:',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 400,
                  child: ComparisonChartWidget(
                    votes: _allVotes,
                    currentMethod: widget.session.method,
                    options: widget.session.options,
                    proposalId: widget.proposal.id,
                    delegationService: widget.delegationService,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
      String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
