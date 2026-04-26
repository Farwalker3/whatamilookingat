import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatamilookingat/providers/analysis_provider.dart';
import 'package:whatamilookingat/screens/camera_screen.dart';
import 'package:whatamilookingat/services/ai_rotation_manager.dart';
import 'package:whatamilookingat/services/location_service.dart';
import 'package:whatamilookingat/services/news_service.dart';
import 'package:whatamilookingat/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    //  .env might not exist in all environments
  }

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  final prefs = await SharedPreferences.getInstance();

  final locationService = LocationService();
  final newsService = NewsService(
    apiKey: prefs.getString('NEWS_API_KEY') ?? dotenv.env['NEWS_API_KEY'] ?? '',
  );

  final aiManager = AIRotationManager();
  aiManager.initialize(
    proxyBaseUrl: dotenv.env['PROXY_BASE_URL'] ?? '/api/chat',
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AnalysisProvider(
            aiManager: aiManager,
            locationService: locationService,
            newsService: newsService,
          ),
        ),
      ],
      child: const WhatAmILookingAtApp(),
    ),
  );
}

class WhatAmILookingAtApp extends StatelessWidget {
  const WhatAmILookingAtApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'What Am I Looking At?',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const CameraScreen(),
    );
  }
}
