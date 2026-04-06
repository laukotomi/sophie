import 'package:flutter/material.dart';
import 'package:sophie/backend.dart';
import 'package:sophie/screens/login_screen.dart';
import 'package:sophie/screens/notes_screen.dart';
import 'package:sophie/services/download_notifications.dart';
import 'package:sophie/storage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Storage.init();
  await DownloadNotifications.init();
  runApp(
    MainApp(
      initialToken: Storage.authToken,
      initialServerUrl: Storage.serverUrl,
    ),
  );
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
    await Storage.clear();
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
