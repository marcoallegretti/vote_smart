import 'package:flutter/material.dart';
import '../../models/comment_model.dart';
import '../../models/data_models.dart' as Dm;
import '../../services/comment_service.dart';
import 'comment_card.dart'; 
import 'comment_editor.dart'; 

class CommentSection extends StatefulWidget {
  final Dm.ProposalModel proposal;
  final CommentService commentService;
  final String currentUserId;
  final String currentUserRole; 

  const CommentSection({
    super.key,
    required this.proposal,
    required this.commentService,
    required this.currentUserId,
    required this.currentUserRole, 
  });

  @override
  _CommentSectionState createState() => _CommentSectionState();
}

class _CommentSectionState extends State<CommentSection> {
  late Future<List<CommentModel>> _commentsFuture;
  // To get current user, you'd typically use a provider or service
  // For now, let's assume a placeholder or that CommentService handles it if needed for posting.

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  void _loadComments() {
    setState(() {
      _commentsFuture = widget.commentService
          .getCommentsForProposal(widget.proposal.id, parentCommentId: null); 
    });
  }

  // void _onCommentPosted() {
  //   // Reload comments after a new one is posted
  //   _loadComments();
  // }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8.0),
      elevation: 2.0,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Discussion: ${widget.proposal.title}',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            // Add CommentEditor widget here
            CommentEditor(
              proposalId: widget.proposal.id,
              commentService: widget.commentService,
              onCommentPosted: _loadComments, 
            ),
            const SizedBox(height: 24),
            Text(
              "Comments",
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            FutureBuilder<List<CommentModel>>(
              future: _commentsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Error loading comments: ${snapshot.error}', style: TextStyle(color: Colors.red)),
                  );
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 20.0),
                      child: Text('No comments yet. Be the first to share your thoughts!', textAlign: TextAlign.center),
                    )
                  );
                }

                final comments = snapshot.data!;
                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(), 
                  itemCount: comments.length,
                  separatorBuilder: (context, index) => const Divider(height: 1, indent: 16, endIndent: 16),
                  itemBuilder: (context, index) {
                    final comment = comments[index];
                    return CommentCard(
                        comment: comment, 
                        commentService: widget.commentService, 
                        currentUserId: widget.currentUserId,
                        currentUserRole: widget.currentUserRole, 
                        onCommentUpdated: _loadComments,
                        depth: 0,
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
