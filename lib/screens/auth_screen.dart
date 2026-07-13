import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart'; // Adjust path if needed

// IMPORTANT: Adjust this import to point to the file where VoxrayDAW is located!
import '../main.dart'; 

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
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AccountSettingsScreen(isForcedPaywall: true)));
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
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AccountSettingsScreen(isForcedPaywall: true)));
      }
      
    } on AuthException catch (e) {
      _showMessage(e.message, isError: true);
    } catch (e) {
      _showMessage(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('voXRAY Beta Login')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.graphic_eq, size: 80, color: Colors.blue),
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
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _signUp,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Create Account'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
