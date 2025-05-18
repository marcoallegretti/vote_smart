import 'package:flutter/material.dart';
import '../../models/comment_model.dart';
import '../../services/comment_service.dart';

class CommentModerationTools extends StatelessWidget {
  final CommentModel comment;
  final CommentService commentService;
  final String currentUserId;
  final String currentUserRole; // Added: user role
  final VoidCallback onModerationChanged;

  const CommentModerationTools({
    super.key,
    required this.comment,
    required this.commentService,
    required this.currentUserId,
    required this.currentUserRole, // Added
    required this.onModerationChanged,
  });

  void _showModerationReasonDialog(BuildContext context) {
    final TextEditingController reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Moderate Comment'),
          content: TextField(
            controller: reasonController,
            decoration: const InputDecoration(hintText: 'Reason for moderation'),
            autofocus: true,
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('Moderate'),
              onPressed: () async {
                if (reasonController.text.trim().isNotEmpty) {
                  await commentService.moderateComment(
                    comment.id,
                    currentUserId, // Pass the moderator's ID
                    reasonController.text.trim(),
                  );
                  onModerationChanged();
                  Navigator.of(context).pop();
                } else {
                  // Show some error or prompt to enter a reason
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a reason for moderation.')),
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Only moderators/admins can see moderation tools
    if (currentUserRole != 'moderator' && currentUserRole != 'admin') {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!comment.isModerated)
          IconButton(
            icon: const Icon(Icons.security, color: Colors.orange, size: 18),
            tooltip: 'Moderate Comment',
            onPressed: () => _showModerationReasonDialog(context),
          ),
        if (comment.isModerated)
          IconButton(
            icon: const Icon(Icons.security_update_good, color: Colors.green, size: 18),
            tooltip: 'Unmoderate Comment',
            onPressed: () async {
              await commentService.unmoderateComment(comment.id);
              onModerationChanged();
            },
          ),
        // Potentially add other tools like 'Delete by Admin' here
      ],
    );
  }
}
