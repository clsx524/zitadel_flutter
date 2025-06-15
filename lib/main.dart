import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_appauth/flutter_appauth.dart';

/// Zitadel url + client id.
/// you can replace String.fromEnvironment(*) calls with the actual values
/// if you don't want to pass them dynamically.
final zitadelIssuer = const String.fromEnvironment('zitadel_url');
const zitadelClientId = String.fromEnvironment('zitadel_client_id');

/// This should be the app's bundle id.
const callbackUrlScheme = 'com.zitadel.zitadelflutter';

/// Platform-specific redirect URIs
/// Mobile: Custom URL schemes work
/// Web: Need actual HTTP URLs that browsers can navigate to
final redirectUri = kIsWeb 
    ? 'http://localhost:4444/auth.html' 
    : '$callbackUrlScheme://oauth';

final postLogoutRedirectUri = kIsWeb 
    ? 'http://localhost:4444/logout.html' 
    : '$callbackUrlScheme://logout';

/// Create FlutterAppAuth instance
final FlutterAppAuth appAuth = FlutterAppAuth();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Flutter ZITADEL Quickstart'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  bool _busy = false;
  Object? latestError;
  AuthorizationTokenResponse? _tokenResponse;

  /// Test if there is a logged in user.
  bool get _authenticated => _tokenResponse != null;

  /// To get the access token.
  String? get accessToken => _tokenResponse?.accessToken;

  /// To get the id token.
  String? get idToken => _tokenResponse?.idToken;

  /// To access the claims (simplified - you would need to decode the JWT to get proper claims).
  String? get _username {
    // In a real implementation, you would decode the JWT token to get claims
    // For now, we'll just show that we're authenticated
    return _authenticated ? 'User' : null;
  }

  Future<void> _authenticate() async {
    setState(() {
      latestError = null;
      _busy = true;
    });
    
    try {
      print('=== STARTING AUTHENTICATION ===');
      print('Client ID: $zitadelClientId');
      print('Issuer: $zitadelIssuer');
      print('Redirect URI: $redirectUri');
      
      // Create the discovery URL
      final discoveryUrl = '$zitadelIssuer/.well-known/openid-configuration';
      
      // Perform authorization and code exchange
      final result = await appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          zitadelClientId,
          redirectUri,
          discoveryUrl: discoveryUrl,
          scopes: ['openid', 'profile', 'email', 'offline_access'],
          allowInsecureConnections: false,
        ),
      );
      
      setState(() {
        _tokenResponse = result;
      });
      
      print('Login successful!');
      print('Access Token: ${result.accessToken}');
      print('ID Token: ${result.idToken}');
      print('Refresh Token: ${result.refreshToken}');
      
    } on FlutterAppAuthUserCancelledException {
      print('User cancelled the authentication');
      // Don't set this as an error since user cancellation is expected behavior
      setState(() {
        latestError = null;
      });
      // Show a brief message to acknowledge the cancellation
      _showSnackBar('Login cancelled');
    } on FlutterAppAuthPlatformException catch (e) {
      print('=== AUTHENTICATION ERROR ===');
      print('Error type: ${e.runtimeType}');
      print('Error message: ${e.message}');
      print('Error code: ${e.code}');
      print('Error details: ${e.details}');
      setState(() {
        latestError = Exception('Authentication failed: ${e.message}');
      });
    } catch (e) {
      print('=== AUTHENTICATION ERROR ===');
      print('Error type: ${e.runtimeType}');
      print('Error message: $e');
      print('Error details: ${e.toString()}');
      setState(() {
        latestError = Exception('Authentication failed: ${e.toString()}');
      });
    }
    
    setState(() {
      _busy = false;
    });
  }

  Future<void> _logout() async {
    setState(() {
      latestError = null;
      _busy = true;
    });
    
    try {
      // Store current token response before clearing it
      final currentTokenResponse = _tokenResponse;
      
      // Clear local state first
      setState(() {
        _tokenResponse = null;
      });
      
      print('Local logout successful!');
      
      // Now try server-side logout if we have an ID token
      if (currentTokenResponse?.idToken != null) {
        try {
          final discoveryUrl = '$zitadelIssuer/.well-known/openid-configuration';
          await appAuth.endSession(
            EndSessionRequest(
              idTokenHint: currentTokenResponse!.idToken!,
              postLogoutRedirectUrl: postLogoutRedirectUri,
              discoveryUrl: discoveryUrl,
              allowInsecureConnections: false,
            ),
          );
          print('Server-side logout also completed');
          _showSnackBar('Logged out successfully (server-side)');
        } on FlutterAppAuthUserCancelledException {
          print('User cancelled the server-side logout');
          _showSnackBar('Logged out locally (server logout cancelled)');
        } catch (serverLogoutError) {
          print('Server-side logout failed (but local logout succeeded): $serverLogoutError');
          _showSnackBar('Logged out locally (server logout failed)');
        }
      } else {
        _showSnackBar('Logged out successfully');
      }
      
    } catch (e) {
      print('Logout error: $e');
      setState(() {
        latestError = Exception('Logout failed: ${e.toString()}');
      });
    }
    
    setState(() {
      _busy = false;
    });
  }

  Future<void> _refreshToken() async {
    if (_tokenResponse?.refreshToken == null) {
      print('No refresh token available');
      return;
    }
    
    setState(() {
      latestError = null;
      _busy = true;
    });
    
    try {
      // Create the discovery URL
      final discoveryUrl = '$zitadelIssuer/.well-known/openid-configuration';
      
      // Refresh the token
      final result = await appAuth.token(
        TokenRequest(
          zitadelClientId,
          redirectUri,
          discoveryUrl: discoveryUrl,
          refreshToken: _tokenResponse!.refreshToken!,
          scopes: ['openid', 'profile', 'email', 'offline_access'],
          allowInsecureConnections: false,
        ),
      );
      
      setState(() {
        _tokenResponse = AuthorizationTokenResponse(
          result.accessToken,
          result.refreshToken,
          result.accessTokenExpirationDateTime,
          result.idToken,
          result.tokenType,
          null, // scopes not available in TokenResponse 
          null, // authorizationAdditionalParameters not available in TokenResponse
          result.tokenAdditionalParameters,
        );
      });
      
      print('Token refresh successful!');
      print('New Access Token: ${result.accessToken}');
      _showSnackBar('Token refreshed successfully');
    } on FlutterAppAuthUserCancelledException {
      print('User cancelled the token refresh');
      setState(() {
        latestError = null;
      });
      _showSnackBar('Token refresh cancelled');
    } catch (e) {
      print('Token refresh error: $e');
      setState(() {
        latestError = Exception('Token refresh failed: ${e.toString()}');
      });
    }
    
    setState(() {
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (latestError != null)
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Icon(Icons.error, color: Colors.red),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.red),
                          onPressed: () {
                            setState(() {
                              latestError = null;
                            });
                          },
                          tooltip: 'Dismiss error',
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Error: ${latestError.toString()}',
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            else ...[
              if (_busy)
                const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text("Processing request..."),
                    Padding(
                      padding: EdgeInsets.all(16.0),
                      child: CircularProgressIndicator(),
                    ),
                  ],
                )
              else ...[
                if (_authenticated) ...[
                  const Icon(
                    Icons.check_circle,
                    color: Colors.green,
                    size: 64,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Hello $_username!',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text('You are successfully authenticated.'),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: const Text('Refresh Token'),
                        onPressed: _refreshToken,
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.logout),
                        label: const Text('Logout'),
                        onPressed: _logout,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  if (_tokenResponse != null) ...[
                    const SizedBox(height: 24),
                    ExpansionTile(
                      title: const Text('Token Information'),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildTokenInfo('Access Token', _tokenResponse!.accessToken),
                              _buildTokenInfo('ID Token', _tokenResponse!.idToken),
                              _buildTokenInfo('Refresh Token', _tokenResponse!.refreshToken),
                              if (_tokenResponse!.accessTokenExpirationDateTime != null)
                                _buildTokenInfo('Expires At', _tokenResponse!.accessTokenExpirationDateTime.toString()),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ] else ...[
                  const Icon(
                    Icons.lock_outline,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'You are not authenticated.',
                    style: TextStyle(fontSize: 18),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('Login'),
                    onPressed: _authenticate,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    ),
                  ),
                ],
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTokenInfo(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              value ?? 'N/A',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'OK',
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }
}
