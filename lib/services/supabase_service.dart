import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:developer' as developer;
import 'dart:convert';
import 'package:http/http.dart' as http;

/// A centralized service to handle all Supabase interactions for voXRAY.
class BackendService {
  // Access the singleton Supabase client
  static final supabase = Supabase.instance.client;

  // ==========================================
  // 1. AUTHENTICATION
  // ==========================================
  
  static Future<AuthResponse> signUpEmail(String email, String password) async {
    return await supabase.auth.signUp(email: email, password: password);
  }

  static Future<AuthResponse> signInEmail(String email, String password) async {
    return await supabase.auth.signInWithPassword(email: email, password: password);
  }

  static Future<void> signOut() async {
    await supabase.auth.signOut();
  }

  // ==========================================
  // 2. WALLET
  // ==========================================
  
  /// Fetches the current user's DSP token balance from the secure wallet table.
  static Future<double> getDSPBalance() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return 0.0;

    try {
      final response = await supabase
          .from('user_wallets')
          .select('balance_dsp_tokens')
          .eq('user_id', userId)
          .single();
      
      return (response['balance_dsp_tokens'] as num).toDouble();
    } catch (e) {
      developer.log('Error fetching balance: $e');
      return 0.0;
    }
  }

  // ==========================================
  // 3. SYSTEM LOGGING
  // ==========================================
  
  static Future<void> logEvent({
    required String platform,
    String layer = 'client', 
    required String severity,
    required String message,
  }) async {
    try {
      await supabase.from('system_logs').insert({
        'user_id': supabase.auth.currentUser?.id, 
        'platform': platform,
        'layer': layer,
        'severity': severity,
        'message': message,
      });
      developer.log('✅ Successfully sent $severity log to Supabase!');
    } catch (e) {
      developer.log('❌ Failed to send log to Supabase: $e');
    }
  }

  // ==========================================
  // 4. USER FEEDBACK
  // ==========================================
  
  static Future<void> submitFeedback(String notes) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Must be logged in to submit feedback.');

    await supabase.from('user_feedback').insert({
      'user_id': userId,
      'notes': notes,
    });
  }

  // ==========================================
  // 5. MODAL DSP API
  // ==========================================
  
  /// Sends an audio payload to your Modal backend for processing.
  static Future<Map<String, dynamic>> processAudio(String base64AudioData) async {
    final session = supabase.auth.currentSession;
    if (session == null) {
      throw Exception('Must be logged in to process audio.');
    }

    final modalUrl = Uri.parse('https://donkelleymusic--voxray-api-process-audio.modal.run');

    try {
      final response = await http.post(
        modalUrl,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'access_token': session.accessToken,
          'audio_payload': base64AudioData,
        }),
      );

      // Successfully processed and deducted tokens
      if (response.statusCode == 200) {
        final decodedData = jsonDecode(response.body);
        
        // --- THE FASTAPI TUPLE FIX ---
        // FastAPI converts Python tuples like `return {"error": ...}, 402` into a JSON List 
        // `[{"error": ...}, 402]` while keeping the HTTP status as 200. We catch that list here:
        if (decodedData is List && decodedData.length >= 2 && decodedData[1] == 402) {
           final errorMap = decodedData[0] as Map;
           throw Exception(errorMap['error'] ?? 'Insufficient DSP tokens. Please top up your wallet.');
        }

        // Normal successful processing
        if (decodedData is Map<String, dynamic>) {
           return decodedData;
        } else if (decodedData is Map) {
           return Map<String, dynamic>.from(decodedData);
        }
        
        throw Exception('API returned unexpected data format. Raw response: ${response.body}');
      } 
      
      // Handle the 402 Insufficient Funds explicitly
      if (response.statusCode == 402) {
        throw Exception('Insufficient DSP tokens. Please top up your wallet.');
      }
      
      // Handle all other API errors gracefully without crashing the JSON parser
      throw Exception('API Error (${response.statusCode}): ${response.body}');
      
    } catch (e) {
      developer.log('Failed to connect to Modal API: $e');
      rethrow;
    }
  }

  // ==========================================
  // 6. STRIPE INTEGRATION
  // ==========================================
  
  /// Asks Modal to generate a secure Stripe Checkout URL for buying tokens.
  /// Returns the URL as a String so the Flutter UI can launch it in a browser.
  static Future<String> getStripeCheckoutUrl(int tokenAmountToBuy) async {
    final session = supabase.auth.currentSession;
    if (session == null) throw Exception('Must be logged in to buy tokens.');

    // 1. Point to the FastAPI Modal App base URL + the specific endpoint route
    // Note: If you are running modal serve, this might have a -dev suffix (e.g., ...api-api-dev.modal.run)
    final stripeModalUrl = Uri.parse('https://donkelleymusic--voxray-pro-api-api.modal.run/create-checkout-session');

    try {
      final response = await http.post(
        stripeModalUrl,
        // 2. Switch from application/json to form-urlencoded to match FastAPI Form(...)
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        // 3. Pass data as a Map of strings, matching the exact parameter names in Python
        body: {
          'access_token': session.accessToken,
          'amount': tokenAmountToBuy.toString(), 
        },
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        
        if (decoded is Map && decoded.containsKey('checkout_url')) {
          return decoded['checkout_url'];
        }
        throw Exception('Invalid response from Stripe API');
      } else {
        throw Exception('API Error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      developer.log('Failed to get Stripe checkout URL: $e');
      rethrow;
    }
  }
  // Inside class BackendService...

  /// Check if the user has an active monthly subscription
  static Future<bool> isSubscriptionActive() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return false;
    try {
      final response = await supabase
          .from('user_wallets')
          .select('subscription_status')
          .eq('user_id', userId)
          .single();
      return response['subscription_status'] == 'active';
    } catch (_) {
      return false;
    }
  }

  /// Get the Checkout URL for starting a new subscription (Monthly or Yearly)
  static Future<String> getSubscriptionUrl({String tier = 'monthly'}) async {
    final session = supabase.auth.currentSession;
    if (session == null) throw Exception('Must be logged in.');

    final url = Uri.parse('https://donkelleymusic--voxray-pro-api-api.modal.run/create-subscription-session');
    final response = await http.post(url, headers: {'Content-Type': 'application/x-www-form-urlencoded'}, body: {
      'access_token': session.accessToken,
      'tier': tier, // Passes 'monthly' or 'yearly' to Python
    });
    if (response.statusCode == 200) {
      return jsonDecode(response.body)['checkout_url'];
    }
    throw Exception(response.body);
  }

  /// Get the pre-built Stripe Customer Portal URL for modifying cards or canceling
  static Future<String> getStripePortalUrl() async {
    final session = supabase.auth.currentSession;
    if (session == null) throw Exception('Must be logged in.');

    final url = Uri.parse('https://donkelleymusic--voxray-pro-api-api.modal.run/create-portal-session');
    final response = await http.post(url, headers: {'Content-Type': 'application/x-www-form-urlencoded'}, body: {
      'access_token': session.accessToken,
    });
    if (response.statusCode == 200) {
      return jsonDecode(response.body)['portal_url'];
    }
    throw Exception(response.body);
  }

  /// Dynamic app texts fetched from Supabase (About info, FAQ, announcements)
  static Future<String> fetchAppContent(String key) async {
    try {
      final res = await supabase.from('app_content').select('content').eq('key', key).single();
      return res['content'] as String;
    } catch (e) {
      return "Failed to load content.";
    }
  }
  
}
