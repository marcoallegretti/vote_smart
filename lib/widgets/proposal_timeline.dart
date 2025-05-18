import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/data_models.dart';
import '../services/proposal_lifecycle_service.dart';

class ProposalTimeline extends StatelessWidget {
  final ProposalModel proposal;
  final double height;
  final double padding;

  const ProposalTimeline({
    super.key,
    required this.proposal,
    this.height = 100,
    this.padding = 16.0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final lifecycleService = Provider.of<ProposalLifecycleService>(context);

    return FutureBuilder<double>(
      future: lifecycleService.getPhaseProgress(proposal.id),
      builder: (context, snapshot) {
        final progress = snapshot.data ?? 0.0;

        return Padding(
          padding: EdgeInsets.all(padding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _getPhaseIcon(proposal.status),
                    color: _getPhaseColor(colorScheme, proposal.status),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _getPhaseName(proposal.status),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: _getPhaseColor(colorScheme, proposal.status),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (proposal.status != ProposalStatus.closed &&
                      proposal.status != ProposalStatus.draft)
                    FutureBuilder<Duration>(
                      future:
                          lifecycleService.getRemainingPhaseTime(proposal.id),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) return const SizedBox();
                        final remaining = snapshot.data!;
                        return Text(
                          _formatDuration(remaining),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: _getTimeColor(colorScheme, remaining),
                          ),
                        );
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: height,
                child: Stack(
                  children: [
                    // Background track
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(height / 2),
                        ),
                      ),
                    ),
                    // Progress indicator
                    if (proposal.status != ProposalStatus.closed &&
                        proposal.status != ProposalStatus.draft)
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 0,
                        bottom: 0,
                        child: FractionallySizedBox(
                          widthFactor: progress,
                          child: Container(
                            decoration: BoxDecoration(
                              color:
                                  _getPhaseColor(colorScheme, proposal.status),
                              borderRadius: BorderRadius.circular(height / 2),
                            ),
                          ),
                        ),
                      ),
                    // Phase markers
                    ..._buildPhaseMarkers(colorScheme, proposal.status),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Draft',
                      style: _getPhaseTextStyle(theme, colorScheme,
                          ProposalStatus.draft, proposal.status)),
                  Text('Discussion',
                      style: _getPhaseTextStyle(theme, colorScheme,
                          ProposalStatus.discussion, proposal.status)),
                  Text('Support',
                      style: _getPhaseTextStyle(theme, colorScheme,
                          ProposalStatus.support, proposal.status)),
                  Text('Frozen',
                      style: _getPhaseTextStyle(theme, colorScheme,
                          ProposalStatus.frozen, proposal.status)),
                  Text('Voting',
                      style: _getPhaseTextStyle(theme, colorScheme,
                          ProposalStatus.voting, proposal.status)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildPhaseMarkers(
      ColorScheme colorScheme, ProposalStatus currentStatus) {
    final phases = [
      ProposalStatus.draft,
      ProposalStatus.discussion,
      ProposalStatus.support,
      ProposalStatus.frozen,
      ProposalStatus.voting,
    ];

    return phases.map((phase) {
      final index = phases.indexOf(phase);
      final position = index / (phases.length - 1);

      return Positioned(
        left: position * 100 - 4,
        top: height / 2 - 4,
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: _getMarkerColor(colorScheme, phase, currentStatus),
            shape: BoxShape.circle,
            border: Border.all(
              color: colorScheme.surface,
              width: 2,
            ),
          ),
        ),
      );
    }).toList();
  }

  Color _getMarkerColor(ColorScheme colorScheme, ProposalStatus phase,
      ProposalStatus currentStatus) {
    if (phase == currentStatus) {
      return _getPhaseColor(colorScheme, phase);
    }
    if (phase.index < currentStatus.index) {
      return colorScheme.primary;
    }
    return colorScheme.surfaceContainerHighest;
  }

  Color _getPhaseColor(ColorScheme colorScheme, ProposalStatus status) {
    switch (status) {
      case ProposalStatus.draft:
        return colorScheme.tertiary;
      case ProposalStatus.discussion:
        return colorScheme.primary;
      case ProposalStatus.support:
        return colorScheme.secondary;
      case ProposalStatus.frozen:
        return colorScheme.surfaceTint;
      case ProposalStatus.voting:
        return colorScheme.primary;
      case ProposalStatus.closed:
        return colorScheme.outline;
    }
  }

  IconData _getPhaseIcon(ProposalStatus status) {
    switch (status) {
      case ProposalStatus.draft:
        return Icons.edit_note;
      case ProposalStatus.discussion:
        return Icons.forum;
      case ProposalStatus.support:
        return Icons.thumb_up;
      case ProposalStatus.frozen:
        return Icons.ac_unit;
      case ProposalStatus.voting:
        return Icons.how_to_vote;
      case ProposalStatus.closed:
        return Icons.check_circle;
    }
  }

  String _getPhaseName(ProposalStatus status) {
    switch (status) {
      case ProposalStatus.draft:
        return 'Draft';
      case ProposalStatus.discussion:
        return 'Discussion';
      case ProposalStatus.support:
        return 'Support';
      case ProposalStatus.frozen:
        return 'Frozen';
      case ProposalStatus.voting:
        return 'Voting';
      case ProposalStatus.closed:
        return 'Closed';
    }
  }

  TextStyle? _getPhaseTextStyle(ThemeData theme, ColorScheme colorScheme,
      ProposalStatus phase, ProposalStatus currentStatus) {
    final baseStyle = theme.textTheme.bodySmall;

    if (phase == currentStatus) {
      return baseStyle?.copyWith(
        color: _getPhaseColor(colorScheme, phase),
        fontWeight: FontWeight.bold,
      );
    }

    if (phase.index < currentStatus.index) {
      return baseStyle?.copyWith(
        color: colorScheme.primary,
      );
    }

    return baseStyle?.copyWith(
      color: colorScheme.outline,
    );
  }

  Color _getTimeColor(ColorScheme colorScheme, Duration remaining) {
    if (remaining.inDays >= 2) {
      return colorScheme.primary;
    } else if (remaining.inHours >= 12) {
      return colorScheme.secondary;
    } else {
      return colorScheme.error;
    }
  }

  String _formatDuration(Duration duration) {
    if (duration.inDays > 0) {
      return '${duration.inDays}d remaining';
    } else if (duration.inHours > 0) {
      return '${duration.inHours}h remaining';
    } else {
      return '${duration.inMinutes}m remaining';
    }
  }
}
