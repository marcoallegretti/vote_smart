import '../models/comment_model.dart';

class CommentService {
  // In-memory store for comments for now, will be replaced with a database later
  final List<CommentModel> _comments = [];
  int _nextCommentId = 1;
  final Map<String, int> _commentDepths = {}; // Helper to track depth for replies

  // Create a new comment
  Future<CommentModel> createComment({
    required String proposalId,
    required String authorId, // Changed from userId
    required String content,
    String? parentCommentId,
  }) async {
    int depth = 0;
    if (parentCommentId != null) {
      depth = (_commentDepths[parentCommentId] ?? -1) + 1; // Parent depth + 1
    }

    final newComment = CommentModel(
      id: _nextCommentId.toString(),
      proposalId: proposalId,
      authorId: authorId, // Use authorId
      content: content,
      createdAt: DateTime.now(), // Use createdAt
      parentCommentId: parentCommentId,
      depth: depth, // Provide depth
      upvotedBy: [], // Initialize as empty list
      downvotedBy: [], // Initialize as empty list
      // author: UserModel(id: userId, name: 'User $userId', email: ''), // Removed placeholder UserModel
    );
    _comments.add(newComment);
    _commentDepths[newComment.id] = depth; // Store depth of new comment
    _nextCommentId++;
    // TODO: Add notification logic
    return newComment;
  }

  // Get comments for a proposal (optionally filtered by parentCommentId for threading)
  Future<List<CommentModel>> getCommentsForProposal(
    String proposalId, {
    String? parentCommentId, // if null, get top-level comments
  }) async {
    return _comments
        .where((comment) =>
            comment.proposalId == proposalId &&
            comment.parentCommentId == parentCommentId)
        .toList()..sort((a,b) => a.createdAt.compareTo(b.createdAt)); // sort by creation time
  }

  // Update a comment
  Future<CommentModel?> updateComment(
      String commentId, String newContent) async {
    final index = _comments.indexWhere((comment) => comment.id == commentId);
    if (index != -1) {
      _comments[index] = _comments[index].copyWith(
        content: newContent, 
        updatedAt: DateTime.now(), 
        isEdited: true
      );
      // TODO: Add notification logic for edits if needed
      return _comments[index];
    }
    return null;
  }

  // Delete a comment
  Future<void> deleteComment(String commentId) async {
    final index = _comments.indexWhere((comment) => comment.id == commentId);
    if (index != -1) {
      _comments[index] = _comments[index].copyWith(
        isDeleted: true,
        deletedAt: DateTime.now(),
      );
    }
    List<String> idsToDelete = [commentId];
    List<String> children = _comments.where((c) => c.parentCommentId == commentId).map((c) => c.id).toList();
    
    // Basic recursive delete for children, could be optimized
    while(children.isNotEmpty) {
        idsToDelete.addAll(children);
        List<String> nextChildren = [];
        for (var childId in children) {
            nextChildren.addAll(_comments.where((c) => c.parentCommentId == childId).map((c) => c.id).toList());
        }
        children = nextChildren;
    }

    _comments.removeWhere((comment) => idsToDelete.contains(comment.id));
    for (var id in idsToDelete) {
      _commentDepths.remove(id);
    }

    // TODO: Add notification logic for deletions if needed
    // No return value for Future<void>
  }

  // Upvote a comment
  Future<CommentModel?> upvoteComment(String commentId, String userId) async {
    final index = _comments.indexWhere((comment) => comment.id == commentId);
    if (index != -1) {
      CommentModel comment = _comments[index];
      List<String> upvotedBy = List.from(comment.upvotedBy);
      List<String> downvotedBy = List.from(comment.downvotedBy);

      if (upvotedBy.contains(userId)) {
        upvotedBy.remove(userId); // User un-upvotes
      } else {
        upvotedBy.add(userId); // User upvotes
        downvotedBy.remove(userId); // Remove from downvotes if present
      }
      
      _comments[index] = comment.copyWith(upvotedBy: upvotedBy, downvotedBy: downvotedBy);
      // TODO: Add notification logic for upvotes
      return _comments[index];
    }
    return null;
  }

  // Downvote a comment
  Future<CommentModel?> downvoteComment(String commentId, String userId) async {
    final index = _comments.indexWhere((comment) => comment.id == commentId);
    if (index != -1) {
      CommentModel comment = _comments[index];
      List<String> upvotedBy = List.from(comment.upvotedBy);
      List<String> downvotedBy = List.from(comment.downvotedBy);

      if (downvotedBy.contains(userId)) {
        downvotedBy.remove(userId); // User un-downvotes
      } else {
        downvotedBy.add(userId); // User downvotes
        upvotedBy.remove(userId); // Remove from upvotes if present
      }

      _comments[index] = comment.copyWith(downvotedBy: downvotedBy, upvotedBy: upvotedBy);
      return _comments[index];
    }
    return null;
  }

  // Moderate a comment
  Future<CommentModel?> moderateComment(String commentId, String moderatorId, String reason) async {
    final index = _comments.indexWhere((comment) => comment.id == commentId);
    if (index != -1) {
      _comments[index] = _comments[index].copyWith(
        isModerated: true,
        moderatedBy: moderatorId,
        moderationReason: reason,
        moderatedAt: DateTime.now(),
      );
      // TODO: Add notification logic for moderation
      return _comments[index];
    }
    return null;
  }

  // Unmoderate a comment
  Future<CommentModel?> unmoderateComment(String commentId) async {
    final index = _comments.indexWhere((comment) => comment.id == commentId);
    if (index != -1) {
      _comments[index] = _comments[index].copyWith(
        isModerated: false,
        setModeratedByToNull: true,
        setModerationReasonToNull: true,
        setModeratedAtToNull: true,
      );
      // TODO: Add notification logic for unmoderation
      return _comments[index];
    }
    return null;
  }

  // TODO: Add methods for fetching user-specific comments, comment history, etc.
}
