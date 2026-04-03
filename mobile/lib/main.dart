import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'backend.dart';
import 'login_screen.dart';
import 'notes_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final storedToken = prefs.getString('auth_token');
  final storedServerUrl = prefs.getString('server_url');
  runApp(MainApp(initialToken: storedToken, initialServerUrl: storedServerUrl));
}

class MainApp extends StatefulWidget {
  final String? initialToken;
  final String? initialServerUrl;

  const MainApp({super.key, this.initialToken, this.initialServerUrl});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  BackendClient? _client;
  String? _token;

  @override
  void initState() {
    super.initState();
    _token = widget.initialToken;
    if (_token != null && widget.initialServerUrl != null) {
      _client = BackendClient(
        baseUrl: widget.initialServerUrl!,
        token: _token,
        onUnauthorized: _onLoggedOut,
      );
    }
  }

  void _onLoggedIn(String token, String serverUrl) {
    setState(() {
      _token = token;
      _client = BackendClient(
        baseUrl: serverUrl,
        token: token,
        onUnauthorized: _onLoggedOut,
      );
    });
  }

  Future<void> _onLoggedOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    setState(() {
      _token = null;
      _client = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      builder: (context, child) => SafeArea(child: child!),
      home: _token == null
          ? LoginScreen(
              initialServerUrl: widget.initialServerUrl,
              onLoggedIn: _onLoggedIn,
            )
          : NotesScreen(client: _client!, onLoggedOut: _onLoggedOut),
    );
  }
}
