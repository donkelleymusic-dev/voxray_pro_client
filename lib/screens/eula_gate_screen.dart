import 'package:flutter/material.dart';
import '../eula_service.dart';

class EulaGateScreen extends StatefulWidget {
  final EulaModel eula;
  final String userId;
  final VoidCallback onAccepted;

  const EulaGateScreen({
    super.key,
    required this.eula,
    required this.userId,
    required this.onAccepted,
  });

  @override
  State<EulaGateScreen> createState() => _EulaGateScreenState();
}

class _EulaGateScreenState extends State<EulaGateScreen> {
  bool _isChecked = false;
  bool _isSubmitting = false;
  final EulaService _eulaService = EulaService();

  Future<void> _handleAccept() async {
    setState(() => _isSubmitting = true);
    try {
      await _eulaService.acceptEula(widget.userId, widget.eula.versionNumber);
      widget.onAccepted();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving agreement: $e')),
      );
      setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false, // Prevent bypassing via back button
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.eula.title),
          automaticallyImplyLeading: false,
        ),
        body: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              const Text(
                'Please review and accept the updated Terms of Service and EULA to continue using voXRay.',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Scrollbar(
                    child: SingleChildScrollView(
                      child: Text(
                        widget.eula.content,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                title: const Text('I have read and agree to the voXRay EULA & Terms of Service.'),
                value: _isChecked,
                onChanged: (val) => setState(() => _isChecked = val ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_isChecked && !_isSubmitting) ? _handleAccept : null,
                  child: _isSubmitting
                      ? const CircularProgressIndicator.adaptive()
                      : const Text('Agree & Continue'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
