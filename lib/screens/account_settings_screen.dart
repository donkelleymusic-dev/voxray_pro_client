import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/supabase_service.dart';
import '../main.dart';
import 'auth_screen.dart';

class AccountSettingsScreen extends StatefulWidget {
  final bool isForcedPaywall; // If true, the user MUST have an approved account to continue
  const AccountSettingsScreen({Key? key, this.isForcedPaywall = false}) : super(key: key);

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
    if (mounted) {
      setState(() {
        _isSubscribed = active;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Account Profile'),
        automaticallyImplyLeading: !widget.isForcedPaywall, // Hide back button if forced
        actions: [
          if (widget.isForcedPaywall)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Check Account Status',
              onPressed: () async {
                setState(() => _isLoading = true);
                await _checkSubscriptionStatus();
                
                if (_isSubscribed && mounted) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => const VoxrayDAW()),
                      );
                    }
                  });
                }
              },
            )
        ],
      ),
      // ✅ FIX: SafeArea ensures bottom UI elements avoid the Android system nav bar
      body: SafeArea(
        child: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.isForcedPaywall) ...[
                    const Icon(Icons.lock_outline, size: 64, color: Colors.amberAccent),
                    const SizedBox(height: 16),
                    const Text('Active Approved Account Required', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text('You must wait for approval to access the voXRay Forensic DAW.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 24),
                  ],
                  ListTile(
                    title: const Text('Logged In As', style: TextStyle(color: Colors.grey)),
                    subtitle: Text(_userEmail, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    leading: const Icon(Icons.person),
                  ),
                  const Divider(),
                  ListTile(
                    title: const Text('App Access Level', style: TextStyle(color: Colors.grey)),
                    subtitle: Text(_isSubscribed ? 'PRO Account' : 'No Approved Active Account', 
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _isSubscribed ? Colors.green : Colors.red)),
                    leading: Icon(_isSubscribed ? Icons.verified : Icons.gpp_bad),
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await BackendService.signOut();
                      if (mounted) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) {
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(builder: (_) => const AuthScreen()), 
                              (route) => false,
                            );
                          }
                        });
                      }
                    },
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign Out'),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  )
                ],
              ),
            ),
      ),
    );
  }
}
