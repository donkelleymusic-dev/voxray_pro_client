import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart'; // Adjust path if needed

// IMPORTANT: Adjust this import to point to the file where VoxrayDAW is located!
import '../main.dart'; 
import 'account_settings_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({Key? key}) : super(key: key);

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // Helper method to show messages to the user
  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  Future<void> _signUp() async {
    setState(() => _isLoading = true);
    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim(); // Fixed typo here
      
      if (email.isEmpty || password.isEmpty) {
        throw Exception('Please fill in both fields.');
      }

      await BackendService.signUpEmail(email, password);
      
      //_showMessage('Sign up successful! Welcome to voXRAY.');
      // NOTE: Because of our SQL trigger, their wallet with 0 DSP is already created!
      
      _showMessage('Authentication successful!');
      if (!mounted) return;
      
      // Check Subscription Status!
      bool isSubbed = await BackendService.isSubscriptionActive();
      
      if (!mounted) return;
      if (isSubbed) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const VoxrayDAW()));
      } else {
        // Send them to the Paywall and hide the back button
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => AccountSettingsScreen(isForcedPaywall: true)));
      }
      
    } on AuthException catch (e) {
      _showMessage(e.message, isError: true);
    } catch (e) {
      _showMessage(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signIn() async {
    setState(() => _isLoading = true);
    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();
      
      if (email.isEmpty || password.isEmpty) {
        throw Exception('Please fill in both fields.');
      }

      await BackendService.signInEmail(email, password);
      
      //_showMessage('Welcome back!');
      
      _showMessage('Authentication successful!');
      if (!mounted) return;
      
      // Check Subscription Status!
      bool isSubbed = await BackendService.isSubscriptionActive();
      
      if (!mounted) return;
      if (isSubbed) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const VoxrayDAW()));
      } else {
        // Send them to the Paywall and hide the back button
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => AccountSettingsScreen(isForcedPaywall: true)));
      }
      
    } on AuthException catch (e) {
      _showMessage(e.message, isError: true);
    } catch (e) {
      _showMessage(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showForgotPasswordDialog() {
    final TextEditingController _resetEmailController = TextEditingController(text: _emailController.text);
    bool _isSending = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: Colors.grey[900],
            title: const Text('Reset Password', style: TextStyle(color: Colors.white)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Enter your email address and we will send you a secure link to reset your password.',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _resetEmailController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    labelStyle: TextStyle(color: Colors.pinkAccent),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.pinkAccent)),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.pinkAccent),
                onPressed: _isSending ? null : () async {
                  setState(() => _isSending = true);
                  try {
                    await BackendService.supabase.auth.resetPasswordForEmail(
                      _resetEmailController.text.trim(),
                      redirectTo: 'voxray://reset-password', // Uses your existing deep link scheme!
                    );
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Reset link sent! Check your email.'), backgroundColor: Colors.green),
                    );
                  } catch (e) {
                    setState(() => _isSending = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.red),
                    );
                  }
                },
                child: _isSending 
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Send Link', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        }
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true, // <-- Changed to true!
        title: Image.asset(
          'assets/images/voXRay_logo_transparent_crop.png',
          height: 30,
          fit: BoxFit.contain,
        ),
      ),
        /*title: const Text('voXRay Beta Login')),*/
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12), // Adds nice rounded corners to the banner
                child: Image.asset(
                  'assets/images/don-music-google_play_developer_banner_4096-2304.jpg',
                  height: 120, // Bigger than the old icon! Adjust this number if you want it even larger.
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: true,                
                autofillHints: const [AutofillHints.password],
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
              ),
              const SizedBox(height: 24),
              if (_isLoading)
                const Center(child: CircularProgressIndicator())
              else ...[
                ElevatedButton(
                  onPressed: _signIn,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Sign In', style: TextStyle(fontSize: 16)),
                ),
                TextButton(onPressed: _showForgotPasswordDialog, child: const Text("Forgot Password?"))
                const Text(
                  "Beta Registration: visit voxray.info",
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                )
                /*const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _signUp,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Create Account'),
                ),*/
              ],
            ],
          ),
        ),
      ),
    );
  }
}
