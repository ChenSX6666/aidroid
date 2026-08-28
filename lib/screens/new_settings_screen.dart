import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/chat_provider.dart';
import '../models/ai_provider.dart';
import '../models/custom_ai_provider.dart';
import 'custom_provider_screen.dart';
import '../constants.dart';
import '../services/native_bridge.dart';
import '../services/shizuku_service.dart';
import '../services/log_service.dart';
import '../widgets/scenario_selector.dart';
import '../services/experience_service.dart';
import '../services/device_scan_service.dart';
import '../services/manual_memory_service.dart';
import '../services/tool_permission_service.dart';

class NewSettingsScreen extends StatefulWidget {
  const NewSettingsScreen({super.key});

  @override
  State<NewSettingsScreen> createState() => _NewSettingsScreenState();
}

class _NewSettingsScreenState extends State<NewSettingsScreen> {
  bool _agentUseVision = false;
  String _exportPath = '';
  Map<String, String>? _deviceInfo;
  Map<String, dynamic>? _scanResult;
  bool _scanning = false;
  bool _injectDeviceToAgent = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadDeviceInfo();
  }

  Future<void> _loadDeviceInfo() async {
    try {
      final info = await NativeBridge.getDeviceInfo();
      final arch = await NativeBridge.getArch();
      info['arch'] = arch;
      if (mounted) setState(() => _deviceInfo = info);
    } catch (_) {
      if (mounted) setState(() => _deviceInfo = {});
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _agentUseVision = prefs.getBool('agent_use_vision') ?? false;
      _exportPath = prefs.getString('export_path') ?? '';
      _injectDeviceToAgent = prefs.getBool('inject_device_to_agent') ?? false;
    });
    // Load persisted device scan result
    if (DeviceScanService.hasPersistedResult) {
      setState(() => _scanResult = DeviceScanService.cachedResult);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        backgroundColor: theme.scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        children: [
          _buildSection(theme, '模型配置', Icons.smart_toy, _buildProvidersSection()),
          _buildSection(theme, '手机操控', Icons.phone_android, _buildPhoneControlSection()),
          _buildSection(theme, '执行模式', Icons.settings_applications, _buildExecutionModeSection()),
          _buildSection(theme, '工具权限', Icons.gpp_good, _buildToolPermissionSection()),
          _buildSection(theme, '隐私模式', Icons.shield, _buildPrivacySection()),
          _buildSection(theme, '场景管理', Icons.flash_on, _buildScenarioSection()),
          _buildSection(theme, '自进化知识库', Icons.auto_awesome, _buildExperienceSection()),
          _buildSection(theme, '手动记忆', Icons.bookmark_outline, _buildManualMemorySection()),
          _buildSection(theme, '对话导出', Icons.file_download, _buildExportSection()),
          _buildSection(theme, '后台运行', Icons.settings_power, _buildBackgroundSection()),
          _buildSection(theme, '交流群聊', Icons.group, _buildQqGroupSection()),
          _buildSection(theme, '调试', Icons.bug_report, _buildDebugSection()),
          _buildSection(theme, '关于', Icons.videocam, _buildBilibiliSection()),
          _buildSection(theme, '捐赠支持', Icons.favorite, _buildDonationSection()),
          _buildSection(theme, '了解设备', Icons.phone_android, _buildDeviceScanSection()),
          _buildSection(theme, '系统信息', Icons.info_outline, _buildSystemSection()),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSection(ThemeData theme, String title, IconData icon, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        child,
        const Divider(height: 1, indent: 16, endIndent: 16),
      ],
    );
  }

  Widget _buildProvidersSection() {
    return Consumer<ChatProvider>(
      builder: (context, chat, _) {
        final custom = chat.allProviders.where((p) => p.id.startsWith(CustomAiProvider.idPrefix)).toList();
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _openCustomProvider(chat),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('添加自定义模型'),
                ),
              ),
            ),
            ...AiProvider.all.map((provider) {
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: provider.color,
                  radius: 18,
                  child: Text(provider.name[0], style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
                title: Text(provider.name, style: const TextStyle(fontSize: 14)),
                subtitle: Text(
                  provider.description,
                  style: const TextStyle(fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: FutureBuilder<String?>(
                  future: context.read<ChatProvider>().getApiKey(provider.id),
                  builder: (context, snapshot) {
                    final hasKey = snapshot.data?.isNotEmpty == true;
                    return Icon(
                      hasKey ? Icons.check_circle : Icons.radio_button_unchecked,
                      size: 20,
                      color: hasKey ? Colors.green : Colors.grey,
                    );
                  },
                ),
                onTap: () => _showApiKeyDialog(provider),
              );
            }).toList(),
            ...custom.map((p) {
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: p.color,
                  radius: 18,
                  child: Text(p.name[0], style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
                title: Text(p.name, style: const TextStyle(fontSize: 14)),
                subtitle: Text(
                  p.baseUrl,
                  style: const TextStyle(fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      onPressed: () => _editCustom(chat, p.id),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                      onPressed: () => _deleteCustom(chat, p.id),
                    ),
                  ],
                ),
                onTap: () => _showApiKeyDialog(p),
              );
            }),
          ],
        );
      },
    );
  }

  void _openCustomProvider(ChatProvider chat, {CustomAiProvider? existing}) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CustomProviderScreen(chat: chat, existing: existing)),
    );
  }

  Future<void> _editCustom(ChatProvider chat, String id) async {
    final customs = await CustomAiProvider.loadAll();
    CustomAiProvider? existing;
    for (final c in customs) {
      if (c.id == id) {
        existing = c;
        break;
      }
    }
    if (!mounted) return;
    _openCustomProvider(chat, existing: existing);
  }

  Future<void> _deleteCustom(ChatProvider chat, String id) async {
    final customs = await CustomAiProvider.loadAll();
    final matched = customs.where((c) => c.id == id).toList();
    if (matched.isEmpty) return;
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除自定义模型'),
        content: Text('确定删除「${matched.first.name}」吗？此操作不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    customs.removeWhere((c) => c.id == id);
    await CustomAiProvider.saveAll(customs);
    await chat.refreshCustomProviders();
  }

  Widget _buildToolPermissionSection() {
    const labels = {
      'shell': '执行 Shell 命令',
      'clear_data': '清除应用数据',
      'force_stop': '强制停止应用',
      'install_apk': '安装 APK',
      'settings_put': '修改系统设置',
      'broadcast': '发送广播',
      'grant_permission': '授予权限',
      'revoke_permission': '撤销权限',
    };
    const levelLabels = {
      ToolPermissionService.allow: '自动允许',
      ToolPermissionService.ask: '每次询问',
      ToolPermissionService.deny: '拒绝',
    };
    return FutureBuilder<Map<String, String>>(
      future: ToolPermissionService.getAllPermissions(),
      builder: (context, snapshot) {
        final perms = snapshot.data ?? {};
        return Column(
          children: ToolPermissionService.riskyTools.map((tool) {
            final level = perms[tool] ?? ToolPermissionService.ask;
            return ListTile(
              dense: true,
              title: Text(labels[tool] ?? tool, style: const TextStyle(fontSize: 13)),
              trailing: PopupMenuButton<String>(
                onSelected: (v) async {
                  await ToolPermissionService.setPermission(tool, v);
                  if (mounted) setState(() {});
                },
                itemBuilder: (_) => levelLabels.entries.map((e) {
                  return PopupMenuItem(
                    value: e.key,
                    child: Row(
                      children: [
                        Text(e.value, style: const TextStyle(fontSize: 13)),
                        if (e.key == level)
                          const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: Icon(Icons.check, size: 16, color: Color(0xFF0D7CB5)),
                          ),
                      ],
                    ),
                  );
                }).toList(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[400]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(levelLabels[level] ?? '每次询问', style: const TextStyle(fontSize: 12)),
                      const Icon(Icons.arrow_drop_down, size: 16),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildPhoneControlSection() {
    return FutureBuilder<bool>(
      future: NativeBridge.isAccessibilityEnabled(),
      builder: (context, snapshot) {
        final a11yEnabled = snapshot.data ?? false;
        return Column(
          children: [
            ListTile(
              title: const Text('无障碍服务', style: TextStyle(fontSize: 14)),
              subtitle: Text(
                a11yEnabled ? '已启用 — 支持点击、滑动、返回、桌面等操作' : '未启用 — 开启后可实现手机操控',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: Icon(
                a11yEnabled ? Icons.check_circle : Icons.error_outline,
                color: a11yEnabled ? Colors.green : Colors.orange,
                size: 20,
              ),
            ),
            if (!a11yEnabled)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => NativeBridge.openAccessibilitySettings(),
                    icon: const Icon(Icons.settings, size: 16),
                    label: const Text('打开无障碍设置'),
                  ),
                ),
              ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            SwitchListTile(
              title: const Text('Agent 截图模式', style: TextStyle(fontSize: 14)),
              subtitle: Text(
                _agentUseVision ? '截图 + 文本（需要视觉模型如 mimo-v2.5）' : '纯文本模式（适用所有模型）',
                style: const TextStyle(fontSize: 12),
              ),
              value: _agentUseVision,
              onChanged: (v) async {
                setState(() => _agentUseVision = v);
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('agent_use_vision', v);
                if (mounted) {
                  context.read<ChatProvider>().setAgentUseVision(v);
                }
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                _agentUseVision
                    ? '截图模式将当前屏幕截图发送给视觉模型，配合 UI 元素列表实现精准定位'
                    : '纯文本模式仅发送屏幕交互元素列表，token 消耗更少，适用所有模型',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            Consumer<ChatProvider>(
              builder: (context, chat, _) {
                return SwitchListTile(
                  title: const Text('Agent 执行策略', style: TextStyle(fontSize: 14)),
                  subtitle: Text(
                    chat.agentSpeedMode ? '速度优先 — 极简 prompt，最快响应' : '准确优先 — 策略丰富，验证反馈，更可靠',
                    style: const TextStyle(fontSize: 12),
                  ),
                  value: chat.agentSpeedMode,
                  onChanged: (v) => chat.setAgentSpeedMode(v),
                );
              },
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            Consumer<ChatProvider>(
              builder: (context, chat, _) {
                return SwitchListTile(
                  title: const Text('Agent 悬浮窗', style: TextStyle(fontSize: 14)),
                  subtitle: const Text('执行任务时显示进度悬浮球', style: TextStyle(fontSize: 12)),
                  value: chat.overlayEnabled,
                  onChanged: (v) => chat.setOverlayEnabled(v),
                );
              },
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            Consumer<ChatProvider>(
              builder: (context, chat, _) {
                return SwitchListTile(
                  title: const Text('OCR 屏幕增强', style: TextStyle(fontSize: 14)),
                  subtitle: const Text('本地 ML Kit 识别截图文字，补全 UI 树遗漏的内容（WebView、弹窗等）', style: TextStyle(fontSize: 12)),
                  value: chat.ocrEnabled,
                  onChanged: (v) => chat.setOcrEnabled(v),
                );
              },
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            Consumer<ChatProvider>(
              builder: (context, chat, _) {
                return SwitchListTile(
                  title: const Text('自动计划模式', style: TextStyle(fontSize: 14)),
                  subtitle: const Text('Agent 先分析屏幕制定分步计划，自动按场景开启/关闭视觉和 OCR', style: TextStyle(fontSize: 12)),
                  value: chat.autoPlanMode,
                  onChanged: (v) => chat.setAutoPlanMode(v),
                );
              },
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            Consumer<ChatProvider>(
              builder: (context, chat, _) {
                return SwitchListTile(
                  title: const Text('文件系统访问 (Agent)', style: TextStyle(fontSize: 14)),
                  subtitle: const Text('开启后 Agent 可读取设备文件辅助决策。默认关闭', style: TextStyle(fontSize: 12)),
                  value: chat.fileSystemAccess,
                  onChanged: (v) {
                    if (v) {
                      _showFileAccessPrivacyDialog(context, chat);
                    } else {
                      chat.setFileSystemAccess(false);
                    }
                  },
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildScenarioSection() {
    return FutureBuilder(
      future: ScenarioSelector.ensureLoaded().then((_) => ScenarioSelector.customScenarios.length),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        return Column(
          children: [
            ListTile(
              title: const Text('自定义场景', style: TextStyle(fontSize: 14)),
              subtitle: Text('$count 个自定义场景', style: const TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right, size: 20),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const SizedBox(width: 16),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final path = await ScenarioSelector.exportToFile();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('已导出到: $path')),
                        );
                      }
                    },
                    icon: const Icon(Icons.upload, size: 14),
                    label: const Text('导出', style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _importScenarios(),
                    icon: const Icon(Icons.download, size: 14),
                    label: const Text('导入', style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 8),
                if (count > 0)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('重置场景'),
                            content: const Text('确定要清除所有自定义场景吗？此操作不可恢复。'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                child: const Text('重置'),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          await ScenarioSelector.resetToDefault();
                          if (mounted) {
                            setState(() {});
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('已重置为默认场景')),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.refresh, size: 14, color: Colors.red),
                      label: const Text('重置', style: TextStyle(fontSize: 12, color: Colors.red)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  void _importScenarios() {
    final controller = TextEditingController(text: '/storage/emulated/0/Download/aidroid/');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入场景'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '输入备份文件路径',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              final path = controller.text.trim();
              if (path.isNotEmpty) {
                final count = await ScenarioSelector.importFromFile(path);
                if (mounted) {
                  Navigator.pop(ctx);
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已导入 $count 个场景')),
                  );
                }
              }
            },
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0D7CB5)),
            child: const Text('导入'),
          ),
        ],
      ),
    );
  }

  Widget _buildExperienceSection() {
    return FutureBuilder(
      future: ExperienceService.getStats(),
      builder: (context, snapshot) {
        final stats = snapshot.data;
        final fileCount = stats?.fileCount ?? 0;
        final totalSize = stats?.totalSize ?? '...';
        final lastUpdate = stats?.lastUpdate ?? '...';

        return Column(
          children: [
            SwitchListTile(
              title: const Text('自动记录操作经验', style: TextStyle(fontSize: 14)),
              subtitle: const Text('Agent 执行任务后自动生成知识库文档', style: TextStyle(fontSize: 12)),
              value: ExperienceService.recordingEnabled,
              onChanged: (v) {
                ExperienceService.setRecordingEnabled(v);
                setState(() {});
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface.withAlpha(80),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _statRow('知识库文件', '$fileCount 个'),
                    const SizedBox(height: 4),
                    _statRow('总大小', totalSize),
                    const SizedBox(height: 4),
                    _statRow('最近更新', lastUpdate),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const SizedBox(width: 16),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: fileCount > 0
                        ? () async {
                            final path = await ExperienceService.exportAll();
                            if (path.isNotEmpty && mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('已导出到: $path')),
                              );
                            }
                          }
                        : null,
                    icon: const Icon(Icons.upload, size: 14),
                    label: const Text('导出', style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _importKnowledge(),
                    icon: const Icon(Icons.download, size: 14),
                    label: const Text('导入', style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 8),
                if (fileCount > 0)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('清空知识库'),
                            content: const Text('确定要删除所有知识库文件吗？此操作不可恢复。'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                child: const Text('清空'),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          await ExperienceService.clearAll();
                          if (mounted) {
                            setState(() {});
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('知识库已清空')),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.delete_outline, size: 14, color: Colors.red),
                      label: const Text('清空', style: TextStyle(fontSize: 12, color: Colors.red)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  Widget _statRow(String label, String value) {
    return Row(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const Spacer(),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }

  void _importKnowledge() {
    final controller = TextEditingController(text: '/storage/emulated/0/Download/aidroid/');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入知识库'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '输入导出文件路径',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              final path = controller.text.trim();
              if (path.isNotEmpty) {
                final count = await ExperienceService.importFrom(File(path));
                if (mounted) {
                  Navigator.pop(ctx);
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已导入 $count 条记录')),
                  );
                }
              }
            },
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0D7CB5)),
            child: const Text('导入'),
          ),
        ],
      ),
    );
  }

  Widget _buildExportSection() {
    return Column(
      children: [
        ListTile(
          title: const Text('导出路径', style: TextStyle(fontSize: 14)),
          subtitle: Text(
            _exportPath.isEmpty
                ? '/storage/emulated/0/Download/aidroid/'
                : _exportPath,
            style: const TextStyle(fontSize: 11),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showExportPathDialog(),
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  void _showFileAccessPrivacyDialog(BuildContext context, ChatProvider chat) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('⚠️ 隐私提醒'),
        content: const Text(
          '开启后，Agent 将能够读取您设备上的文件内容，\n包括应用数据、下载文件、文档等。\n\n'
          '此功能依赖 root 权限。\n\n'
          '确认开启文件系统访问？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              chat.setFileSystemAccess(true);
            },
            child: const Text('确认开启'),
          ),
        ],
      ),
    );
  }

  void _showExportPathDialog() {
    final controller = TextEditingController(text: _exportPath);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导出路径'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '/storage/emulated/0/Download/aidroid',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final path = controller.text.trim();
              setState(() => _exportPath = path);
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('export_path', path);
              if (mounted) Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0D7CB5),
            ),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Widget _buildBackgroundSection() {
    return Column(
      children: [
        ListTile(
          title: const Text('电池优化', style: TextStyle(fontSize: 14)),
          subtitle: const Text('关闭电池优化以保持后台运行', style: TextStyle(fontSize: 12)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => NativeBridge.requestBatteryOptimization(),
        ),
      ],
    );
  }

  Widget _buildQqGroupSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () {
            Clipboard.setData(const ClipboardData(text: '696995105'));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('QQ群号 696995105 已复制'), duration: Duration(seconds: 1)),
            );
          },
          icon: const Icon(Icons.group, size: 18),
          label: const Text('QQ群: 696995105 — 点击复制群号'),
        ),
      ),
    );
  }

  Widget _buildDebugSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                final logs = LogService.dump();
                if (logs.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('暂无日志'), duration: Duration(seconds: 1)),
                  );
                } else {
                  Clipboard.setData(ClipboardData(text: logs));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已复制 ${logs.split('\n').length} 行日志'), duration: const Duration(seconds: 1)),
                  );
                }
              },
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('复制日志到剪贴板'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                LogService.clear();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('日志已清空'), duration: Duration(seconds: 1)),
                );
              },
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('清空日志'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFEF4444),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBilibiliSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => launchUrl(Uri.parse(AppConstants.bilibiliUrl)),
          icon: const Icon(Icons.open_in_new, size: 16),
          label: const Text('关注我的 Bilibili 频道'),
        ),
      ),
    );
  }

  Widget _buildExecutionModeSection() {
    return Consumer<ChatProvider>(
      builder: (context, chat, _) {
        final info = _deviceInfo ?? {};
        final isRooted = (info['rootStatus'] ?? '') == '已获取';
        final mode = chat.executionMode;

        return FutureBuilder<bool>(
          future: NativeBridge.isAccessibilityEnabled(),
          builder: (context, a11ySnapshot) {
            final a11yEnabled = a11ySnapshot.data ?? false;

            return Column(children: [
              RadioListTile<String>(
                title: Row(children: [
                  Icon(isRooted ? Icons.check_circle : Icons.cancel,
                      color: isRooted ? Colors.green : Colors.grey, size: 18),
                  const SizedBox(width: 8),
                  const Text('Root 模式', style: TextStyle(fontSize: 14)),
                ]),
                subtitle: Text(isRooted ? '通过 su 命令执行操作，速度最快' : '设备未 Root，不可用',
                    style: const TextStyle(fontSize: 12)),
                value: 'root',
                groupValue: mode,
                onChanged: isRooted ? (v) => chat.setExecutionMode(v!) : null,
              ),
              RadioListTile<String>(
                title: Row(children: [
                  Icon(a11yEnabled ? Icons.check_circle : Icons.error_outline,
                      color: a11yEnabled ? Colors.green : Colors.orange, size: 18),
                  const SizedBox(width: 8),
                  const Text('无障碍模式', style: TextStyle(fontSize: 14)),
                ]),
                subtitle: Text(a11yEnabled ? '通过 AccessibilityService 操作' : '未启用',
                    style: const TextStyle(fontSize: 12)),
                value: 'a11y',
                groupValue: mode,
                onChanged: (v) => chat.setExecutionMode(v!),
              ),
              if (!a11yEnabled)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: SizedBox(width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => NativeBridge.openAccessibilitySettings(),
                      icon: const Icon(Icons.settings, size: 16),
                      label: const Text('打开无障碍设置'),
                    ),
                  ),
                ),
              FutureBuilder<bool>(
                future: ShizukuService.checkAvailable(),
                builder: (context, shizukuSnapshot) {
                  final shizukuAvailable = shizukuSnapshot.data ?? false;
                  return RadioListTile<String>(
                    title: Row(children: [
                      Icon(shizukuAvailable ? Icons.check_circle : Icons.help_outline,
                          color: shizukuAvailable ? Colors.green : Colors.orange, size: 18),
                      const SizedBox(width: 8),
                      const Text('Shizuku 模式', style: TextStyle(fontSize: 14)),
                    ]),
                    subtitle: Text(shizukuAvailable
                        ? '通过 Shizuku ADB 权限执行，无需 Root'
                        : '需要安装 Shizuku 应用并通过 ADB 激活',
                        style: const TextStyle(fontSize: 12)),
                    value: 'shizuku',
                    groupValue: mode,
                    onChanged: (v) => chat.setExecutionMode(v!),
                  );
                },
              ),
              RadioListTile<String>(
                title: const Row(children: [
                  Icon(Icons.layers, color: Color(0xFF0D7CB5), size: 18),
                  SizedBox(width: 8),
                  Text('同时使用（推荐）', style: TextStyle(fontSize: 14)),
                ]),
                subtitle: const Text('Root 优先执行，失败时自动切换无障碍',
                    style: const TextStyle(fontSize: 12)),
                value: 'both',
                groupValue: mode,
                onChanged: (v) => chat.setExecutionMode(v!),
              ),
            ]);
          },
        );
      },
    );
  }

  Widget _buildPrivacySection() {
    return Consumer<ChatProvider>(
      builder: (context, chat, _) {
        return Column(children: [
          SwitchListTile(
            title: const Text('隐私模式', style: TextStyle(fontSize: 14)),
            subtitle: const Text('启用后助手会结合你手动添加的记忆提供个性化回复', style: TextStyle(fontSize: 12)),
            value: chat.privacyMode,
            onChanged: (v) => chat.setPrivacyMode(v),
          ),
        ]);
      },
    );
  }

  Widget _buildManualMemorySection() {
    final _memoryController = TextEditingController();
    return FutureBuilder<List<ManualMemory>>(
      future: ManualMemoryService.getAll(),
      builder: (context, snapshot) {
        final memories = snapshot.data ?? [];
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                '手动添加记忆条目，注入到助手回复和 Agent 任务中',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ),
            if (memories.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  '还没有记忆，添加一条试试',
                  style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                ),
              )
            else
              ...memories.map((m) {
                return ListTile(
                  dense: true,
                  title: Text(m.content, style: const TextStyle(fontSize: 13)),
                  subtitle: Text(m.createdAt,
                      style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () async {
                      await ManualMemoryService.removeMemory(m.id);
                      if (mounted) setState(() {});
                    },
                  ),
                );
              }).toList(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _memoryController,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: '输入记忆内容，如：我喜欢简洁的回复',
                        hintStyle: TextStyle(fontSize: 12, color: Colors.grey[500]),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () async {
                      final text = _memoryController.text.trim();
                      if (text.isEmpty) return;
                      await ManualMemoryService.addMemory(text);
                      _memoryController.clear();
                      if (mounted) setState(() {});
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    child: const Text('添加'),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDonationSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          const Text(
            '如果您觉得 Aidroid 对您有帮助，欢迎捐赠支持开发者的持续维护和功能迭代。',
            style: TextStyle(fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _launchAlipay(),
              icon: const Icon(Icons.favorite, size: 18, color: Color(0xFFEF4444)),
              label: const Text('捐赠支持', style: TextStyle(fontSize: 14)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: Color(0xFFEF4444)),
                foregroundColor: const Color(0xFFEF4444),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const _alipayScheme = 'alipays://platformapi/startapp?appId=20000067&url=https%3A%2F%2Fqr.alipay.com%2Ffkx10961a1iydhys1lli8b1';
  static const _alipayWeb = 'https://qr.alipay.com/fkx10961a1iydhys1lli8b1';

  Future<void> _launchAlipay() async {
    try {
      final launched = await launchUrl(
        Uri.parse(_alipayScheme),
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        await launchUrl(Uri.parse(_alipayWeb), mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      try {
        await launchUrl(Uri.parse(_alipayWeb), mode: LaunchMode.externalApplication);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('无法打开支付宝，请手动扫码捐赠')),
          );
        }
      }
    }
  }

  Widget _buildSystemSection() {
    final info = _deviceInfo;
    final isLoading = info == null;

    return Column(
      children: [
        ListTile(
          title: const Text('应用版本', style: TextStyle(fontSize: 14)),
          trailing: Text(
            AppConstants.version,
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
        ),
        if (isLoading)
          for (final label in ['设备型号', 'Android 版本', '屏幕分辨率', '内存 (RAM)', 'CPU', '设备架构', 'Root 状态', '无障碍服务', '执行模式'])
            ListTile(
              title: Text(label, style: const TextStyle(fontSize: 14)),
              trailing: Container(
                width: 80, height: 12,
                decoration: BoxDecoration(
                  color: Colors.grey.withAlpha(40),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            )
        else ...[
          ListTile(
            title: const Text('设备型号', style: TextStyle(fontSize: 14)),
            trailing: Text(
              '${info['manufacturer'] ?? ''} ${info['model'] ?? ''}',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ),
          ListTile(
            title: const Text('Android 版本', style: TextStyle(fontSize: 14)),
            trailing: Text(
              info['androidVersion'] ?? '未知',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ),
          ListTile(
            title: const Text('屏幕分辨率', style: TextStyle(fontSize: 14)),
            trailing: Text(
              '${info['screenWidth'] ?? '-'}×${info['screenHeight'] ?? '-'}  @${info['density'] ?? '-'}x',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ),
          ListTile(
            title: const Text('内存 (RAM)', style: TextStyle(fontSize: 14)),
            trailing: Text(
              '${info['ramMB'] ?? '未知'} MB',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ),
          ListTile(
            title: const Text('CPU', style: TextStyle(fontSize: 14)),
            trailing: Text(
              info['cpuHardware'] ?? '未知',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ),
          ListTile(
            title: const Text('设备架构', style: TextStyle(fontSize: 14)),
            trailing: Text(
              info['arch'] ?? _deviceInfo!['arch'] ?? '未知',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ),
          ListTile(
            title: const Text('Root 状态', style: TextStyle(fontSize: 14)),
            trailing: Text(
              info['rootStatus'] ?? '未知',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ),
        ],
        ListTile(
          title: const Text('开发者', style: TextStyle(fontSize: 14)),
          trailing: Text(
            AppConstants.authorName,
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
        ),
      ],
    );
  }

  Widget _buildDeviceScanSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          title: const Text('全面扫描设备', style: TextStyle(fontSize: 14)),
          subtitle: _scanning
              ? const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(),
                )
              : _scanResult != null
                  ? Text(
                      '${_scanResult!['brand'] ?? ''} ${_scanResult!['model'] ?? ''} | '
                      '${_scanResult!['appCount'] ?? '?'} 个应用 | '
                      '电量 ${_scanResult!['batteryLevel'] ?? '?'}%',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    )
                  : const Text('点击扫描设备信息、应用列表、存储、电池等', style: TextStyle(fontSize: 12, color: Colors.grey)),
          trailing: _scanning
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () async {
                    setState(() => _scanning = true);
                    try {
                      final result = await DeviceScanService.scanDevice();
                      if (mounted) setState(() => _scanResult = result);
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('扫描失败: $e')),
                        );
                      }
                    } finally {
                      if (mounted) setState(() => _scanning = false);
                    }
                  },
                ),
        ),
        if (_scanResult != null) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _scanRow('型号', '${_scanResult!['brand'] ?? '?'} ${_scanResult!['model'] ?? '?'}'),
                _scanRow('Android', '${_scanResult!['androidVersion'] ?? '?'} (SDK ${_scanResult!['sdkInt'] ?? '?'})'),
                _scanRow('架构', '${_scanResult!['arch'] ?? '?'}'),
                _scanRow('Root', _scanResult!['rooted'] == true ? '已获取' : '未获取'),
                if (_scanResult!['storageTotal'] != null)
                  _scanRow('存储', '${_scanResult!['storageUsed']}/${_scanResult!['storageTotal']} (可用 ${_scanResult!['storageAvail']})'),
                if (_scanResult!['ramTotalMB'] != null)
                  _scanRow('RAM', '${_scanResult!['ramTotalMB']}MB (可用 ${_scanResult!['ramAvailMB'] ?? '?'}MB)'),
                if (_scanResult!['batteryLevel'] != null)
                  _scanRow('电池', '${_scanResult!['batteryLevel']}% ${_scanResult!['batteryStatus'] ?? ''} ${_scanResult!['batteryTemp'] ?? ''}'),
                if (_scanResult!['wifiSSID'] != null)
                  _scanRow('WiFi', _scanResult!['wifiSSID'].toString()),
                if (_scanResult!['ipAddress'] != null)
                  _scanRow('IP', _scanResult!['ipAddress'].toString()),
                _scanRow('应用', '${_scanResult!['appCount'] ?? '?'} 个'),
                if (_scanResult!['keyApps'] != null)
                  _scanRow('关键应用', (_scanResult!['keyApps'] as List).join('、')),
              ],
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('注入 Agent', style: TextStyle(fontSize: 14)),
            subtitle: const Text('自动将设备信息注入 Agent 提示词', style: TextStyle(fontSize: 12, color: Colors.grey)),
            value: _injectDeviceToAgent,
            onChanged: (v) async {
              setState(() => _injectDeviceToAgent = v);
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('inject_device_to_agent', v);
            },
          ),
        ],
      ],
    );
  }

  Widget _scanRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  void _showApiKeyDialog(AiProvider provider) {
    final keyController = TextEditingController();
    final chatProvider = context.read<ChatProvider>();

    chatProvider.getApiKey(provider.id).then((key) {
      if (key != null && key.isNotEmpty) {
        keyController.text = key;
      }
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _ApiKeySheet(provider: provider, keyController: keyController, chatProvider: chatProvider),
    );
  }
}

class _ApiKeySheet extends StatefulWidget {
  final AiProvider provider;
  final TextEditingController keyController;
  final ChatProvider chatProvider;

  const _ApiKeySheet({
    required this.provider,
    required this.keyController,
    required this.chatProvider,
  });

  @override
  State<_ApiKeySheet> createState() => _ApiKeySheetState();
}

class _ApiKeySheetState extends State<_ApiKeySheet> {
  List<String> _customModels = [];
  final _modelController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCustomModels();
  }

  Future<void> _loadCustomModels() async {
    final models = await widget.provider.getAllModels();
    final defaults = widget.provider.defaultModels;
    if (mounted) {
      setState(() {
        _customModels = models.where((m) => !defaults.contains(m)).toList();
      });
    }
  }

  Future<void> _addModel() async {
    final name = _modelController.text.trim();
    if (name.isEmpty) return;
    await widget.provider.addCustomModel(name);
    _modelController.clear();
    await _loadCustomModels();
  }

  Future<void> _removeModel(String modelId) async {
    await widget.provider.removeCustomModel(modelId);
    await _loadCustomModels();
  }

  @override
  void dispose() {
    _modelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              CircleAvatar(
                backgroundColor: widget.provider.color,
                radius: 14,
                child: Text(widget.provider.name[0], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
              const SizedBox(width: 8),
              Text(widget.provider.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: widget.keyController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'API Key',
              hintText: widget.provider.apiKeyHint,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.visibility),
                onPressed: () {},
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () async {
                final key = widget.keyController.text.trim();
                if (key.isNotEmpty) {
                  await widget.chatProvider.saveApiKey(widget.provider.id, key);
                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${widget.provider.name} API Key 已保存')),
                    );
                  }
                }
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0D7CB5),
              ),
              child: const Text('保存'),
            ),
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          const Text('自定义模型', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _modelController,
                  decoration: const InputDecoration(
                    hintText: '输入模型 ID',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _addModel(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _addModel,
                icon: const Icon(Icons.add, size: 20),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF0D7CB5),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          if (_customModels.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...(_customModels.map((m) => ListTile(
                  dense: true,
                  title: Text(m, style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 18, color: Colors.red),
                    onPressed: () => _removeModel(m),
                  ),
                ))),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
