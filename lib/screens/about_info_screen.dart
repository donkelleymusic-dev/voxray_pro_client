class AboutInfoScreen extends StatelessWidget {
  final String contentKey; // Pass 'about_me', 'faq', or 'tutorial'
  final String pageTitle;

  const AboutInfoScreen({Key? key, required this.contentKey, required this.pageTitle}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(pageTitle)),
      body: FutureBuilder<String>(
        future: BackendService.fetchAppContent(contentKey),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Text(
              snapshot.data ?? 'No information available.',
              style: const TextStyle(fontSize: 16, height: 1.5),
            ),
          );
        },
      ),
    );
  }
}
