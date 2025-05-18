import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

/// A widget that displays ranking-based voting results
class RankingResultsDisplay extends StatelessWidget {
  final Map<String, dynamic> results;
  final String? winner;
  final String methodName;

  const RankingResultsDisplay({
    super.key,
    required this.results,
    this.winner,
    required this.methodName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // Extract rankings from results
    final Map<String, int> rankings = {};
    if (results.containsKey('rankings')) {
      final rankingsData = results['rankings'] as Map<String, dynamic>;
      rankings.addAll(rankingsData.map((key, value) => MapEntry(key, value as int)));
    } else if (results.containsKey('scores')) {
      final scoresData = results['scores'] as Map<String, dynamic>;
      rankings.addAll(scoresData.map((key, value) => MapEntry(key, value as int)));
    } else if (results.containsKey('counts')) {
      final countsData = results['counts'] as Map<String, dynamic>;
      rankings.addAll(countsData.map((key, value) => MapEntry(key, value as int)));
    }
    
    // Sort by ranking
    final sortedEntries = rankings.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.leaderboard,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$methodName Rankings',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                ...List.generate(sortedEntries.length, (index) {
                  final entry = sortedEntries[index];
                  final isWinner = entry.key == winner;
                  final rankColor = _getRankColor(index, theme);
                  
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: rankColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: isWinner ? Border.all(
                        color: theme.colorScheme.primary,
                        width: 2,
                      ) : null,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: rankColor,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                color: theme.colorScheme.onPrimary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      entry.key,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: isWinner ? theme.colorScheme.primary : null,
                                      ),
                                    ),
                                  ),
                                  if (isWinner)
                                    Icon(
                                      Icons.emoji_events,
                                      color: theme.colorScheme.primary,
                                      size: 20,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Score: ${entry.value}',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        _buildRankingChart(sortedEntries, theme),
      ],
    );
  }
  
  Widget _buildRankingChart(List<MapEntry<String, int>> entries, ThemeData theme) {
    // Calculate max value for scaling
    final maxValue = entries.isNotEmpty ? entries.first.value.toDouble() : 0.0;
    
    return SizedBox(
      height: 300,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxValue * 1.2, // Add some space at the top
          barTouchData: BarTouchData(
            enabled: true,
            touchCallback: (FlTouchEvent event, BarTouchResponse? response) {},
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final entry = entries[groupIndex];
                return BarTooltipItem(
                  '${entry.key}\n${entry.value} points',
                  TextStyle(color: theme.colorScheme.onSurface),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  if (value >= entries.length || value < 0) return const Text('');
                  final name = entries[value.toInt()].key;
                  // Truncate long names
                  final displayName = name.length > 10 ? '${name.substring(0, 8)}...' : name;
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      displayName,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withOpacity(0.7),
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  );
                },
                reservedSize: 30,
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  return Text(
                    value.toInt().toString(),
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  );
                },
                reservedSize: 30,
              ),
            ),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            show: true,
            horizontalInterval: maxValue / 5,
            getDrawingHorizontalLine: (value) => FlLine(
              color: theme.colorScheme.onSurface.withOpacity(0.1),
              strokeWidth: 1,
            ),
          ),
          barGroups: List.generate(entries.length, (index) {
            final entry = entries[index];
            final isWinner = entry.key == winner;
            final color = isWinner 
                ? theme.colorScheme.primary 
                : _getRankColor(index, theme);
                
            return BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: entry.value.toDouble(),
                  color: color,
                  width: 20,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(6),
                    topRight: Radius.circular(6),
                  ),
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: maxValue,
                    color: theme.colorScheme.onSurface.withOpacity(0.05),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
  
  Color _getRankColor(int rank, ThemeData theme) {
    switch (rank) {
      case 0:
        return Colors.amber; // Gold for 1st place
      case 1:
        return Colors.blueGrey.shade400; // Silver for 2nd place
      case 2:
        return Colors.brown.shade300; // Bronze for 3rd place
      default:
        return theme.colorScheme.tertiary.withOpacity(0.7);
    }
  }
}
