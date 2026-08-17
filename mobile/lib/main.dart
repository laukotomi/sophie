import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:sophie/services/alerts.dart';
import 'package:sophie/services/backend.dart';
import 'package:sophie/screens/home_screen.dart';
import 'package:sophie/screens/login_screen.dart';
import 'package:sophie/services/storage.dart';

final getIt = GetIt.instance;
final navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final locale = WidgetsBinding.instance.platformDispatcher.locale.toString();
  Intl.defaultLocale = locale;
  await initializeDateFormatting(locale);

  await Storage.init();

  if (!kIsWeb) {
    await Alerts.init();
  }

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
  String? _token;
  bool _offlineMode = false;

  @override
  void initState() {
    super.initState();
    _token = widget.initialToken;
    if (_token != null && widget.initialServerUrl != null) {
      _onLoggedIn(_token!, widget.initialServerUrl!);
    }

    if (!kIsWeb) {
      Alerts.requestPermissions();
    }
  }

  Future _onLoggedIn(String token, String serverUrl) async {
    if (token.isNotEmpty) {
      final client = BackendClient(baseUrl: serverUrl, token: token);
      getIt.registerSingleton(client);
      getIt.registerSingleton(client.note);
      getIt.registerSingleton(client.task);
      getIt.registerSingleton(client.noteFile);
    }

    setState(() {
      _token = token;
      _offlineMode = token.isEmpty;
    });
  }

  Future _onLoggedOut() async {
    await Storage.clear();
    getIt.reset();
    if (!kIsWeb) {
      Alerts.clear();
    }
    setState(() {
      _token = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      theme: ThemeData.dark(useMaterial3: true),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('en'), Locale('hu')],
      locale: Locale(
        WidgetsBinding.instance.platformDispatcher.locale.languageCode,
      ),
      builder: (context, child) {
        final safeChild = SafeArea(child: child!);

        if (!kIsWeb) {
          return safeChild;
        }

        return ColoredBox(
          color: const Color(0xFF0F141B),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: safeChild,
            ),
          ),
        );
      },
      home: _token == null
          ? LoginScreen(onLoggedIn: _onLoggedIn)
          : HomeScreen(onLoggedOut: _onLoggedOut, offlineMode: _offlineMode),
    );
  }
}
