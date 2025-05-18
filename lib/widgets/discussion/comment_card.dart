import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // For date formatting
import '../../models/comment_model.dart';
import '../../services/comment_service.dart';
import 'comment_editor.dart'; // For reply functionality
import 'comment_moderation_tools.dart'; // Added for moderation

class CommentCard extends StatefulWidget {
  final CommentModel comment;
  final CommentService commentService;
  final String currentUserId;
  final String currentUserRole; // Added: user role
  final VoidCallback? onCommentUpdated;
  final int depth;

  const CommentCard({
    super.key,
    required this.comment,
    required this.commentService,
    required this.currentUserId,
    required this.currentUserRole, // Added
    this.onCommentUpdated,
    this.depth = 0,
  });

  @override
  State<CommentCard> createState() => _CommentCardState();
}

class _CommentCardState extends State<CommentCard> {
  bool _showReplyEditor = false;
  late Future<List<CommentModel>> _repliesFuture;
  bool _repliesVisible = false; // To toggle visibility of replies
  bool _isEditing = false; // For inline editing
  final TextEditingController _editController = TextEditingController();

  late CommentModel _optimisticComment; // For optimistic UI

  @override
  void initState() {
    super.initState();
    _optimisticComment = widget.comment;
    _loadReplies();
  }

  void _loadReplies() {
    setState(() {
      _repliesFuture = widget.commentService.getCommentsForProposal(
        widget.comment.proposalId,
        parentCommentId: widget.comment.id,
      );
    });
  }

  String _formatTimestamp(DateTime timestamp) {
    return DateFormat('MMM d, yyyy HH:mm').format(timestamp);
  }

  void _handleUpvote() async {
    // In a real app, get current userId
    await widget.commentService.upvoteComment(widget.comment.id, 'current_user_id');
    widget.onCommentUpdated?.call();
    // TODO: Optimistic UI update
  }

  void _handleDownvote() async {
    await widget.commentService.downvoteComment(widget.comment.id, 'current_user_id');
    widget.onCommentUpdated?.call();
    // TODO: Optimistic UI update
  }

