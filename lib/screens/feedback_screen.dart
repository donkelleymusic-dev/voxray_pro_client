Future<void> toggleVote(String postId, String userId, bool isCurrentlyVoted) async {
  try {
    if (isCurrentlyVoted) {
      // Remove vote
      await supabase
          .from('feedback_votes')
          .delete()
          .match({'post_id': postId, 'user_id': userId});
    } else {
      // Add vote
      await supabase
          .from('feedback_votes')
          .insert({'post_id': postId, 'user_id': userId});
    }
  } catch (e) {
    print('Error toggling vote: $e');
  }
}

Future<List<dynamic>> fetchFeedbackBoard() async {
  final response = await supabase
      .from('feedback_posts')
      .select('*, feedback_votes(count)') // Joins the tables and returns the total vote count
      .order('created_at', ascending: false);
      
  return response;
}
