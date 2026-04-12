import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'providers/analysis_provider.dart';
import 'services/ai_rotation_manager.dart';
import 'services/location_service.dart';
import 'services/news_service.dart';
import 'screens/camera_screen.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // .env might not exist in all environments
  }

  // Lock to portrait for camera
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Initialize services
  final locationService = LocationService();
  final newsService = NewsService(
    apiKey: dotenv.env['NEWS_API_KEY'] ?? '',
  );

  final aiManager = AIRotationManager();
  aiManager.initialize(
    geminiKey: dotenv.env['GEMINI_API_KEY'] ?? '',
    groqKey: dotenv.env['GROQ_API_KEY'] ?? '',
    openRouterKey: dotenv.env['OPENROUTER_API_KEY'] ?? '',
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
