import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'webview.dart';

class TokenGenerationPage extends StatefulWidget {
  const TokenGenerationPage({super.key});

  @override
  State<TokenGenerationPage> createState() => _TokenGenerationPageState();
}

class _TokenGenerationPageState extends State<TokenGenerationPage> {
  bool _isLoading = true;
  String? _errorMessage;

  // API configuration
  static const String _baseUrl = 'https://dahabmasr.net/eand/api/v1/generate-webview-token';
  static const String _authToken = 'Bearer 2neaat67uh4yenevii8ixz7ac1oevwp';
  static const Map<String, String> _requestBody = {
    'userId': 'tse1yPjNT0BDxJ7BWILo4Q==',
    'dial': '01066002669',
    'clientId': 'etisalat',
    'secret': 'dummy',
  };

  @override
  void initState() {
    super.initState();
    _generateToken();
  }

  Future<void> _generateToken() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {'Content-Type': 'application/json', 'Authorization': _authToken},
        body: jsonEncode(_requestBody),
      );
      print(response.request);
      print(response.headers);
      print(response.body);
      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body) as Map<String, dynamic>;

        if (responseData['success'] == true && responseData['token'] != null) {
          final token = responseData['token'] as String;
          final appUri = Uri.parse('https://dahabmasr.net');

          // Navigate to webview with generated token
          if (mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => TokenWebViewPage(appUri: appUri, userToken: token),
              ),
            );
          }
        } else {
          setState(() {
            _errorMessage = responseData['message'] as String? ?? 'Failed to generate token';
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _errorMessage = 'Error: ${response.statusCode} - ${response.body}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Network error: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isLoading) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 24),
                const Text('Generating token...', style: TextStyle(fontSize: 16)),
              ] else if (_errorMessage != null) ...[
                const Icon(Icons.error_outline, color: Colors.red, size: 64),
                const SizedBox(height: 24),
                Text('Error', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
                const SizedBox(height: 24),
                ElevatedButton(onPressed: _generateToken, child: const Text('Retry')),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
