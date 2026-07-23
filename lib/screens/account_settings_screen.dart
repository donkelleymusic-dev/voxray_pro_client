import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/supabase_service.dart';
import '../main.dart';
import 'auth_screen.dart';

class AccountSettingsScreen extends StatefulWidget {
  final bool isForcedPaywall; // If true, the user MUST subscribe to continue
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

  Future<void> _launchStripe(String tier) async {
    setState(() => _isLoading = true);
    try {
      String targetUrl;
      if (_isSubscribed) {
        targetUrl = await BackendService.getStripePortalUrl();
      } else {
        targetUrl = await BackendService.getSubscriptionUrl(tier: tier);
      }
      await launchUrl(Uri.parse(targetUrl), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Billing Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
              tooltip: 'Check Payment Status',
              onPressed: () async {
                setState(() => _isLoading = true);
                await _checkSubscriptionStatus();
                
                if (_isSubscribed && mounted) {
                  // ✅ FIX: Defer navigation safely out of the current build frame
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
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.isForcedPaywall) ...[
                  const Icon(Icons.lock_outline, size: 64, color: Colors.amberAccent),
                  const SizedBox(height: 16),
                  const Text('Active Subscription Required', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const Text('You must subscribe to access the voXRAY Pro DAW.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
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
                  subtitle: Text(_isSubscribed ? 'PRO Subscriber' : 'No Active Subscription', 
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _isSubscribed ? Colors.green : Colors.red)),
                  leading: Icon(_isSubscribed ? Icons.verified : Icons.gpp_bad),
                ),
                const SizedBox(height: 32),
                
                /*if (_isSubscribed)
                  ElevatedButton.icon(
                    onPressed: () => _launchStripe('portal'),
                    icon: const Icon(Icons.credit_card),
                    label: const Text('Manage Billing / Cancel'),
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  )
                else ...[
                  ElevatedButton.icon(
                    onPressed: () => _launchStripe('monthly'),
                    icon: const Icon(Icons.calendar_month),
                    label: const Text('Subscribe Monthly (Includes 100 Tokens)'),
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () => _launchStripe('yearly'),
                    icon: const Icon(Icons.star),
                    label: const Text('Subscribe Yearly (Includes 2000 Tokens)'),
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), backgroundColor: Colors.amberAccent, foregroundColor: Colors.black),
                  ),
                ],*/

                const Spacer(),
                OutlinedButton.icon(
                  onPressed: () async {
                    await BackendService.signOut();
                    if (mounted) {
                      // ✅ FIX: Defer navigation safely out of the current build frame
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(builder: (_) => AuthScreen()), 
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
    );
  }
}
