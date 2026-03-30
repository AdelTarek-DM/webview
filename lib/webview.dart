import 'dart:convert';
import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    // Permission will be requested when JavaScript sends CAMERA_PERMISSION_REQUEST message
  }

  Future<void> _requestCameraPermissionIfNeeded() async {
    // Check current status first
    final currentStatus = await Permission.camera.status;
    if (currentStatus.isGranted) {
      debugPrint('Camera permission already granted');
      return; // Already granted, no need to request
    }

    if (_cameraPermissionRequested && currentStatus.isDenied) {
      // Already requested and denied, don't ask again in this session
      debugPrint('Camera permission was already requested and denied');
      return;
    }

    _cameraPermissionRequested = true;
    debugPrint('Requesting camera permission triggered by CAMERA_PERMISSION_REQUEST message');

    // Request camera permission
    final cameraStatus = await Permission.camera.request();
    if (cameraStatus.isGranted) {
      debugPrint('Camera permission granted');
      // No need to reload, the WebView will request permission and we'll grant it
    } else if (cameraStatus.isDenied) {
      debugPrint('Camera permission denied');
      _cameraPermissionRequested = false; // Allow retry on next navigation
    } else if (cameraStatus.isPermanentlyDenied) {
      debugPrint('Camera permission permanently denied');
      // Show dialog to open settings
      if (mounted) {
        _showPermissionDeniedDialog();
      }
    }

    // Also request storage permissions for saving captured images
    try {
      final photosStatus = await Permission.photos.request();
      if (photosStatus.isGranted) {
        debugPrint('Photos permission granted');
      }
    } catch (e) {
      debugPrint('Photos permission not available: $e');
      try {
        await Permission.storage.request();
      } catch (e2) {
        debugPrint('Storage permission request failed: $e2');
      }
    }
  }

  Future<void> _requestLocationPermissionIfNeeded() async {
    final currentStatus = await Permission.locationWhenInUse.status;
    if (currentStatus.isGranted) {
      debugPrint('Location permission already granted');
      await _getAndSendCurrentLocationToWeb();
      return;
    }
    debugPrint('Requesting location permission triggered by ADD_ADDRESS_REQUEST message');

    final status = await Permission.locationWhenInUse.request();
    if (status.isGranted) {
      debugPrint('Location permission granted');
      await _getAndSendCurrentLocationToWeb();
    } else if (status.isDenied) {
      debugPrint('Location permission denied');
    } else if (status.isPermanentlyDenied) {
      debugPrint('Location permission permanently denied');
      if (mounted) {
        _showLocationPermissionDeniedDialog();
      }
    }
  }

  Future<void> _getAndSendCurrentLocationToWeb() async {
    final controller = _webViewController;
    if (controller == null) return;

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Location services are disabled');
        return;
      }

      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final requested = await Geolocator.requestPermission();
        if (requested == LocationPermission.denied) {
          debugPrint('Geolocator permission denied');
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        debugPrint('Geolocator permission denied forever');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      final lat = position.latitude;
      final lng = position.longitude;
      debugPrint('Sending coordinates to web: $lat, $lng');

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
      debugPrint('Failed to get/send location: $e');
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
        ),
        onWebViewCreated: (controller) {
          _webViewController = controller;

          controller.addJavaScriptHandler(
            handlerName: 'onCameraPermissionRequest',
            callback: (args) {
              debugPrint('TokenWebViewPage:Received JavaScript message: $args');
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
              debugPrint('TokenWebViewPage:Received JavaScript message: $args');
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
              debugPrint('TokenWebViewPage:requestAddAddress called: $args');
              _requestLocationPermissionIfNeeded();
              return {'ok': true};
            },
          );
        },
        onLoadStop: (controller, url) async {
          // Inject JavaScript to listen for postMessage events from the web page
          await controller.evaluateJavascript(
            source: '''
            (function() {
              console.log('Flutter: Setting up CAMERA_PERMISSION_REQUEST listener');
              
              // Listen for postMessage events
              window.addEventListener('message', function(event) {
                console.log('Flutter: Received postMessage:', event.data);
                if (event.data && event.data.type === 'CAMERA_PERMISSION_REQUEST') {
                  console.log('Flutter: CAMERA_PERMISSION_REQUEST detected in postMessage');
                  if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                    window.flutter_inappwebview.callHandler('onCameraPermissionRequest', event.data);
                  }
                }

                if (event.data && event.data.type === 'ADD_ADDRESS_REQUEST' && event.data.trigger === 'AddAddress') {
                  console.log('Flutter: ADD_ADDRESS_REQUEST(AddAddress) detected in postMessage');
                  if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                    window.flutter_inappwebview.callHandler('onLocationPermissionRequest', event.data);
                  }
                }
              }, true);
              
              // Also listen for custom DOM events
              document.addEventListener('CAMERA_PERMISSION_REQUEST', function(event) {
                console.log('Flutter: Received CAMERA_PERMISSION_REQUEST DOM event');
                if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                  window.flutter_inappwebview.callHandler('onCameraPermissionRequest', event.detail || {});
                }
              });

              document.addEventListener('ADD_ADDRESS_REQUEST', function(event) {
                console.log('Flutter: Received ADD_ADDRESS_REQUEST DOM event');
                var data = (event && event.detail) ? event.detail : {};
                if (data && data.type === 'ADD_ADDRESS_REQUEST' && data.trigger === 'AddAddress') {
                  if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                    window.flutter_inappwebview.callHandler('onLocationPermissionRequest', data);
                  }
                }
              });
              
              // Override console.log to catch any CAMERA_PERMISSION_REQUEST messages
              const originalLog = console.log;
              console.log = function(...args) {
                originalLog.apply(console, args);
                const message = args.join(' ');
                if (message.includes('CAMERA_PERMISSION_REQUEST')) {
                  try {
                    const data = JSON.parse(message);
                    if (data.type === 'CAMERA_PERMISSION_REQUEST' && window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                      window.flutter_inappwebview.callHandler('onCameraPermissionRequest', data);
                    }
                  } catch (e) {
                    // Not JSON, ignore
                  }
                }
              };
            })();
          ''',
          );
        },
        onLoadStart: (controller, url) async {
          final urlString = url.toString();
          debugPrint('TokenWebViewPage:onLoadStart: $urlString');

          // Parse URI once
          final requestUri = Uri.tryParse(urlString);

          // Handle navigation to same host with auth headers
          final host = requestUri?.host;

          if (host == widget.appUri.host) {
            final targetUrl = _homeUrl.toString();
            if (urlString == targetUrl ||
                urlString.startsWith('${widget.appUri.scheme}://${widget.appUri.host}/eand/')) {
              if (_lastHeaderUrl != urlString) {
                _lastHeaderUrl = urlString;
                debugPrint('TokenWebViewPage:loading with auth headers: $urlString');
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
        onPermissionRequest: (controller, request) async {
          // This handler works for both iOS and Android
          debugPrint('TokenWebViewPage:onPermissionRequest: resources=${request.resources}, origin=${request.origin}');

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
              debugPrint('TokenWebViewPage:Granting camera permission to WebView');
              return PermissionResponse(resources: request.resources, action: PermissionResponseAction.GRANT);
            } else if (cameraStatus.isPermanentlyDenied) {
              // Permission permanently denied - show dialog to open settings
              debugPrint('TokenWebViewPage:Camera permission permanently denied');
              if (mounted) {
                _showPermissionDeniedDialog();
              }
              return PermissionResponse(resources: request.resources, action: PermissionResponseAction.DENY);
            } else {
              // Permission not granted, request it now
              // This handles the case where WebView requests permission before JavaScript message is received
              debugPrint('TokenWebViewPage:Camera permission not granted, requesting now');
              final newStatus = await Permission.camera.request();
              if (newStatus.isGranted) {
                debugPrint('TokenWebViewPage:Camera permission granted, granting to WebView');
                return PermissionResponse(resources: request.resources, action: PermissionResponseAction.GRANT);
              } else if (newStatus.isPermanentlyDenied) {
                debugPrint('TokenWebViewPage:Camera permission permanently denied after request');
                if (mounted) {
                  _showPermissionDeniedDialog();
                }
                return PermissionResponse(resources: request.resources, action: PermissionResponseAction.DENY);
              } else {
                // Permission denied (but not permanently) - user can try again
                debugPrint('TokenWebViewPage:Camera permission denied (user can try again)');
                // On iOS, we might want to still grant to WebView as it will handle the system dialog
                // But for now, we'll deny and let the user try again
                return PermissionResponse(resources: request.resources, action: PermissionResponseAction.DENY);
              }
            }
          }

          // Grant other permissions
          debugPrint('TokenWebViewPage:Granting other permissions: ${request.resources}');
          return PermissionResponse(resources: request.resources, action: PermissionResponseAction.GRANT);
        },
        onConsoleMessage: (controller, consoleMessage) {
          final message = consoleMessage.message;
          debugPrint('TokenWebViewPage:onConsoleMessage: $message');
          if (message.contains('LOGOUT_REQUEST')) {
            debugPrint('TokenWebViewPage:Logout request detected, navigating to login');
            if (mounted) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const LoginPage()),
                (route) => false,
              );
            }
          }

          // Some pages log "ADD_ADDRESS_REQUEST [object Object]" instead of postMessage.
          // Trigger location permission from that console signal as well.
          if (message.contains('ADD_ADDRESS_REQUEST')) {
            _requestLocationPermissionIfNeeded();
          }
        },
      ),
    );
  }
}
