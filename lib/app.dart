import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/strings.dart';
import 'models/session.dart';
import 'state/remote_controller.dart';
import 'theme/app_theme.dart';
import 'ui/connect_screen.dart';
import 'ui/workspace_screen.dart';
import 'widgets/common.dart';

class RemoteApp extends StatefulWidget {
  const RemoteApp({super.key, required this.controller});

  final RemoteController controller;

  @override
  State<RemoteApp> createState() => _RemoteAppState();
}

class _RemoteAppState extends State<RemoteApp> with WidgetsBindingObserver {
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();
  late AppLanguage _language;
  late Locale _systemLocale;
  int _lastErrorSequence = 0;
  bool _restoreScheduled = false;

  RemoteController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _language = _controller.settings.language;
    _systemLocale = WidgetsBinding.instance.platformDispatcher.locale;
    WidgetsBinding.instance.addObserver(this);
    _controller.error.addListener(_showError);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: AppColors.background,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _restoreScheduled) return;
      _restoreScheduled = true;
      if (_controller.settings.autoReconnect) {
        _controller.restoreLastSession();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.error.removeListener(_showError);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _controller.onAppResumed();
    } else if (state == AppLifecycleState.paused) {
      _controller.onAppPaused();
    }
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    final next = WidgetsBinding.instance.platformDispatcher.locale;
    if (next != _systemLocale) {
      setState(() => _systemLocale = next);
    }
  }

  AppLanguage get _resolvedLanguage =>
      resolveLanguage(_language, _systemLocale);

  void _setLanguage(AppLanguage language) {
    setState(() => _language = language);
    _controller.setLanguage(language);
  }

  void _showError() {
    final error = _controller.error.value;
    if (error == null || error.sequence == _lastErrorSequence) return;
    _lastErrorSequence = error.sequence;
    final l10n = L10n.forLanguage(_resolvedLanguage);
    final messenger = _messengerKey.currentState;
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 18,
                color: AppColors.danger,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  friendlyCommandError(l10n, error),
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
            ],
          ),
          action: SnackBarAction(
            label: l10n.t('close'),
            textColor: AppColors.accent,
            onPressed: () => messenger.hideCurrentSnackBar(),
          ),
          duration: const Duration(seconds: 5),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final resolved = _resolvedLanguage;
    final l10n = L10n.forLanguage(resolved);
    final locale = switch (resolved) {
      AppLanguage.spanish => const Locale('es'),
      AppLanguage.japanese => const Locale('ja'),
      _ => const Locale('en'),
    };

    return L10nScope(
      l10n: l10n,
      language: _language,
      onLanguageChanged: _setLanguage,
      child: MaterialApp(
        title: 'EZ Remote',
        debugShowCheckedModeBanner: false,
        scaffoldMessengerKey: _messengerKey,
        theme: buildAppTheme(),
        locale: locale,
        supportedLocales: const [Locale('en'), Locale('es'), Locale('ja')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: _RootGate(
          controller: _controller,
          language: _language,
          onLanguageChanged: _setLanguage,
        ),
      ),
    );
  }
}

class _RootGate extends StatelessWidget {
  const _RootGate({
    required this.controller,
    required this.language,
    required this.onLanguageChanged,
  });

  final RemoteController controller;
  final AppLanguage language;
  final ValueChanged<AppLanguage> onLanguageChanged;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: controller.connection,
      builder: (context, connection, _) {
        return ValueListenableBuilder(
          valueListenable: controller.project,
          builder: (context, project, _) {
            final showWorkspace =
                connection.isConnected ||
                (project != null &&
                    connection.phase != ConnectionPhase.authFailed);
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child:
                  showWorkspace
                      ? WorkspaceScreen(
                        key: const ValueKey('workspace'),
                        controller: controller,
                        language: language,
                        onLanguageChanged: onLanguageChanged,
                      )
                      : ConnectScreen(
                        key: const ValueKey('connect'),
                        controller: controller,
                        language: language,
                        onLanguageChanged: onLanguageChanged,
                      ),
            );
          },
        );
      },
    );
  }
}
