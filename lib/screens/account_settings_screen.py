import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/supabase_service.dart';

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({Key? key}) : super(key: key);

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  bool _isSubscribed = false;
  bool _isLoading = true;
  final String _userEmail = BackendService.supabase.auth.currentUser?.email ?? 'Unknown';

  @override
  void initState() {
    super.initState();
    _checkSubscriptionStatus();
  }

  Future<void> _checkSubscriptionStatus() async {
    final active = await BackendService.isSubscriptionActive();
    setState(() {
      _isSubscribed = active;
      _isLoading = false;
    });
  }

  Future<void> _manageBilling() async {
    setState(() => _isLoading = true);
    try {
      String targetUrl;
      if (_isSubscribed) {
        // Active members get redirected to manage card information / cancel
        targetUrl = await BackendService.getStripePortalUrl();
      } else {
        // Non-active members go directly to signup checkout page
        targetUrl = await BackendService.getSubscriptionUrl();
      }
      await launchUrl(Uri.parse(targetUrl), mode: LaunchMode.externalApplication);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Billing Error: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account Profile')),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  title: const Text('Logged In As', style: TextStyle(color: Colors.grey)),
                  subtitle: Text(_userEmail, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  leading: const Icon(Icons.person),
                ),
                const Divider(),
                ListTile(
                  title: const Text('App Access Level', style: TextStyle(color: Colors.grey)),
                  subtitle: Text(_isSubscribed ? 'PRO Subscriber (Monthly)' : 'No Active Subscription', 
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _isSubscribed ? Colors.green : Colors.red)),
                  leading: Icon(_isSubscribed ? Icons.verified : Icons.gpp_bad),
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: _manageBilling,
                  icon: const Icon(Icons.credit_card),
                  label: Text(_isSubscribed ? 'Manage Billing / Cancel' : 'Subscribe to voXRAY Pro'),
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: () async {
                    await BackendService.signOut();
                    if (mounted) Navigator.of(context).popToRoot(); // Route back to login screen
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign Out'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                )
              ],
            ),
          ),
    );
  }
}
