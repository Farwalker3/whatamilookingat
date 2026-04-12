import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../theme/app_theme.dart';

/// Settings screen for API key management and preferences.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _geminiController;
  late TextEditingController _groqController;
  late TextEditingController _openrouterController;
  late TextEditingController _newsController;
  bool _showKeys = false;

  @override
  void initState() {
    super.initState();
    _geminiController = TextEditingController(
      text: dotenv.env['GEMINI_API_KEY'] ?? '',
    );
    _groqController = TextEditingController(
      text: dotenv.env['GROQ_API_KEY'] ?? '',
    );
    _openrouterController = TextEditingController(
      text: dotenv.env['OPENROUTER_API_KEY'] ?? '',
    );
    _newsController = TextEditingController(
      text: dotenv.env['NEWS_API_KEY'] ?? '',
    );
  }

  @override
  void dispose() {
    _geminiController.dispose();
    _groqController.dispose();
    _openrouterController.dispose();
    _newsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // API Keys Section
          _buildSectionHeader('AI Providers', Icons.smart_toy_rounded),
          const SizedBox(height: 8),
          _buildInfoCard(
            'The app rotates between multiple AI providers to avoid '
            'draining any single account. Configure as many as you can '
            'for the best experience.',
            icon: Icons.info_outline_rounded,
            color: AppTheme.primary,
          ),
          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () => setState(() => _showKeys = !_showKeys),
                icon: Icon(
                  _showKeys ? Icons.visibility_off : Icons.visibility,
                  size: 16,
                ),
                label: Text(_showKeys ? 'Hide keys' : 'Show keys'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.textMuted,
                ),
              ),
            ],
          ),

          _buildApiKeyField(
            'Gemini API Key',
            _geminiController,
            'aistudio.google.com',
            '15 RPM, best quality',
          ),
          _buildApiKeyField(
            'Groq API Key',
            _groqController,
            'console.groq.com',
            '30 RPM, fastest speed',
          ),
          _buildApiKeyField(
            'OpenRouter API Key',
            _openrouterController,
            'openrouter.ai',
            'Free models, no credit card',
          ),

          const SizedBox(height: 24),
          _buildSectionHeader('News', Icons.newspaper_rounded),
          const SizedBox(height: 8),
          _buildApiKeyField(
            'NewsData.io API Key',
            _newsController,
            'newsdata.io',
            '200 req/day, local news',
          ),

          const SizedBox(height: 24),
          _buildSectionHeader('About', Icons.info_rounded),
          const SizedBox(height: 8),
          _buildInfoCard(
            'What Am I Looking At? v1.0.0\n\n'
            'An AI-powered smart camera that explains what you see '
            'using your device\'s camera, location, local news, and '
            'multiple AI providers.\n\n'
            'All AI processing is done via free API tiers. No data '
            'is stored on external servers beyond what the AI APIs '
            'require for processing.',
            icon: Icons.camera_rounded,
            color: AppTheme.secondary,
          ),

          const SizedBox(height: 24),
          _buildInfoCard(
            '⚠️ Note: API keys entered here are stored only on this device. '
            'For production use, keys should be configured in the .env file '
            'before building the app.',
            icon: Icons.security_rounded,
            color: AppTheme.warning,
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.primary, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildApiKeyField(
    String label,
    TextEditingController controller,
    String hint,
    String description,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.glassBorder, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: controller.text.isNotEmpty
                        ? AppTheme.accent.withOpacity(0.15)
                        : AppTheme.error.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    controller.text.isNotEmpty ? 'Configured' : 'Missing',
                    style: TextStyle(
                      color: controller.text.isNotEmpty
                          ? AppTheme.accent
                          : AppTheme.error,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              obscureText: !_showKeys,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 13,
                fontFamily: 'monospace',
              ),
              decoration: InputDecoration(
                hintText: 'Get from $hint',
                hintStyle: const TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 12,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                filled: true,
                fillColor: AppTheme.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppTheme.glassBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppTheme.glassBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppTheme.primary),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(String text,
      {required IconData icon, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color.withOpacity(0.9),
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
