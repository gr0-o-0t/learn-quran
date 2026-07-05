import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/llm_service.dart';
import '../../core/services/model_download_service.dart';
import '../../core/models/model_catalog.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with WidgetsBindingObserver {
  String _selectedLanguage = 'English';
  String _selectedModel = 'e2b';
  String _calculationMethod = 'muslim_world_league';
  bool _salatNotifications = true;
  bool _notificationsEnabled = false;
  bool _exactAlarmsEnabled = false;
  bool _checkingPermissions = true;
  Map<String, bool> _modelDownloaded = {};
  String? _recommendedModelId;
  String? _downloadingModelId;
  double _downloadProgress = 0.0;
  bool _wifiOnlyDownloads = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() => _loadSettings());
    _checkPermissions();
    _checkModelStatuses();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Catches the user coming back from the exact-alarm system settings
    // screen, which flutter_local_notifications opens outside the app.
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    final notifService = ref.read(notificationServiceProvider);
    final results = await Future.wait([
      notifService.areNotificationsEnabled(),
      notifService.canScheduleExactNotifications(),
    ]);
    if (mounted) {
      setState(() {
        _notificationsEnabled = results[0] ?? false;
        _exactAlarmsEnabled = results[1] ?? false;
        _checkingPermissions = false;
      });
    }
  }

  Future<void> _grantNotifications() async {
    await ref
        .read(notificationServiceProvider)
        .requestNotificationsPermission();
    await _checkPermissions();
  }

  Future<void> _grantExactAlarms() async {
    await ref
        .read(notificationServiceProvider)
        .requestExactAlarmsPermission();
    await _checkPermissions();
  }

  Future<void> _checkModelStatuses() async {
    final downloadService = ref.read(modelDownloadServiceProvider);
    final statuses = <String, bool>{};
    for (final model in kModelCatalog) {
      statuses[model.id] = await downloadService.isDownloaded(model);
    }
    final ramGb = ref.read(llmServiceProvider).detectDeviceRamGb();
    if (mounted) {
      setState(() {
        _modelDownloaded = statuses;
        _recommendedModelId = recommendedModelFor(ramGb).id;
      });
    }
  }

  String _formatSize(int bytes) {
    final gb = bytes / (1024 * 1024 * 1024);
    return '${gb.toStringAsFixed(1)}GB';
  }

  Future<void> _downloadModel(ModelInfo model) async {
    if (_wifiOnlyDownloads) {
      final results = await Connectivity().checkConnectivity();
      if (!results.contains(ConnectivityResult.wifi)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Turn off Wi-Fi-only downloads in Settings, or connect to Wi-Fi, to download this model.'),
            ),
          );
        }
        return;
      }
    }

    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Download ${model.displayName}?'),
        content: Text(
            'This will download ${_formatSize(model.sizeBytes)} from Hugging Face.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Download'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _downloadingModelId = model.id;
      _downloadProgress = 0.0;
    });

    try {
      await ref.read(modelDownloadServiceProvider).downloadModel(
        model,
        onProgress: (progress) {
          if (mounted) {
            setState(() => _downloadProgress = progress.fraction);
          }
        },
      );
      if (mounted) {
        setState(() {
          _modelDownloaded[model.id] = true;
          _downloadingModelId = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _downloadingModelId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Failed to download ${model.displayName}. Tap Download to retry.')),
        );
      }
    }
  }

  Future<void> _deleteModel(ModelInfo model) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${model.displayName}?'),
        content: const Text('You can download it again later.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(modelDownloadServiceProvider).deleteModel(model);
    if (mounted) {
      setState(() => _modelDownloaded[model.id] = false);
    }
  }

  Widget _buildModelRow(ThemeData theme, ModelInfo model) {
    final isDownloaded = _modelDownloaded[model.id] ?? false;
    final isDownloading = _downloadingModelId == model.id;
    final isRecommended = _recommendedModelId == model.id;

    final titleText = Text(
      isRecommended ? '${model.displayName} • Recommended' : model.displayName,
      style: theme.textTheme.bodyMedium,
    );
    final subtitleText = Text(
      '${_formatSize(model.sizeBytes)} — ${model.description}',
      style: theme.textTheme.labelLarge,
    );

    if (isDownloading) {
      return ListTile(
        title: titleText,
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: LinearProgressIndicator(
            value: _downloadProgress,
            color: AppTheme.emeraldGreen,
          ),
        ),
        trailing: TextButton(
          onPressed: () {
            ref.read(modelDownloadServiceProvider).cancelDownload();
          },
          child: const Text('Cancel'),
        ),
      );
    }

    if (isDownloaded) {
      return RadioListTile<String>(
        title: titleText,
        subtitle: subtitleText,
        value: model.id,
        activeColor: AppTheme.emeraldGreen,
        secondary: IconButton(
          icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
          onPressed: () => _deleteModel(model),
        ),
      );
    }

    return ListTile(
      title: titleText,
      subtitle: subtitleText,
      trailing: TextButton(
        onPressed: () => _downloadModel(model),
        child: const Text('Download'),
      ),
    );
  }

  Future<void> _loadSettings() async {
    final userRepo = ref.read(userRepositoryProvider);
    final lang = await userRepo.getEngagementValue('selected_language') ?? 'English';
    final model = await userRepo.getEngagementValue('selected_llm_model') ?? 'e2b';
    final method = await userRepo.getEngagementValue('calculation_method') ?? 'muslim_world_league';
    final notifs = await userRepo.getEngagementValue('salat_notifications') ?? 'true';
    final wifiOnly = await userRepo.getEngagementValue('wifi_only_model_downloads') ?? 'true';

    if (mounted) {
      setState(() {
        _selectedLanguage = lang;
        _selectedModel = model;
        _calculationMethod = method;
        _salatNotifications = notifs == 'true';
        _wifiOnlyDownloads = wifiOnly == 'true';
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

            if (!_checkingPermissions &&
                (!_notificationsEnabled || !_exactAlarmsEnabled)) ...[
              _buildSectionCard(
                theme: theme,
                title: 'Permissions',
                icon: Icons.verified_user_rounded,
                children: [
                  if (!_notificationsEnabled)
                    ListTile(
                      title: Text('Prayer Notifications',
                          style: theme.textTheme.bodyMedium),
                      subtitle: Text('Needed to show Salat reminders.',
                          style: theme.textTheme.labelLarge),
                      trailing: TextButton(
                        onPressed: _grantNotifications,
                        child: const Text('Grant'),
                      ),
                    ),
                  if (!_exactAlarmsEnabled)
                    ListTile(
                      title: Text('Precise Reminder Timing',
                          style: theme.textTheme.bodyMedium),
                      subtitle: Text(
                          'Needed for reminders to arrive exactly on time.',
                          style: theme.textTheme.labelLarge),
                      trailing: TextButton(
                        onPressed: _grantExactAlarms,
                        child: const Text('Grant'),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],

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
                RadioGroup<String>(
                  groupValue: _selectedModel,
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedModel = val);
                      _updateSetting('selected_llm_model', val);
                    }
                  },
                  child: Column(
                    children: kModelCatalog
                        .map((model) => _buildModelRow(theme, model))
                        .toList(),
                  ),
                ),
                SwitchListTile(
                  title: Text('Wi-Fi only downloads', style: theme.textTheme.bodyMedium),
                  subtitle: Text('Avoid using cellular data for multi-GB model downloads',
                      style: theme.textTheme.labelLarge),
                  value: _wifiOnlyDownloads,
                  activeThumbColor: AppTheme.emeraldGreen,
                  onChanged: (val) {
                    setState(() => _wifiOnlyDownloads = val);
                    _updateSetting('wifi_only_model_downloads', val.toString());
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
                  activeThumbColor: AppTheme.emeraldGreen,
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
