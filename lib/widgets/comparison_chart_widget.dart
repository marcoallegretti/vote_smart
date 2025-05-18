import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import '../models/data_models.dart';
import '../services/voting_service.dart';
import '../services/delegation_service.dart';

/// A widget that compares results across different voting methods
class ComparisonChartWidget extends StatefulWidget {
  final List<Map<String, dynamic>> votes;
  final VotingMethod currentMethod;
  final List<String> options;
  final String proposalId;
  final DelegationService delegationService;

  const ComparisonChartWidget({
    super.key,
    required this.votes,
    required this.currentMethod,
    required this.options,
    required this.proposalId,
    required this.delegationService,
  });

  @override
  _ComparisonChartWidgetState createState() => _ComparisonChartWidgetState();
}

class _ComparisonChartWidgetState extends State<ComparisonChartWidget> {
  late List<VotingMethod> _comparisonMethods;
  Map<VotingMethod, Map<String, dynamic>> _methodResults = {};
  int _touchedIndex = -1;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeComparisonMethods();
    _loadAndCalculateResults();
  }

  void _initializeComparisonMethods() {
    _comparisonMethods = [
      VotingMethod.firstPastThePost,
      VotingMethod.approvalVoting,
      VotingMethod.majorityRunoff,
    ];

    if (!_comparisonMethods.contains(widget.currentMethod) &&
        _isImplemented(widget.currentMethod)) {
      _comparisonMethods.add(widget.currentMethod);
    }
  }

  bool _isImplemented(VotingMethod method) {
    return [
      VotingMethod.firstPastThePost,
      VotingMethod.approvalVoting,
      VotingMethod.majorityRunoff
    ].contains(method);
  }

  Future<void> _loadAndCalculateResults() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    Map<VotingMethod, Map<String, dynamic>> results = {};
    for (var method in _comparisonMethods) {
      try {
        final result = await VotingService.calculateResults(
          method,
          widget.votes,
          widget.delegationService,
          widget.proposalId,
        );
        results[method] = result;
      } catch (e) {
        print('Error calculating results for $method: $e');
        results[method] = {'error': 'Failed to calculate: $e'};
      }
    }

    if (mounted) {
      setState(() {
        _methodResults = results;
        _isLoading = false;
      });
    }
  }

  String _getMethodName(VotingMethod method) {
    switch (method) {
      case VotingMethod.firstPastThePost:
        return 'FPTP';
      case VotingMethod.approvalVoting:
        return 'Approval';
      case VotingMethod.majorityRunoff:
        return 'Majority Runoff';
      case VotingMethod.schulze:
        return 'Schulze';
      case VotingMethod.instantRunoff:
        return 'IRV';
      case VotingMethod.starVoting:
        return 'STAR';
      case VotingMethod.rangeVoting:
        return 'Range';
      case VotingMethod.majorityJudgment:
        return 'Majority Judgment';
      case VotingMethod.quadraticVoting:
        return 'Quadratic';
      case VotingMethod.condorcet:
        return 'Condorcet';
      case VotingMethod.bordaCount:
        return 'Borda';
      case VotingMethod.cumulativeVoting:
        return 'Cumulative';
      case VotingMethod.kemenyYoung:
        return 'Kemeny-Young';
      case VotingMethod.dualChoice:
        return 'Dual-Choice';
      case VotingMethod.weightVoting:
        return 'Weight';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_methodResults.values.any((res) => res.containsKey('error'))) {
      return const Center(child: Text('Error calculating comparison results.'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _buildComparisonChart(theme),
        ),
        const SizedBox(height: 16),
        _buildWinnerComparison(theme),
      ],
    );
  }

  Widget _buildComparisonChart(ThemeData theme) {
    final Set<String> allWinners = {};
    for (var results in _methodResults.values) {
      final winner = results['winner'] as String?;
      if (winner != null) {
        allWinners.add(winner);
      }
    }

    final Map<String, Color> optionColors = {};
    final List<Color> colorPalette = [
      theme.colorScheme.primary,
      theme.colorScheme.secondary,
      theme.colorScheme.tertiary,
      Colors.purple,
      Colors.orange,
      Colors.teal,
      Colors.pink,
      Colors.indigo,
      Colors.amber,
      Colors.cyan,
    ];

    for (var i = 0; i < widget.options.length; i++) {
      optionColors[widget.options[i]] = colorPalette[i % colorPalette.length];
    }

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final method = _comparisonMethods[groupIndex];
              final results = _methodResults[method]!;
              final winner = results['winner'] as String?;
              final counts = results['counts'] as Map<String, dynamic>?;

              if (winner == null || counts == null) return null;

              final totalVotes = results['totalVotes'] as int? ?? 0;
              final percentage = totalVotes > 0
                  ? ((counts[winner] as num) / totalVotes * 100)
                      .toStringAsFixed(1)
                  : '0.0';

              return BarTooltipItem(
                '${_getMethodName(method)}\n'
                'Winner: $winner\n'
                '${counts[winner]} votes ($percentage%)',
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              );
            },
          ),
          touchCallback: (FlTouchEvent event, barTouchResponse) {
            setState(() {
              if (barTouchResponse?.spot != null &&
                  event is! FlTapUpEvent &&
                  event is! FlPanEndEvent) {
                _touchedIndex = barTouchResponse!.spot!.touchedBarGroupIndex;
              } else {
                _touchedIndex = -1;
              }
            });
          },
        ),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (double value, TitleMeta meta) {
                if (value < 0 || value >= _comparisonMethods.length) {
                  return const SizedBox.shrink();
                }

                final method = _comparisonMethods[value.toInt()];
                final isCurrentMethod = method == widget.currentMethod;

                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    _getMethodName(method),
                    style: TextStyle(
                      color: isCurrentMethod ? theme.colorScheme.primary : null,
                      fontWeight:
                          isCurrentMethod ? FontWeight.bold : FontWeight.normal,
                      fontSize: 12,
                    ),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toInt().toString(),
                  style: const TextStyle(
                    fontSize: 12,
                  ),
                );
              },
            ),
          ),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(
          show: true,
          horizontalInterval: 10,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: theme.dividerColor,
              strokeWidth: 1,
              dashArray: [5, 5],
            );
          },
        ),
        borderData: FlBorderData(show: false),
        barGroups: List.generate(_comparisonMethods.length, (index) {
          final method = _comparisonMethods[index];
          final results = _methodResults[method]!;
          final counts = results['counts'] as Map<String, dynamic>?;

          if (counts == null) return BarChartGroupData(x: index);

          final sortedOptions = counts.entries.toList()
            ..sort((a, b) => (b.value as num).compareTo(a.value as num));

          final topOptions = sortedOptions.take(3).toList();

          return BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(
                toY: results['totalVotes'] as double? ?? 0,
                width: 22,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(6),
                  topRight: Radius.circular(6),
                ),
                rodStackItems: topOptions.asMap().entries.map((entry) {
                  final i = entry.key;
                  final option = entry.value.key;
                  final votes = entry.value.value as num;

                  double fromY = 0;
                  for (var j = 0; j < i; j++) {
                    fromY += topOptions[j].value as num;
                  }

                  return BarChartRodStackItem(
                    fromY,
                    fromY + votes,
                    optionColors[option] ?? theme.colorScheme.primary,
                    BorderSide.none,
                  );
                }).toList(),
                color: Colors.transparent,
                backDrawRodData: BackgroundBarChartRodData(
                  show: true,
                  toY: results['totalVotes'] as double? ?? 0,
                  color: theme.colorScheme.surface,
                ),
              ),
            ],
            showingTooltipIndicators: _touchedIndex == index ? [0] : [],
          );
        }),
      ),
    );
  }

  Widget _buildWinnerComparison(ThemeData theme) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Winner Comparison',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Table(
              columnWidths: const {
                0: FlexColumnWidth(2),
                1: FlexColumnWidth(3),
              },
              children: [
                TableRow(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        'Method',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        'Winner',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                ..._comparisonMethods.map((method) {
                  final results = _methodResults[method]!;
                  final winner = results['winner'] as String?;
                  final isCurrentMethod = method == widget.currentMethod;

                  return TableRow(
                    decoration: BoxDecoration(
                      color: isCurrentMethod
                          ? theme.colorScheme.primary.withOpacity(0.1)
                          : null,
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(
                          _getMethodName(method),
                          style: TextStyle(
                            fontWeight: isCurrentMethod
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isCurrentMethod
                                ? theme.colorScheme.primary
                                : null,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(
                          winner ?? 'No winner',
                          style: TextStyle(
                            fontWeight: isCurrentMethod
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isCurrentMethod
                                ? theme.colorScheme.primary
                                : null,
                          ),
                        ),
                      ),
                    ],
                  );
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
