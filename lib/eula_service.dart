import 'package:supabase_flutter/supabase_flutter.dart';

class EulaModel {
  final int versionNumber;
  final String title;
  final String content;

  EulaModel({required this.versionNumber, required this.title, required this.content});

  factory EulaModel.fromMap(Map<String, dynamic> map) {
    return EulaModel(
      versionNumber: map['version_number'],
      title: map['title'],
      content: map['content'],
    );
  }
}

class EulaService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Fetches the latest EULA version available in the database
  Future<EulaModel?> fetchLatestEula() async {
    final response = await _supabase
        .from('license_agreements')
        .select()
        .order('version_number', ascending: false)
        .limit(1)
        .maybeSingle();

    if (response == null) return null;
    return EulaModel.fromMap(response);
  }

  /// Checks if the current user has accepted the specified version
  Future<bool> hasUserAcceptedVersion(String userId, int versionNumber) async {
    final response = await _supabase
        .from('user_eula_acceptances')
        .select()
        .eq('user_id', userId)
        .eq('agreement_version', versionNumber)
        .maybeSingle();

    return response != null;
  }

  /// Records the user's acceptance of a specific EULA version
  Future<void> acceptEula(String userId, int versionNumber) async {
    await _supabase.from('user_eula_acceptances').insert({
      'user_id': userId,
      'agreement_version': versionNumber,
    });
  }
}
