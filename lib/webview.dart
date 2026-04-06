import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview/login_page.dart';

class TokenWebViewPage extends StatefulWidget {
  const TokenWebViewPage({super.key, required this.appUri, required this.userToken});

  final Uri appUri;
  final String userToken;

  @override
  State<TokenWebViewPage> createState() => _TokenWebViewPageState();
}

class _TokenWebViewPageState extends State<TokenWebViewPage> {
  String? _lastHeaderUrl;
  bool _cameraPermissionRequested = false;
  InAppWebViewController? _webViewController;
  Future<void>? _locationFlowInFlight;

  bool _isAllowedWebUri(Uri uri) {
    // Allow only HTTPS to the expected host (and subdomains).
    if (uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    final allowedHost = widget.appUri.host.toLowerCase();
    return host == allowedHost || host.endsWith('.$allowedHost');
  }

  @override
  void initState() {
    super.initState();
    // Permission will be requested when JavaScript sends CAMERA_PERMISSION_REQUEST message
  }

  Future<void> _requestCameraPermissionIfNeeded() async {
    // Check current status first
    final currentStatus = await Permission.camera.status;
    if (currentStatus.isGranted) {
      if (kDebugMode) debugPrint('Camera permission already granted');
      return; // Already granted, no need to request
    }

    if (_cameraPermissionRequested && currentStatus.isDenied) {
      // Already requested and denied, don't ask again in this session
      if (kDebugMode) debugPrint('Camera permission was already requested and denied');
      return;
    }

    _cameraPermissionRequested = true;
    if (kDebugMode) {
      debugPrint('Requesting camera permission triggered by web message');
    }

    // Request camera permission
    final cameraStatus = await Permission.camera.request();
    if (cameraStatus.isGranted) {
      if (kDebugMode) debugPrint('Camera permission granted');
      // No need to reload, the WebView will request permission and we'll grant it
    } else if (cameraStatus.isDenied) {
      if (kDebugMode) debugPrint('Camera permission denied');
      _cameraPermissionRequested = false; // Allow retry on next navigation
    } else if (cameraStatus.isPermanentlyDenied) {
      if (kDebugMode) debugPrint('Camera permission permanently denied');
      // Show dialog to open settings
      if (mounted) {
        _showPermissionDeniedDialog();
      }
    }
  }

  Future<void> _requestLocationPermissionIfNeeded() async {
    // Multiple triggers can arrive quickly (postMessage + console + handler call).
    // Permission Handler does not allow concurrent requests, so serialize the flow.
    if (_locationFlowInFlight != null) {
      await _locationFlowInFlight;
      return;
    }

    _locationFlowInFlight = () async {
      try {
        final currentStatus = await Permission.locationWhenInUse.status;
        if (currentStatus.isGranted) {
          if (kDebugMode) debugPrint('Location permission already granted');
          await _getAndSendCurrentLocationToWeb();
          return;
        }

        if (kDebugMode) debugPrint('Requesting location permission triggered by web message');
        final status = await Permission.locationWhenInUse.request();

        if (status.isGranted) {
          if (kDebugMode) debugPrint('Location permission granted');
          await _getAndSendCurrentLocationToWeb();
        } else if (status.isDenied) {
          if (kDebugMode) debugPrint('Location permission denied');
        } else if (status.isPermanentlyDenied) {
          if (kDebugMode) debugPrint('Location permission permanently denied');
          if (mounted) {
            _showLocationPermissionDeniedDialog();
          }
        }
      } finally {
        _locationFlowInFlight = null;
      }
    }();

    await _locationFlowInFlight;
  }

  Future<void> _getAndSendCurrentLocationToWeb() async {
    final controller = _webViewController;
    if (controller == null) return;

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (kDebugMode) debugPrint('Location services are disabled');
        return;
      }

      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        // Permission requests are handled via permission_handler to avoid
        // overlapping requests coming from two plugins.
        if (kDebugMode) {
          debugPrint('Geolocator reports permission denied (will not request here)');
        }
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        if (kDebugMode) debugPrint('Geolocator permission denied forever');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      final lat = position.latitude;
      final lng = position.longitude;
      if (kDebugMode) debugPrint('Sending coordinates to web');

      await controller.evaluateJavascript(
        source: '''
          (function() {
            var lat = ${lat.toStringAsFixed(7)};
            var lng = ${lng.toStringAsFixed(7)};
            var tries = 0;
            function send() {
              tries++;
              if (typeof window.setAddressCoordinatesFromFlutter === 'function') {
                window.setAddressCoordinatesFromFlutter(lat, lng);
                return;
              }
              if (tries < 25) {
                setTimeout(send, 200);
              }
            }
            send();
          })();
        ''',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to get/send location: $e');
    }
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Camera Permission Required'),
          content: const Text('Camera permission is required to capture ID card. Please enable it in app settings.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                openAppSettings();
              },
              child: const Text('Open Settings'),
            ),
          ],
        );
      },
    );
  }

  void _showLocationPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Location Permission Required'),
          content: const Text('Location permission is required to add an address. Please enable it in app settings.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                openAppSettings();
              },
              child: const Text('Open Settings'),
            ),
          ],
        );
      },
    );
  }

  Uri get _homeUrl => widget.appUri.replace(
    pathSegments: [...widget.appUri.pathSegments.where((segment) => segment.isNotEmpty), 'eand', 'home'],
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: InAppWebView(
        initialUrlRequest: URLRequest(
          url: WebUri(_homeUrl.toString()),
          headers: {'Authorization': 'Bearer ${widget.userToken}'},
        ),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          mediaPlaybackRequiresUserGesture: false,
          allowsInlineMediaPlayback: true,
          useShouldOverrideUrlLoading: true,
          javaScriptCanOpenWindowsAutomatically: false,
          supportMultipleWindows: false,
          mixedContentMode: MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
          thirdPartyCookiesEnabled: false,
          cacheEnabled: false,
          clearCache: true,
          allowFileAccessFromFileURLs: false,
          allowUniversalAccessFromFileURLs: false,
          allowContentAccess: false,
          allowFileAccess: false,
        ),
        onWebViewCreated: (controller) {
          _webViewController = controller;

          controller.addJavaScriptHandler(
            handlerName: 'onCameraPermissionRequest',
            callback: (args) {
              if (kDebugMode) {
                debugPrint('TokenWebViewPage:Received camera permission request');
              }
              if (args.isNotEmpty) {
                // Handle both Map and direct object
                dynamic messageData = args[0];
                Map<String, dynamic>? message;

                if (messageData is Map) {
                  message = messageData as Map<String, dynamic>;
                } else if (messageData is String) {
                  try {
                    message = Map<String, dynamic>.from(jsonDecode(messageData));
                  } catch (e) {
                    debugPrint('TokenWebViewPage:Failed to parse message: $e');
                  }
                }

                if (message != null && message['trigger'] == 'CameraStep') {
                  _requestCameraPermissionIfNeeded();
                }
              }
            },
          );

          controller.addJavaScriptHandler(
            handlerName: 'onLocationPermissionRequest',
            callback: (args) {
              if (kDebugMode) {
                debugPrint('TokenWebViewPage:Received location permission request');
              }
              if (args.isNotEmpty) {
                dynamic messageData = args[0];
                Map<String, dynamic>? message;

                if (messageData is Map) {
                  message = messageData as Map<String, dynamic>;
                } else if (messageData is String) {
                  try {
                    message = Map<String, dynamic>.from(jsonDecode(messageData));
                  } catch (e) {
                    debugPrint('TokenWebViewPage:Failed to parse message: $e');
                  }
                }

                if (message != null &&
                    (message['type'] == 'ADD_ADDRESS_REQUEST') &&
                    (message['trigger'] == 'AddAddress')) {
                  _requestLocationPermissionIfNeeded();
                }
              }
            },
          );

          // Some pages may call this handler directly (observed in logs).
          controller.addJavaScriptHandler(
            handlerName: 'requestAddAddress',
            callback: (args) {
              if (kDebugMode) debugPrint('TokenWebViewPage:requestAddAddress called');
              _requestLocationPermissionIfNeeded();
              return {'ok': true};
            },
          );
        },
        onLoadStop: (controller, url) async {
          // Inject JavaScript to listen for postMessage events from the web page
          // (kept intentionally minimal; avoid overriding console.*).
          await controller.evaluateJavascript(
            source: '''
            (function() {
              // Listen for postMessage events
              window.addEventListener('message', function(event) {
                if (event.data && event.data.type === 'CAMERA_PERMISSION_REQUEST') {
                  if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                    window.flutter_inappwebview.callHandler('onCameraPermissionRequest', event.data);
                  }
                }

                if (event.data && event.data.type === 'ADD_ADDRESS_REQUEST' && event.data.trigger === 'AddAddress') {
                  if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                    window.flutter_inappwebview.callHandler('onLocationPermissionRequest', event.data);
                  }
                }
              }, true);
            })();
          ''',
          );
        },
        onLoadStart: (controller, url) async {
          final urlString = url.toString();
          if (kDebugMode) debugPrint('TokenWebViewPage:onLoadStart: $urlString');

          // Parse URI once
          final requestUri = Uri.tryParse(urlString);
          if (requestUri == null || !_isAllowedWebUri(requestUri)) {
            await controller.stopLoading();
            return;
          }

          // Handle navigation to same host with auth headers
          final host = requestUri.host;

          if (host == widget.appUri.host) {
            final targetUrl = _homeUrl.toString();
            if (urlString == targetUrl ||
                urlString.startsWith('${widget.appUri.scheme}://${widget.appUri.host}/eand/')) {
              if (_lastHeaderUrl != urlString) {
                _lastHeaderUrl = urlString;
                if (kDebugMode) {
                  debugPrint('TokenWebViewPage:loading with auth headers: $urlString');
                }
                await controller.loadUrl(
                  urlRequest: URLRequest(
                    url: WebUri(urlString),
                    headers: {'Authorization': 'Bearer ${widget.userToken}'},
                  ),
                );
              }
            }
          }
        },
        shouldOverrideUrlLoading: (controller, navigationAction) async {
          final uri = navigationAction.request.url?.uriValue;
          if (uri == null) {
            return NavigationActionPolicy.CANCEL;
          }
          if (!_isAllowedWebUri(uri)) {
            if (kDebugMode) debugPrint('Blocked navigation to $uri');
            return NavigationActionPolicy.CANCEL;
          }
          return NavigationActionPolicy.ALLOW;
        },
        onReceivedServerTrustAuthRequest: (controller, challenge) async {
          // Do not allow user-provided exceptions for TLS errors.
          return ServerTrustAuthResponse(action: ServerTrustAuthResponseAction.CANCEL);
        },
        onPermissionRequest: (controller, request) async {
          // This handler works for both iOS and Android
          if (kDebugMode) {
            debugPrint(
              'TokenWebViewPage:onPermissionRequest: resources=${request.resources}, origin=${request.origin}',
            );
          }

          // Check if camera permission is requested
          // PermissionResourceType enum values: CAMERA, MICROPHONE, etc.
          final needsCamera = request.resources.any(
            (resource) => resource == PermissionResourceType.CAMERA || resource == PermissionResourceType.MICROPHONE,
          );

          if (needsCamera) {
            // Check current permission status
            final cameraStatus = await Permission.camera.status;
            if (cameraStatus.isGranted) {
              // Grant the permission request
              if (kDebugMode) debugPrint('TokenWebViewPage:Granting camera permission to WebView');
              return PermissionResponse(resources: request.resources, action: PermissionResponseAction.GRANT);
            } else if (cameraStatus.isPermanentlyDenied) {
              // Permission permanently denied - show dialog to open settings
              if (kDebugMode) debugPrint('TokenWebViewPage:Camera permission permanently denied');
              if (mounted) {
                _showPermissionDeniedDialog();
              }
              return PermissionResponse(resources: request.resources, action: PermissionResponseAction.DENY);
            } else {
              // Permission not granted, request it now
              // This handles the case where WebView requests permission before JavaScript message is received
              if (kDebugMode) {
                debugPrint('TokenWebViewPage:Camera permission not granted, requesting now');
              }
              final newStatus = await Permission.camera.request();
              if (newStatus.isGranted) {
                if (kDebugMode) {
                  debugPrint('TokenWebViewPage:Camera permission granted, granting to WebView');
                }
                return PermissionResponse(resources: request.resources, action: PermissionResponseAction.GRANT);
              } else if (newStatus.isPermanentlyDenied) {
                if (kDebugMode) {
                  debugPrint('TokenWebViewPage:Camera permission permanently denied after request');
                }
                if (mounted) {
                  _showPermissionDeniedDialog();
                }
                return PermissionResponse(resources: request.resources, action: PermissionResponseAction.DENY);
              } else {
                // Permission denied (but not permanently) - user can try again
                if (kDebugMode) {
                  debugPrint('TokenWebViewPage:Camera permission denied (user can try again)');
                }
                // On iOS, we might want to still grant to WebView as it will handle the system dialog
                // But for now, we'll deny and let the user try again
                return PermissionResponse(resources: request.resources, action: PermissionResponseAction.DENY);
              }
            }
          }

          // Grant other permissions
          // Restrict WebView permission grants to the minimum set required.
          return PermissionResponse(resources: request.resources, action: PermissionResponseAction.DENY);
        },
        onConsoleMessage: (controller, consoleMessage) {
          final message = consoleMessage.message;
          if (kDebugMode) debugPrint('TokenWebViewPage:onConsoleMessage: $message');
          if (message.contains('LOGOUT_REQUEST')) {
            if (kDebugMode) {
              debugPrint('TokenWebViewPage:Logout request detected, navigating to login');
            }
            if (mounted) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const LoginPage()),
                (route) => false,
              );
            }
          }
        },
      ),
    );
  }
}
