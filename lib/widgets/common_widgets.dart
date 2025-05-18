import 'package:flutter/material.dart';
import '../models/data_models.dart';

/// A custom button with a consistent style across the app
class CustomButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isPrimary;
  final bool isLoading;
  final IconData? icon;
  final double height;

  const CustomButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isPrimary = true,
    this.isLoading = false,
    this.icon,
    this.height = 54,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: height,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor:
              isPrimary ? theme.colorScheme.primary : theme.colorScheme.surface,
          foregroundColor: isPrimary
              ? theme.colorScheme.onPrimary
              : theme.colorScheme.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: isPrimary
                ? BorderSide.none
                : BorderSide(color: theme.colorScheme.primary),
          ),
          elevation: isPrimary ? 2 : 0,
        ),
        child: isLoading
            ? SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: isPrimary
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.primary,
                ),
              )
            : icon != null
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon),
                      const SizedBox(width: 8),
                      Text(text),
                    ],
                  )
                : Text(text),
      ),
    );
  }
}

/// A status badge for proposals
class ProposalStatusBadge extends StatelessWidget {
  final ProposalStatus status;

  const ProposalStatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _getStatusColor(),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.toString().split('.').last,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  Color _getStatusColor() {
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
}

/// A user avatar with initials
class UserAvatar extends StatelessWidget {
  final String name;
  final UserRole? role;
  final double size;

  const UserAvatar({
    super.key,
    required this.name,
    this.role,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initials = name.isNotEmpty
        ? name
            .split(' ')
            .map((word) => word.isEmpty ? '' : word[0].toUpperCase())
            .join('')
            .substring(0, name.split(' ').length > 1 ? 2 : 1)
        : '?';

    final color =
        role != null ? _getRoleColor(role!) : theme.colorScheme.primary;

    return CircleAvatar(
      radius: size / 2,
      backgroundColor: color,
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: size / 3,
        ),
      ),
    );
  }

  Color _getRoleColor(UserRole role) {
    switch (role) {
      case UserRole.admin:
        return Colors.red;
      case UserRole.moderator:
        return Colors.purple;
      case UserRole.proposer:
        return Colors.green;
      case UserRole.user:
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }
}

/// A card for displaying a proposal summary
class ProposalCard extends StatelessWidget {
  final ProposalModel proposal;
  final VoidCallback onTap;

  const ProposalCard({
    super.key,
    required this.proposal,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
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
                          fontWeight: FontWeight.bold, fontSize: 18),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ProposalStatusBadge(status: proposal.status),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                proposal.content,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: theme.colorScheme.onSurface.withOpacity(0.7)),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.people_outline,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${proposal.supporters.length} supporters',
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${proposal.createdAt.day}/${proposal.createdAt.month}/${proposal.createdAt.year}',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A rich text editor for proposal content
class ContentEditor extends StatelessWidget {
  final TextEditingController controller;
  final String? labelText;
  final String? hintText;
  final int maxLines;
  final bool autofocus;
  final FormFieldValidator<String>? validator;

  const ContentEditor({
    super.key,
    required this.controller,
    this.labelText,
    this.hintText,
    this.maxLines = 10,
    this.autofocus = false,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      autofocus: autofocus,
      validator: validator,
      decoration: InputDecoration(
        labelText: labelText,
        hintText: hintText,
        alignLabelWithHint: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: theme.colorScheme.surface,
        contentPadding: const EdgeInsets.all(16),
      ),
      style: theme.textTheme.bodyLarge,
    );
  }
}

/// A comment display widget
class CommentTile extends StatelessWidget {
  final String authorName;
  final UserRole? authorRole;
  final String content;
  final DateTime timestamp;

  const CommentTile({
    super.key,
    required this.authorName,
    this.authorRole,
    required this.content,
    required this.timestamp,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                UserAvatar(name: authorName, role: authorRole, size: 32),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      authorName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${timestamp.day}/${timestamp.month}/${timestamp.year} at ${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(content),
          ],
        ),
      ),
    );
  }
}

/// A role badge
class RoleBadge extends StatelessWidget {
  final UserRole role;

  const RoleBadge({super.key, required this.role});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: _getRoleColor(role),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        role.toString().split('.').last,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Color _getRoleColor(UserRole role) {
    switch (role) {
      case UserRole.admin:
        return Colors.red;
      case UserRole.moderator:
        return Colors.purple;
      case UserRole.proposer:
        return Colors.green;
      case UserRole.user:
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }
}

/// A voting method badge
class VotingMethodBadge extends StatelessWidget {
  final VotingMethod method;

  const VotingMethodBadge({super.key, required this.method});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.tertiary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _getMethodName(method),
        style: TextStyle(
          color: Theme.of(context).colorScheme.onTertiary,
          fontSize: 12,
          fontWeight: FontWeight.bold,
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
      default:
        return method.toString().split('.').last;
    }
  }
}
