import 'package:flutter/material.dart';
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
    final targetUrl = _homeUrl.toString();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) async {
            final requestUri = Uri.tryParse(request.url);
            final host = requestUri?.host;

            // Only intercept requests to the same host
            if (host == widget.appUri.host) {
              // If this is the target URL or a sub-path, load it with auth headers
              if (request.url == targetUrl || request.url.startsWith('${widget.appUri.scheme}://${widget.appUri.host}/eand/')) {
                if (_lastHeaderUrl != request.url) {
                  _lastHeaderUrl = request.url;
                  debugPrint('TokenWebViewPage:loading with auth headers: ${request.url}');
                  await _controller.loadRequest(
                    Uri.parse(request.url),
                    headers: {'Authorization': 'Bearer ${widget.userToken}'},
                  );
                  return NavigationDecision.prevent;
                }
              } else {
                // For other URLs on the same host, allow navigation
                return NavigationDecision.navigate;
              }
            }
            return NavigationDecision.navigate;
          },
        ),
      );
    
    // Directly load the target URL with auth headers instead of using HTML redirect
    _controller.loadRequest(
      _homeUrl,
      headers: {'Authorization': 'Bearer ${widget.userToken}'},
    );
  }

  Uri get _homeUrl => widget.appUri.replace(
    pathSegments: [...widget.appUri.pathSegments.where((segment) => segment.isNotEmpty), 'eand', 'home'],
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: WebViewWidget(controller: _controller));
  }
}
