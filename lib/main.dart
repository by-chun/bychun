import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme/app_theme.dart';
import 'state/theme_controller.dart';
import 'shell.dart';
import 'agent/music_handler.dart';
import 'pages/video_page.dart';
import 'agent/tools_overlay.dart';
import 'native/native_bridge.dart';
import 'state/active_session.dart';
import 'floating/floating_chat_app.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Colors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  try {
    await initAudioService();
  } catch (e) {
    debugPrint('audio service init failed: $e');
  }
  OverlayBridge.init();
  OverlayBridge.subscribeOutput();
  // 恢复上次打开的会话
  try {
    final raw = await NativeBridge.readAppFile('last_session');
    final id = int.tryParse((raw ?? '').trim());
    if (id != null) ActiveSessionNotifier.seed(id);
  } catch (_) {}
  // 预载液态玻璃着色器，避免首帧白闪/卡顿
  await LiquidGlassWidgets.initialize();
  runApp(LiquidGlassWidgets.wrap(
    brightnessResolver: Theme.maybeBrightnessOf,
    child: const ProviderScope(child: RowanApp()),
  ));
}

/// 第二个 Flutter 引擎的入口：渲染灵动岛悬浮窗。
@pragma('vm:entry-point')
void floatingChatMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(backgroundColor: Colors.transparent, body: FloatingChatApp()),
  ));
}

class RowanApp extends ConsumerWidget {
  const RowanApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seed = ref.watch(themeColorProvider);
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: 'Rowan',
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
        ).copyWith(primary: seed, surface: Colors.white),
        scaffoldBackgroundColor: AppColors.bg,
        splashFactory: InkSparkle.splashFactory,
        dialogTheme: DialogThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 18,
          insetPadding: const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          titleTextStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text),
          contentTextStyle: const TextStyle(fontSize: 13, color: AppColors.text, height: 1.5),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF4F6FA),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.brand, width: 1.4)),
          labelStyle: const TextStyle(fontSize: 12.5, color: AppColors.muted),
          floatingLabelStyle: const TextStyle(fontSize: 12, color: AppColors.brand),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: AppColors.text,
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.brand,
            backgroundColor: const Color(0xFFF1F4F8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.brand,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
        pageTransitionsTheme: const PageTransitionsTheme(builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        }),
      ),
      scrollBehavior: const _BouncyScrollBehavior(),
      home: const Shell(),
    );
  }
}

/// 列表滚动带弹性（Q 弹）效果。
class _BouncyScrollBehavior extends MaterialScrollBehavior {
  const _BouncyScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) => const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      );
}
