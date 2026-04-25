// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.


import 'package:flutter_test/flutter_test.dart';

import 'package:whatamilookingat/main.dart';
import 'package:provider/provider.dart';
import 'package:whatamilookingat/providers/analysis_provider.dart';
import 'package:whatamilookingat/services/ai_rotation_manager.dart';
import 'package:whatamilookingat/services/location_service.dart';
import 'package:whatamilookingat/services/news_service.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    final locationService = LocationService();
    final newsService = NewsService(apiKey: '');
    final aiManager = AIRotationManager();
    aiManager.initialize(geminiKey: '', groqKey: '', openRouterKey: '');

    await tester.pumpWidget(
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

    expect(find.text('Initializing camera...'), findsOneWidget);
  });
}
