import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter/webview_flutter.dart';

class TokenWebViewPage extends StatefulWidget {
  const TokenWebViewPage({super.key, required this.appUri, required this.userToken});

  final Uri appUri;
  final String userToken;

  @override
  State<TokenWebViewPage> createState() => _TokenWebViewPageState();
}

class _TokenWebViewPageState extends State<TokenWebViewPage> {
  late final WebViewController _controller;
  String? _lastHeaderUrl;

  @override
  void initState() {
    super.initState();
    _requestCameraPermission();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) async {
            final host = Uri.tryParse(request.url)?.host;

            if (host == widget.appUri.host) {
              await _controller.runJavaScript('try { console.log("localStorage", localStorage.getItem("token"));');

              if (_lastHeaderUrl != request.url) {
                _lastHeaderUrl = request.url;
                await _controller.loadRequest(
                  Uri.parse(request.url),
                  headers: {'Authorization': 'Bearer ${widget.userToken}'},
                );
                return NavigationDecision.prevent;
              }
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadHtmlString(_bootstrapHtml, baseUrl: widget.appUri.toString());
  }

  Future<void> _requestCameraPermission() async {
    // Request camera permission
    final cameraStatus = await Permission.camera.request();
    if (cameraStatus.isDenied) {
      debugPrint('Camera permission denied');
    } else if (cameraStatus.isPermanentlyDenied) {
      debugPrint('Camera permission permanently denied');
    }

    // Request storage permissions for saving images
    // Permission.photos handles Android 13+ (API 33+) automatically
    // Permission.storage is for older Android versions
    try {
      // Try photos permission first (Android 13+ and iOS)
      final photosStatus = await Permission.photos.request();
      if (photosStatus.isDenied) {
        debugPrint('Photos permission denied');
      }
    } catch (e) {
      // Fallback for older Android versions
      debugPrint('Photos permission not available, trying storage: $e');
      try {
        await Permission.storage.request();
      } catch (e2) {
        debugPrint('Storage permission request failed: $e2');
      }
    }
  }

  Uri get _homeUrl => widget.appUri.replace(
    pathSegments: [...widget.appUri.pathSegments.where((segment) => segment.isNotEmpty), 'eand', 'home'],
  );

  String get _bootstrapHtml {
    final targetUrl = jsonEncode(_homeUrl.toString());
    debugPrint('TokenWebViewPage:targetUrl=$targetUrl');
    return '''
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<script>
console.log("token",localStorage.getItem("token"));
window.location.replace($targetUrl);
</script>
</head>
<body>Loading...</body>
</html>
''';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: WebViewWidget(controller: _controller));
  }
}
