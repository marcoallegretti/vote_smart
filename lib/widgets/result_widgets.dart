import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math' as math;

/// A widget that displays the winner of a vote
class ResultWinnerCard extends StatelessWidget {
  final String winner;
  final String? subtitle;

  const ResultWinnerCard({
    super.key,
    required this.winner,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.emoji_events,
              color: Theme.of(context).colorScheme.onPrimary,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Winner',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  winner,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.7),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A bar that shows a result value
class ResultBar extends StatelessWidget {
  final String option;
  final num value;
  final num maxValue;
  final String label;
  final bool isWinner;
  final bool highlighted;

  const ResultBar({
    super.key,
    required this.option,
    required this.value,
    required this.maxValue,
    required this.label,
    this.isWinner = false,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backgroundColor = highlighted
        ? theme.colorScheme.secondary.withOpacity(0.1)
        : theme.colorScheme.surface;
    final progressColor = isWinner
        ? theme.colorScheme.primary
        : highlighted
            ? theme.colorScheme.secondary
            : theme.colorScheme.tertiary;

    final ratio = maxValue == 0 ? 0.0 : value / maxValue;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  option,
                  style: TextStyle(
                    fontWeight: isWinner || highlighted
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: isWinner
                        ? theme.colorScheme.primary
                        : highlighted
                            ? theme.colorScheme.secondary
                            : null,
                  ),
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                  color: isWinner
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Stack(
            children: [
              Container(
                height: 20,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  return Container(
                    height: 20,
                    width: constraints.maxWidth * ratio,
                    decoration: BoxDecoration(
                      color: progressColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  );
                },
              ),
              if (isWinner) ...[
                Positioned(
                  right: 8,
                  top: 0,
                  bottom: 0,
                  child: Icon(
                    Icons.check_circle,
                    color: theme.colorScheme.onPrimary,
                    size: 16,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// A pie chart that shows vote distribution with enhanced visuals and interactivity
class ResultPieChart extends StatefulWidget {
  final Map<String, int> counts;
  final String? winner;
  final bool interactive;

  const ResultPieChart({
    super.key,
    required this.counts,
    this.winner,
    this.interactive = true,
  });

  @override
  State<ResultPieChart> createState() => _ResultPieChartState();
}

class _ResultPieChartState extends State<ResultPieChart> {
  int? touchedIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total =
        widget.counts.values.fold<int>(0, (sum, count) => sum + count);

    // Generate a list of colors for the pie sections
    final List<Color> sectionColors = [
      theme.colorScheme.primary,
      theme.colorScheme.secondary,
      theme.colorScheme.tertiary,
      Colors.amber,
      Colors.teal,
      Colors.purple,
      Colors.orange,
      Colors.indigo,
      Colors.pink,
      Colors.lime,
    ];

    // Create the sections for the pie chart
    final entries = widget.counts.entries.toList();
    final sections = List.generate(entries.length, (i) {
      final entry = entries[i];
      final isWinner = entry.key == widget.winner;
      final isTouched = i == touchedIndex;
      final double fontSize = isTouched ? 18 : 14;
      final double radius =
          isWinner ? (isTouched ? 70 : 60) : (isTouched ? 60 : 50);

      // Use a color from our palette or generate one if we run out
      final color = i < sectionColors.length
          ? sectionColors[i]
          : Color((math.Random().nextDouble() * 0xFFFFFF).toInt())
              .withOpacity(1.0);

      return PieChartSectionData(
        value: entry.value.toDouble(),
        title: '${(entry.value / total * 100).toStringAsFixed(1)}%',
        color: isWinner ? theme.colorScheme.primary : color,
        radius: radius,
        titleStyle: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onPrimary,
          shadows: [
            Shadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 2,
              offset: const Offset(1, 1),
            ),
          ],
        ),
        badgeWidget: isWinner
            ? _Badge(
                size: 40,
                borderColor: theme.colorScheme.onPrimary,
              )
            : null,
        badgePositionPercentageOffset: 1.1,
      );
    });

    return Column(
      children: [
        SizedBox(
          height: 300,
          child: PieChart(
            PieChartData(
              sections: sections,
              centerSpaceRadius: 30,
              sectionsSpace: 2,
              pieTouchData: widget.interactive
                  ? PieTouchData(
                      touchCallback: (FlTouchEvent event, pieTouchResponse) {
                        setState(() {
                          if (!event.isInterestedForInteractions ||
                              pieTouchResponse == null ||
                              pieTouchResponse.touchedSection == null) {
                            touchedIndex = -1;
                            return;
                          }
                          touchedIndex = pieTouchResponse
                              .touchedSection!.touchedSectionIndex;
                        });
                      },
                    )
                  : null,
              centerSpaceColor: theme.colorScheme.surface,
            ),
          ),
        ),
        const SizedBox(height: 24),
        // Enhanced legend with vote counts and percentages
        Wrap(
          spacing: 16,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: List.generate(entries.length, (i) {
            final entry = entries[i];
            final isWinner = entry.key == widget.winner;
            final color = i < sectionColors.length
                ? (isWinner ? theme.colorScheme.primary : sectionColors[i])
                : Color((math.Random().nextDouble() * 0xFFFFFF).toInt())
                    .withOpacity(1.0);

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: color.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.key,
                        style: TextStyle(
                          fontWeight:
                              isWinner ? FontWeight.bold : FontWeight.normal,
                          color: isWinner ? theme.colorScheme.primary : null,
                        ),
                      ),
                      Text(
                        '${entry.value} votes (${(entry.value / total * 100).toStringAsFixed(1)}%)',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                  if (isWinner) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.emoji_events,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                ],
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  final double size;
  final Color borderColor;

  const _Badge({
    required this.size,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: PieChart.defaultDuration,
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(
          color: borderColor,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.5),
            offset: const Offset(3, 3),
            blurRadius: 3,
          ),
        ],
      ),
      child: const Center(
        child: Icon(
          Icons.emoji_events,
          color: Colors.amber,
          size: 16,
        ),
      ),
    );
  }
}

/// A summary card that shows vote statistics with enhanced visuals
class ResultSummaryCard extends StatelessWidget {
  final int totalVotes;
  final bool majorityAchieved;
  final bool runoffNeeded;
  final List<String>? runoffCandidates;

  const ResultSummaryCard({
    super.key,
    required this.totalVotes,
    this.majorityAchieved = false,
    this.runoffNeeded = false,
    this.runoffCandidates,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 2,
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outline.withOpacity(0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.summarize,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Vote Summary',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            _buildSummaryItem(
              context,
              'Total Votes',
              '$totalVotes',
              Icons.how_to_vote,
            ),
            if (majorityAchieved)
              _buildSummaryItem(
                context,
                'Majority Achieved',
                'Yes',
                Icons.check_circle,
                color: Colors.green,
              )
            else
              _buildSummaryItem(
                context,
                'Majority Achieved',
                'No',
                Icons.cancel,
                color: Colors.red,
              ),
            if (runoffNeeded) ...[
              _buildSummaryItem(
                context,
                'Runoff Needed',
                'Yes',
                Icons.repeat,
                color: Colors.orange,
              ),
              if (runoffCandidates != null && runoffCandidates!.isNotEmpty)
                _buildSummaryItem(
                  context,
                  'Runoff Candidates',
                  runoffCandidates!.join(', '),
                  Icons.people,
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(
      BuildContext context, String label, String value, IconData icon,
      {Color? color}) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12.0),
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: (color ?? theme.colorScheme.primary).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (color ?? theme.colorScheme.primary).withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: color ?? theme.colorScheme.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
                Text(
                  value,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
