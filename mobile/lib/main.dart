import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:sophie/services/backend.dart';
import 'package:sophie/screens/home_screen.dart';
import 'package:sophie/screens/login_screen.dart';
import 'package:sophie/services/alert_notifications.dart';
import 'package:sophie/services/storage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final locale = Platform.localeName; // e.g. 'hu_HU'
  Intl.defaultLocale = locale;
  await initializeDateFormatting(locale);
  await Storage.init();
  await AlertNotifications.init();
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

    AlertNotifications.requestPermissions();
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
      navigatorKey: AlertNotifications.navigatorKey,
      theme: ThemeData.dark(useMaterial3: true),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('en'), Locale('hu')],
      locale: Locale(Platform.localeName.split('_').first),
      builder: (context, child) => SafeArea(child: child!),
      home: _token == null
          ? LoginScreen(
              initialServerUrl: widget.initialServerUrl,
              onLoggedIn: _onLoggedIn,
            )
          : HomeScreen(client: _client!, onLoggedOut: _onLoggedOut),
    );
  }
}
