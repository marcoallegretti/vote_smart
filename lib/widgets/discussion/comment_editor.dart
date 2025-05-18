import 'package:flutter/material.dart';
import '../../services/comment_service.dart';

class CommentEditor extends StatefulWidget {
  final String proposalId;
  final CommentService commentService;
  final String? parentCommentId; // Null if it's a top-level comment
  final VoidCallback onCommentPosted; // To notify parent to refresh
  final bool isReply; // To adjust UI slightly for replies

  const CommentEditor({
    super.key,
    required this.proposalId,
    required this.commentService,
    this.parentCommentId,
    required this.onCommentPosted,
    this.isReply = false,
  });

  @override
  _CommentEditorState createState() => _CommentEditorState();
}

class _CommentEditorState extends State<CommentEditor> {
  final _textController = TextEditingController();
  bool _isLoading = false;
  // TODO: Get actual current user ID from auth service
  final String _currentUserId = 'current_user_id_placeholder'; 

  Future<void> _submitComment() async {
    if (_textController.text.trim().isEmpty) {
      // Optionally show a snackbar or message
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await widget.commentService.createComment(
        proposalId: widget.proposalId,
        authorId: _currentUserId, // Changed from userId to authorId
        content: _textController.text.trim(),
        parentCommentId: widget.parentCommentId,
      );
      _textController.clear();
      widget.onCommentPosted(); // Notify parent to refresh comments
    } catch (e) {
      // Handle error, e.g., show a SnackBar
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to post comment: ${e.toString()}')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: widget.isReply ? 0 : 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          TextField(
            controller: _textController,
            decoration: InputDecoration(
              hintText: widget.isReply ? 'Write a reply...' : 'Add a comment...', 
              border: const OutlineInputBorder(),
            ),
            maxLines: 3,
            textInputAction: TextInputAction.newline, // Allows multiline input
          ),
          const SizedBox(height: 8),
          _isLoading
              ? const CircularProgressIndicator()
              : ElevatedButton(
                  onPressed: _submitComment,
                  child: Text(widget.isReply ? 'Reply' : 'Post Comment'),
                ),
        ],
      ),
    );
  }
}