  void _handleDelete() async {
    // Add confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Comment?'),
          content: const Text('Are you sure you want to delete this comment? This action cannot be undone.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      await widget.commentService.deleteComment(widget.comment.id);
      widget.onCommentUpdated?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.only(left: widget.depth * 16.0, top: 8.0, right: 8.0, bottom: 8.0),
      elevation: 1.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
      child: Container(
        decoration: BoxDecoration(
          color: _optimisticComment.isDeleted
              ? Colors.grey.shade300
              : (widget.comment.isModerated ? Colors.grey.shade100 : null), // Gray background if deleted or moderated
          border: widget.depth > 0
              ? Border(
                  left: BorderSide(
                    color: Colors.blue.shade200,
                    width: 3.0,
                  ),
                )
              : null,
        ),
        padding: const EdgeInsets.all(16.0),
        child: _optimisticComment.isDeleted
            ? Row(
                children: [
                  const Icon(Icons.delete_forever, color: Colors.grey, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'This comment has been deleted.',
                      style: TextStyle(color: Colors.grey.shade700, fontStyle: FontStyle.italic),
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
            if (widget.comment.isModerated)
              Row(
                children: [
                  const Icon(Icons.warning, color: Colors.orange, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Comment hidden by moderation: ${widget.comment.moderationReason ?? "No reason provided."}',
                      style: const TextStyle(color: Colors.orange, fontStyle: FontStyle.italic),
                    ),
                  ),
                ],
              ),
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  child: Text(widget.comment.authorId.isNotEmpty ? widget.comment.authorId[0].toUpperCase() : "A"),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.comment.authorId, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      Text(
                        _formatTimestamp(widget.comment.createdAt) + (widget.comment.updatedAt != null ? ' (edited)' : ''),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                // Show menu if user is author or moderator/admin
                if (!_optimisticComment.isDeleted && (widget.currentUserId == widget.comment.authorId || widget.currentUserRole == 'moderator' || widget.currentUserRole == 'admin'))
                  PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'edit') {
                        setState(() {
                          _isEditing = true;
                          _editController.text = _optimisticComment.content;
                        });
                      } else if (value == 'delete') {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Delete Comment'),
                            content: const Text('Are you sure you want to delete this comment?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(true),
                                child: const Text('Delete', style: TextStyle(color: Colors.red)),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true) {
                          // Optimistic UI: mark as deleted
                          final oldComment = _optimisticComment;
                          setState(() {
                            _optimisticComment = _optimisticComment.copyWith(isDeleted: true, deletedAt: DateTime.now());
                          });
                          try {
                            await widget.commentService.deleteComment(widget.comment.id);
                            if (widget.onCommentUpdated != null) widget.onCommentUpdated!();
                          } catch (e) {
                            // Revert on error
                            setState(() {
                              _optimisticComment = oldComment;
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Failed to delete comment. Please try again.')),
                            );
                          }
                        }
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      const PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'delete') {
                      _handleDelete();
                    }
                    // TODO: Add edit functionality
                  },
                  itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                    // TODO: Conditionally show based on ownership/permissions
                    const PopupMenuItem<String>(
                      value: 'edit',
                      child: Text('Edit'),
                    ),
                    const PopupMenuItem<String>(
                      value: 'delete',
                      child: Text('Delete'),
                    ),
                  ],
                  icon: const Icon(Icons.more_vert, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_isEditing)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _editController,
                    autofocus: true,
                    minLines: 1,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Edit Comment',
                    ),
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () async {
                          // Optimistic UI: update local state
                          final oldContent = _optimisticComment.content;
                          setState(() {
                            _optimisticComment = _optimisticComment.copyWith(content: _editController.text.trim());
                            _isEditing = false;
                          });
                          try {
                            await widget.commentService.updateComment(widget.comment.id, _editController.text.trim());
                            if (widget.onCommentUpdated != null) widget.onCommentUpdated!();
                          } catch (e) {
                            // Revert on error
                            setState(() {
                              _optimisticComment = _optimisticComment.copyWith(content: oldContent);
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Failed to update comment. Please try again.')),
                            );
                          }
                        },
                        child: const Text('Save'),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _isEditing = false;
                          });
                        },
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ],
              )
            else
              Text(_optimisticComment.content, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(icon: const Icon(Icons.thumb_up_alt_outlined, size: 18), onPressed: _handleUpvote),
                Text('${widget.comment.upvotes}'),
                const SizedBox(width: 12),
                IconButton(icon: const Icon(Icons.thumb_down_alt_outlined, size: 18), onPressed: _handleDownvote),
                Text('${widget.comment.downvotes}'),
                const Spacer(),
                CommentModerationTools(
                  comment: widget.comment,
                  commentService: widget.commentService,
                  currentUserId: widget.currentUserId,
                  currentUserRole: widget.currentUserRole, // Pass user role
                  onModerationChanged: () {
                    setState(() {});
                  },
                ),
                TextButton.icon(
                  icon: Icon(_repliesVisible ? Icons.chat_bubble : Icons.chat_bubble_outline, size: 18),
                  label: Text(_repliesVisible ? 'Hide Replies' : 'Show Replies (${widget.comment.score})'), // Placeholder for reply count
                  onPressed: () {
                    setState(() {
                      _repliesVisible = !_repliesVisible;
                      if (_repliesVisible) {
                        _loadReplies(); // Load replies when made visible
                      }
                    });
                  },
                ),
                TextButton.icon(
                  icon: const Icon(Icons.reply, size: 18),
                  label: const Text('Reply'),
                  onPressed: () {
                    setState(() {
                      _showReplyEditor = !_showReplyEditor;
                    });
                  },
                ),
              ],
            ),
            if (_showReplyEditor)
              Padding(
                padding: const EdgeInsets.only(top: 8.0, left: 16.0, right: 16.0), // Indent reply editor slightly
                child: CommentEditor(
                  proposalId: widget.comment.proposalId,
                  commentService: widget.commentService,
                  parentCommentId: widget.comment.id,
                  onCommentPosted: () {
                    setState(() { 
                      _showReplyEditor = false; 
                      _repliesVisible = true; // Show replies section after posting
                    });
                    _loadReplies(); // Refresh the replies list for this comment
                    widget.onCommentUpdated?.call(); // Also call parent's update if needed (e.g. total comment count)
                  },
                  isReply: true,
                ),
              ),
            if (_repliesVisible)
              FutureBuilder<List<CommentModel>>(
                future: _repliesFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2.0)),
                    );
                  }
                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text('Error loading replies: ${snapshot.error}', style: const TextStyle(color: Colors.red)),
                    );
                  }
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const SizedBox.shrink(); // No replies to show
                  }

                  final replies = snapshot.data!;
                  return Padding(
                    padding: const EdgeInsets.only(left: 16.0), // Indent replies further
                    child: ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: replies.length,
                      itemBuilder: (context, index) {
                        final reply = replies[index];
                        return CommentCard(
                          comment: reply,
                          commentService: widget.commentService,
                          currentUserId: widget.currentUserId,
                          currentUserRole: widget.currentUserRole, // Pass down currentUserRole
                          onCommentUpdated: _loadReplies,
                          depth: widget.depth + 1,
                        );
                      },
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
