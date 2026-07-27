import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// TODO: Point this to your actual main DAW screen
import 'main_daw_screen.dart'; 

class AuthGate extends StatefulWidget {
  const AuthGate({Key? key}) : super(key: key);

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _isLoading = true;
  bool _isPro = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkProfileStatus();
  }

  Future<void> _checkProfileStatus() async {
    final user = Supabase.instance.client.auth.currentUser;
    
    // If no user is logged in, stop loading and let the login screen show
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      // Query the new profiles table we made in SQL
      final response = await Supabase.instance.client
          .from('profiles')
          .select('is_pro')
          .eq('id', user.id)
          .single();

      if (mounted) {
        setState(() {
          _isPro = response['is_pro'] as bool? ?? false;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = "Could not verify account status.";
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 1. Listen to the global auth state stream
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = snapshot.data?.session;

        // 2. If they are completely logged out, show your standard Login Screen
        if (session == null) {
          // TODO: Replace with your actual login screen widget
          return const Scaffold(
            body: Center(child: Text("Login Screen Goes Here")),
          ); 
        }

        // 3. If we are currently fetching their profile status, show a loader
        if (_isLoading) {
          return const Scaffold(
            backgroundColor: Color(0xFF121212),
            body: Center(
              child: CircularProgressIndicator(color: Colors.pinkAccent),
            ),
          );
        }

        // 4. If they paid and the webhook flipped the boolean, let them in!
        if (_isPro) {
          return const MainDawScreen();
        }

        // 5. If they are logged in but NOT pro, trap them on the waitlist screen
        return Scaffold(
          backgroundColor: const Color(0xFF121212),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_clock, size: 64, color: Colors.white54),
                  const SizedBox(height: 24),
                  const Text(
                    "Account Pending Activation",
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "Your Voxray Pro account has been created, but requires an active subscription to unlock the DSP engine.\n\nPlease check your email for your beta approval link, or visit voxray.info to manage your account.",
                    style: TextStyle(fontSize: 14, color: Colors.white70, height: 1.5),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  
                  if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: Text(_errorMessage!, 
                        style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                    ),

                  // A refresh button just in case they paid while staring at this screen
                  OutlinedButton.icon(
                    icon: const Icon(Icons.refresh, color: Colors.pinkAccent),
                    label: const Text("Check Status", style: TextStyle(color: Colors.white)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.pinkAccent),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    onPressed: () {
                      setState(() {
                        _isLoading = true;
                        _errorMessage = null;
                      });
                      _checkProfileStatus();
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  // Crucial: Let them log out if they used the wrong account
                  TextButton(
                    onPressed: () => Supabase.instance.client.auth.signOut(),
                    child: const Text("Log Out", style: TextStyle(color: Colors.white54)),
                  )
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
