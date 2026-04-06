import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'webview.dart';
import 'app_config.dart';

class TokenGenerationPage extends StatefulWidget {
  const TokenGenerationPage({
    super.key,
    required this.dial,
    required this.userId,
    required this.clientLanguage,
  });

  final String dial;
  final String userId;
  final String clientLanguage;

  @override
  State<TokenGenerationPage> createState() => _TokenGenerationPageState();
}

class _TokenGenerationPageState extends State<TokenGenerationPage> {
  bool _isLoading = true;
  String? _errorMessage;

  Map<String, String> get _requestBody => {
    'userId': widget.userId,
    'dial': widget.dial,
    'clientId': AppConfig.clientId,
    'secret': AppConfig.clientSecret,
    'clientLanguage': widget.clientLanguage,
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
        Uri.parse(AppConfig.tokenApiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': AppConfig.tokenApiAuthHeader,
        },
        body: jsonEncode(_requestBody),
      );
      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body) as Map<String, dynamic>;

        if (responseData['success'] == true && 
            responseData['data'] != null && 
            responseData['data'] is Map &&
            (responseData['data'] as Map<String, dynamic>)['accessToken'] != null) {
          final data = responseData['data'] as Map<String, dynamic>;
          final token = data['accessToken'] as String;
          final appUri = Uri.parse(AppConfig.webBaseUrl);

          // Navigate to webview with generated token
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => TokenWebViewPage(appUri: appUri, userToken: token),
              ),
            );
          }
        } else {
          // Check for error in response
          final errorMessage = responseData['error'] as String?;
          setState(() {
            _errorMessage = errorMessage ?? 'Failed to generate token';
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _errorMessage = 'Request failed (${response.statusCode}). Please try again.';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = kDebugMode ? 'Network error: $e' : 'Network error. Please try again.';
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
