import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

/// A widget that displays score-based voting results
class ScoreResultsDisplay extends StatelessWidget {
  final Map<String, dynamic> results;
  final String? winner;
  final String methodName;

  const ScoreResultsDisplay({
    super.key,
    required this.results,
    this.winner,
    required this.methodName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // Extract scores from results
    final Map<String, double> scores = {};
    if (results.containsKey('scores')) {
      final scoresData = results['scores'] as Map<String, dynamic>;
      scores.addAll(scoresData.map((key, value) => MapEntry(key, value is int ? value.toDouble() : value as double)));
    } else if (results.containsKey('ratings')) {
      final ratingsData = results['ratings'] as Map<String, dynamic>;
      scores.addAll(ratingsData.map((key, value) => MapEntry(key, value is int ? value.toDouble() : value as double)));
    } else if (results.containsKey('counts')) {
      final countsData = results['counts'] as Map<String, dynamic>;
      scores.addAll(countsData.map((key, value) => MapEntry(key, value is int ? value.toDouble() : value as double)));
    }
    
    // Sort by score
    final sortedEntries = scores.entries.toList()
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
                      Icons.score,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$methodName Scores',
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
                  
                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      border: isWinner ? Border.all(
                        color: theme.colorScheme.primary,
                        width: 2,
                      ) : null,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Row(
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
                              Text(
                                entry.value.toStringAsFixed(1),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: isWinner ? theme.colorScheme.primary : null,
                                ),
                              ),
                              if (isWinner) ...[
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.emoji_events,
                                  color: theme.colorScheme.primary,
                                  size: 20,
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildScoreBar(entry.value, sortedEntries.first.value, isWinner, theme),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        _buildRadarChart(sortedEntries, theme),
      ],
    );
  }
  
  Widget _buildScoreBar(double value, double maxValue, bool isWinner, ThemeData theme) {
    final ratio = maxValue > 0 ? value / maxValue : 0.0;
    final color = isWinner ? theme.colorScheme.primary : theme.colorScheme.secondary;
    
    return Stack(
      children: [
        Container(
          height: 12,
          width: double.infinity,
          decoration: BoxDecoration(
            color: theme.colorScheme.onSurface.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        FractionallySizedBox(
          widthFactor: ratio,
          child: Container(
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildRadarChart(List<MapEntry<String, double>> entries, ThemeData theme) {
    // Limit to top 8 entries for radar chart clarity
    final displayEntries = entries.length > 8 ? entries.sublist(0, 8) : entries;
    final maxValue = displayEntries.isNotEmpty ? displayEntries.first.value : 0.0;
    
    // Instead of the RadarChart which has compatibility issues,
    // let's use a horizontal bar chart for score visualization
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
                final entry = displayEntries[groupIndex];
                return BarTooltipItem(
                  '${entry.key}\n${entry.value.toStringAsFixed(1)} points',
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
                  if (value >= displayEntries.length || value < 0) return const Text('');
                  final name = displayEntries[value.toInt()].key;
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
                    value.toStringAsFixed(1),
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  );
                },
                reservedSize: 40,
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
          barGroups: List.generate(displayEntries.length, (index) {
            final entry = displayEntries[index];
            final isWinner = entry.key == winner;
            final color = isWinner 
                ? theme.colorScheme.primary 
                : theme.colorScheme.secondary;
                
            return BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: entry.value,
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
}
