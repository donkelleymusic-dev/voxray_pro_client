import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({Key? key}) : super(key: key);

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final supabase = Supabase.instance.client;
  List<dynamic> _posts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchFeedbackBoard();
  }

  // =========================================================================
  // DATA FETCHING
  // =========================================================================
  Future<void> _fetchFeedbackBoard() async {
    setState(() => _isLoading = true);
    try {
      // Fetch posts and join the votes table to get both the count and the user IDs
      final response = await supabase
          .from('feedback_posts')
          .select('*, feedback_votes(user_id)')
          .order('created_at', ascending: false);

      setState(() {
        _posts = response;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching feedback: $e');
      setState(() => _isLoading = false);
    }
  }

  // =========================================================================
  // VOTE TOGGLING
  // =========================================================================
  Future<void> _toggleVote(String postId, bool isCurrentlyVoted) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return; // Failsafe for unauthenticated users

    // Optimistic UI Update (update the screen instantly before server confirms)
    setState(() {
      final postIndex = _posts.indexWhere((p) => p['id'] == postId);
      if (postIndex != -1) {
        if (isCurrentlyVoted) {
          _posts[postIndex]['feedback_votes']
              .removeWhere((v) => v['user_id'] == userId);
        } else {
          _posts[postIndex]['feedback_votes'].add({'user_id': userId});
        }
      }
    });

    // Server-side Update
    try {
      if (isCurrentlyVoted) {
        await supabase
            .from('feedback_votes')
            .delete()
            .match({'post_id': postId, 'user_id': userId});
      } else {
        await supabase
            .from('feedback_votes')
            .insert({'post_id': postId, 'user_id': userId});
      }
    } catch (e) {
      debugPrint('Error toggling vote: $e');
      _fetchFeedbackBoard(); // Revert to server state if it fails
    }
  }

  // =========================================================================
  // ADD POST DIALOG
  // =========================================================================
  void _showAddPostDialog() {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    String selectedCategory = 'feature';
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Submit Feedback'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: selectedCategory,
                      decoration: const InputDecoration(labelText: 'Type'),
                      items: const [
                        DropdownMenuItem(value: 'feature', child: Text('Feature Request')),
                        DropdownMenuItem(value: 'bug', child: Text('Bug Report')),
                      ],
                      onChanged: (val) {
                        if (val != null) setDialogState(() => selectedCategory = val);
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: descriptionController,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (titleController.text.trim().isEmpty) return;
                          
                          setDialogState(() => isSubmitting = true);
                          try {
                            await supabase.from('feedback_posts').insert({
                              'user_id': supabase.auth.currentUser!.id,
                              'title': titleController.text.trim(),
                              'description': descriptionController.text.trim(),
                              'category': selectedCategory,
                            });
                            if (context.mounted) Navigator.pop(context);
                            _fetchFeedbackBoard(); // Refresh list
                          } catch (e) {
                            debugPrint('Error submitting post: $e');
                            setDialogState(() => isSubmitting = false);
                          }
                        },
                  child: isSubmitting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Submit'),
                ),
              ],
            );
          }
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = supabase.auth.currentUser?.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Community Feedback'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchFeedbackBoard,
          )
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddPostDialog,
        icon: const Icon(Icons.add),
        label: const Text('New Post'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _posts.isEmpty
              ? const Center(child: Text('No feedback yet. Be the first!'))
              : RefreshIndicator(
                  onRefresh: _fetchFeedbackBoard,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16.0),
                    itemCount: _posts.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final post = _posts[index];
                      final votes = post['feedback_votes'] as List<dynamic>;
                      final voteCount = votes.length;
                      final hasVoted = votes.any((v) => v['user_id'] == currentUserId);
                      final isBug = post['category'] == 'bug';

                      return Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // --- UPVOTE COLUMN ---
                              Column(
                                children: [
                                  IconButton(
                                    icon: Icon(
                                      Icons.keyboard_arrow_up_rounded,
                                      size: 32,
                                      color: hasVoted ? Colors.blueAccent : Colors.grey,
                                    ),
                                    onPressed: () => _toggleVote(post['id'], hasVoted),
                                  ),
                                  Text(
                                    '$voteCount',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: hasVoted ? Colors.blueAccent : null,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 16),
                              
                              // --- CONTENT COLUMN ---
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: isBug ? Colors.red.withOpacity(0.1) : Colors.teal.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            isBug ? 'BUG' : 'FEATURE',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: isBug ? Colors.redAccent : Colors.teal,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        if (post['status'] != 'open')
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              post['status'].toString().toUpperCase().replaceAll('_', ' '),
                                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      post['title'],
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      post['description'],
                                      style: const TextStyle(fontSize: 14, color: Colors.grey, height: 1.4),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
