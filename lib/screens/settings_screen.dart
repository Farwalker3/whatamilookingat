import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/analysis_provider.dart';
import '../theme/app_theme.dart';

/// Settings screen for preferences.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _newsController;

  @override
  void initState() {
    super.initState();
    _newsController = TextEditingController();
    _loadNewsKey();
  }

  Future<void> _loadNewsKey() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('NEWS_API_KEY');
    if (saved != null) {
      _newsController.text = saved;
    }
    setState(() {});
  }

  @override
  void dispose() {
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
          _buildSectionHeader('AI Providers', Icons.smart_toy_rounded),
          const SizedBox(height: 8),
          _buildInfoCard(
            'Cloud AI calls now go through the shared Vercel proxy. No API keys are required in the app setup flow.',
            icon: Icons.cloud_done_rounded,
            color: AppTheme.primary,
          ),

          const SizedBox(height: 24),
          _buildSectionHeader('News', Icons.newspaper_rounded),
          const SizedBox(height: 8),
          _buildApiKeyField(
            'NewsData.io API Key',
            _newsController,
            'newsdata.io',
            '200 req/day, local news',
            'NEWS_API_KEY',
          ),

          const SizedBox(height: 24),
          _buildSectionHeader('Features', Icons.auto_awesome_rounded),
          const SizedBox(height: 8),
          Consumer<AnalysisProvider>(
            builder: (context, provider, _) => SwitchListTile(
              title: const Text(
                'Live AR Bounds (Beta)',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                'Draws real-time computer vision boundaries over objects. Uses more battery.',
                style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 13),
              ),
              value: provider.isARModeEnabled,
              onChanged: (val) => provider.toggleARMode(),
              activeColor: AppTheme.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              tileColor: Colors.white.withAlpha(10),
            ),
          ),

          const SizedBox(height: 24),
          _buildSectionHeader('About', Icons.info_rounded),
          const SizedBox(height: 8),
          _buildInfoCard(
            'What Am I Looking At? v1.0.0\n\n'
            'An AI-powered smart camera that explains what you see using your device\'s camera, location, local news, and cloud AI through a Vercel proxy.\n\n'
            'AI provider credentials are managed server-side, so the app works without manual setup for those keys.',
            icon: Icons.camera_rounded,
            color: AppTheme.secondary,
          ),

          const SizedBox(height: 24),
          _buildInfoCard(
            'Only the NewsData.io key remains optional in settings. Cloud AI credentials are not stored on the device.',
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
    String storageKey,
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
                        ? AppTheme.accent.withValues(alpha: 0.15)
                        : AppTheme.error.withValues(alpha: 0.15),
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
              obscureText: false,
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
              onChanged: (val) async {
                setState(() {});
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString(storageKey, val);
              },
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
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
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
                color: color.withValues(alpha: 0.9),
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
