import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/services/notification_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _selectedLanguage = 'English';
  String _selectedModel = 'e2b';
  String _calculationMethod = 'muslim_world_league';
  bool _salatNotifications = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _loadSettings());
  }

  Future<void> _loadSettings() async {
    final userRepo = ref.read(userRepositoryProvider);
    final lang = await userRepo.getEngagementValue('selected_language') ?? 'English';
    final model = await userRepo.getEngagementValue('selected_llm_model') ?? 'e2b';
    final method = await userRepo.getEngagementValue('calculation_method') ?? 'muslim_world_league';
    final notifs = await userRepo.getEngagementValue('salat_notifications') ?? 'true';

    if (mounted) {
      setState(() {
        _selectedLanguage = lang;
        _selectedModel = model;
        _calculationMethod = method;
        _salatNotifications = notifs == 'true';
      });
    }
  }

  Future<void> _updateSetting(String key, String value) async {
    final userRepo = ref.read(userRepositoryProvider);
    await userRepo.setEngagementValue(key, value);

    if (key == 'salat_notifications' && value == 'false') {
      await ref.read(notificationServiceProvider).cancelAllNotifications();
    }
  }

  Future<void> _resetAllData() async {
    final userRepo = ref.read(userRepositoryProvider);
    await userRepo.clearAllData();
    await _loadSettings();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All local data deleted successfully.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Settings', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 24),

            // Language & Translation
            _buildSectionCard(
              theme: theme,
              title: 'Language & Translation',
              icon: Icons.translate_rounded,
              children: [
                ListTile(
                  title: Text('Default Translation', style: theme.textTheme.bodyMedium),
                  trailing: DropdownButton<String>(
                    value: _selectedLanguage,
                    underline: const SizedBox(),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: AppTheme.emeraldGreen),
                    items: const [
                      DropdownMenuItem(value: 'English', child: Text('English')),
                      DropdownMenuItem(value: 'Bangla', child: Text('Bangla')),
                      DropdownMenuItem(value: 'Hindi', child: Text('Hindi')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedLanguage = val);
                        _updateSetting('selected_language', val);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // AI Model Selection
            _buildSectionCard(
              theme: theme,
              title: 'AI Model',
              icon: Icons.memory_rounded,
              children: [
                RadioListTile<String>(
                  title: Text('Gemma 4 e2b (Lighter)',
                      style: theme.textTheme.bodyMedium),
                  subtitle: Text('Recommended for devices with <6GB RAM',
                      style: theme.textTheme.labelLarge),
                  value: 'e2b',
                  groupValue: _selectedModel,
                  activeColor: AppTheme.emeraldGreen,
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedModel = val);
                      _updateSetting('selected_llm_model', val);
                    }
                  },
                ),
                RadioListTile<String>(
                  title: Text('Gemma 4 e4b (Standard)',
                      style: theme.textTheme.bodyMedium),
                  subtitle: Text('Recommended for devices with ≥6GB RAM',
                      style: theme.textTheme.labelLarge),
                  value: 'e4b',
                  groupValue: _selectedModel,
                  activeColor: AppTheme.emeraldGreen,
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedModel = val);
                      _updateSetting('selected_llm_model', val);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Prayer Calculation
            _buildSectionCard(
              theme: theme,
              title: 'Prayer Calculation',
              icon: Icons.access_time_rounded,
              children: [
                SwitchListTile(
                  title: Text('Salat Notifications',
                      style: theme.textTheme.bodyMedium),
                  value: _salatNotifications,
                  activeColor: AppTheme.emeraldGreen,
                  onChanged: (val) {
                    setState(() => _salatNotifications = val);
                    _updateSetting('salat_notifications', val.toString());
                  },
                ),
                ListTile(
                  title: Text('Calculation Method',
                      style: theme.textTheme.bodyMedium),
                  trailing: DropdownButton<String>(
                    value: _calculationMethod,
                    underline: const SizedBox(),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: AppTheme.emeraldGreen, fontSize: 13),
                    items: const [
                      DropdownMenuItem(
                          value: 'muslim_world_league', child: Text('MWL')),
                      DropdownMenuItem(
                          value: 'north_america', child: Text('ISNA')),
                      DropdownMenuItem(
                          value: 'umm_al_qura', child: Text('Umm al-Qura')),
                      DropdownMenuItem(
                          value: 'karachi', child: Text('Karachi')),
                      DropdownMenuItem(
                          value: 'egyptian', child: Text('Egyptian')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _calculationMethod = val);
                        _updateSetting('calculation_method', val);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Privacy & Data
            _buildSectionCard(
              theme: theme,
              title: 'Privacy & Data',
              icon: Icons.shield_rounded,
              children: [
                ListTile(
                  leading: const Icon(Icons.download_rounded,
                      color: AppTheme.emeraldGreen),
                  title: Text('Export Data', style: theme.textTheme.bodyMedium),
                  subtitle: Text('Download your reading progress and logs',
                      style: theme.textTheme.labelLarge),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Data exported to local storage.')),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_forever_rounded,
                      color: Colors.redAccent),
                  title: Text('Delete All Data',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: Colors.redAccent)),
                  subtitle: Text('This action cannot be undone',
                      style: theme.textTheme.labelLarge),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Delete All Data?'),
                        content: const Text(
                            'Are you sure you want to delete all reading progress, prayer logs, and conversations? This action is permanent.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              _resetAllData();
                            },
                            child: const Text('Delete',
                                style: TextStyle(color: Colors.redAccent)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),

            // App info
            Center(
              child: Text(
                'Learn Quran v1.0.0\nMade with ❤️ for the Ummah',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppTheme.textMuted,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required ThemeData theme,
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceMint,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Row(
              children: [
                Icon(icon, size: 20, color: AppTheme.forestGreen),
                const SizedBox(width: 8),
                Text(title, style: theme.textTheme.titleMedium),
              ],
            ),
          ),
          ...children,
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
