import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../models/custom_ai_provider.dart';
import '../providers/chat_provider.dart';
import '../services/ai_chat_service.dart';

/// 新增/编辑自定义 AI 厂商表单
class CustomProviderScreen extends StatefulWidget {
  final ChatProvider chat;
  final CustomAiProvider? existing;

  const CustomProviderScreen({super.key, required this.chat, this.existing});

  @override
  State<CustomProviderScreen> createState() => _CustomProviderScreenState();
}

class _CustomProviderScreenState extends State<CustomProviderScreen> {
  late final TextEditingController _name;
  late final TextEditingController _note;
  late final TextEditingController _website;
  late final TextEditingController _apiKey;
  late final TextEditingController _baseUrl;
  late bool _isFullUrl;
  late String _apiFormat;
  late String _authField;
  bool _obscureKey = true;
  bool _pinging = false;
  String _pingResult = '';

  // Model mapping state
  late Map<String, TextEditingController> _modelControllers;
  late Set<String> _supportContext1M;
  late bool _fallbackEnabled;
  late TextEditingController _fallbackController;
  bool _mappingExpanded = false;
  bool _fetchingModels = false;

  static const _formats = [
    ('openai', 'OpenAI Chat Completions'),
    ('anthropic', 'Anthropic 原生'),
    ('gemini', 'Gemini 原生'),
  ];
  static const _authFields = [
    ('authorization', 'Authorization (Bearer)'),
    ('x_api_key', 'x-api-key'),
    ('auth_token', 'ANTHROPIC_AUTH_TOKEN'),
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _note = TextEditingController(text: e?.note ?? '');
    _website = TextEditingController(text: e?.website ?? '');
    _apiKey = TextEditingController();
    _baseUrl = TextEditingController(text: e?.baseUrl ?? '');
    _isFullUrl = e?.isFullUrl ?? false;
    _apiFormat = e?.apiFormat ?? 'openai';
    _authField = e?.authField ?? 'authorization';

    // Model mapping
    _modelControllers = {};
    for (final role in CustomAiProvider.modelRoles) {
      _modelControllers[role] = TextEditingController(
        text: e?.modelMapping[role] ?? '',
      );
    }
    _supportContext1M = Set.from(e?.supportContext1M ?? {});
    _fallbackEnabled = e?.fallbackEnabled ?? true;
    _fallbackController = TextEditingController(
      text: e?.fallbackModel ?? '陈烧虾的免费AI',
    );

    _loadKey();
  }

  Future<void> _loadKey() async {
    if (widget.existing == null) return;
    final key = await widget.chat.getApiKey(widget.existing!.id);
    if (key != null && key.isNotEmpty && mounted) {
      _apiKey.text = key;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    _website.dispose();
    _apiKey.dispose();
    _baseUrl.dispose();
    _fallbackController.dispose();
    for (final c in _modelControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _ping() async {
    final url = _baseUrl.text.trim();
    if (url.isEmpty) {
      setState(() => _pingResult = '请先填写请求地址');
      return;
    }
    setState(() {
      _pinging = true;
      _pingResult = '';
    });
    final probe = CustomAiProvider(
      id: 'probe',
      name: 'probe',
      baseUrl: url,
      isFullUrl: _isFullUrl,
      apiFormat: _apiFormat,
    ).resolveHost();
    final result = await AiChatService.pingEndpoint(probe);
    if (!mounted) return;
    setState(() {
      _pinging = false;
      _pingResult = result == null
          ? '测速失败：无法连接 $probe'
          : '可连通 (HTTP ${result.code}) — ${result.ms}ms';
    });
  }

  /// 一键设置：弹出输入框，填入一个模型 ID 后自动填充所有角色
  void _quickSetup() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('一键设置模型'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '模型 ID',
            hintText: '例如: deepseek-v4-flash',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final model = controller.text.trim();
              if (model.isNotEmpty) {
                setState(() {
                  for (final role in CustomAiProvider.modelRoles) {
                    _modelControllers[role]!.text = model;
                  }
                });
              }
              Navigator.pop(ctx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 获取模型列表：请求供应商 API 获取可用模型
  Future<void> _fetchModels() async {
    final url = _baseUrl.text.trim().replaceAll(RegExp(r'/+$'), '');
    final key = _apiKey.text.trim();
    if (url.isEmpty || key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先填写请求地址和 API Key')),
      );
      return;
    }
    setState(() => _fetchingModels = true);
    try {
      final host = CustomAiProvider(
        id: 'probe', name: 'probe', baseUrl: url,
        isFullUrl: _isFullUrl, apiFormat: _apiFormat,
      ).resolveHost();
      final ep = await AiChatService.resolveEndpoint(
        widget.existing?.id ?? 'probe',
      );
      // Use /models endpoint for OpenAI-compatible
      final modelsUrl = '$host/models';
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
      ));
      final resp = await dio.get(
        modelsUrl,
        options: Options(headers: {
          'Content-Type': 'application/json',
          if (ep.authHeader != null) ep.authHeader!: '${ep.authPrefix}$key',
        }),
      );
      final data = resp.data;
      final models = <String>[];
      if (data is Map && data['data'] is List) {
        for (final m in data['data']) {
          final id = m['id'] as String?;
          if (id != null) models.add(id);
        }
      }
      if (!mounted) return;
      if (models.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未获取到模型列表')),
        );
      } else {
        _showModelPicker(models);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('获取失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _fetchingModels = false);
    }
  }

  void _showModelPicker(List<String> models) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择模型'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: ListView.builder(
            itemCount: models.length,
            itemBuilder: (_, i) => ListTile(
              dense: true,
              title: Text(models[i], style: const TextStyle(fontSize: 13)),
              onTap: () {
                Navigator.pop(ctx);
                // 填入当前未填写的第一个角色
                for (final role in CustomAiProvider.modelRoles) {
                  if (_modelControllers[role]!.text.isEmpty) {
                    setState(() => _modelControllers[role]!.text = models[i]);
                    break;
                  }
                }
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final baseUrl = _baseUrl.text.trim().replaceAll(RegExp(r'/+$'), '');
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请填写供应商名称')));
      return;
    }
    if (baseUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请填写请求地址')));
      return;
    }

    // Build model mapping from controllers
    final mapping = <String, String>{};
    for (final role in CustomAiProvider.modelRoles) {
      final v = _modelControllers[role]!.text.trim();
      if (v.isNotEmpty) mapping[role] = v;
    }

    final existing = widget.existing;
    final newItem = (existing ?? CustomAiProvider(
      id: '${CustomAiProvider.idPrefix}${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      baseUrl: baseUrl,
    )).copyWith(
      name: name,
      note: _note.text.trim(),
      website: _website.text.trim(),
      baseUrl: baseUrl,
      isFullUrl: _isFullUrl,
      apiFormat: _apiFormat,
      authField: _authField,
      modelMapping: mapping,
      supportContext1M: _supportContext1M,
      fallbackEnabled: _fallbackEnabled,
      fallbackModel: _fallbackController.text.trim(),
    );

    final list = await CustomAiProvider.loadAll();
    final idx = list.indexWhere((c) => c.id == newItem.id);
    if (idx >= 0) {
      list[idx] = newItem;
    } else {
      list.add(newItem);
    }
    await CustomAiProvider.saveAll(list);
    final key = _apiKey.text.trim();
    if (key.isNotEmpty) {
      await widget.chat.saveApiKey(newItem.id, key);
    }
    await widget.chat.refreshCustomProviders();
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? '编辑自定义模型' : '添加自定义模型'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: '供应商名称',
              hintText: '例如: 基元律动',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            decoration: const InputDecoration(
              labelText: '备注',
              hintText: '例如: 公司专用账号',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _website,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: '官网链接 (可选)',
              hintText: 'https://example.com',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _apiKey,
            obscureText: _obscureKey,
            decoration: InputDecoration(
              labelText: 'API Key',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscureKey ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscureKey = !_obscureKey),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _baseUrl,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: '请求地址',
              hintText: 'https://tokenrhythm.studio/v1',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Expanded(
                child: Text(
                  '完整 URL：地址已包含 /v1 时开启，否则自动拼接',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
              Switch(
                value: _isFullUrl,
                onChanged: (v) => setState(() => _isFullUrl = v),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _buildDropdown(
            label: 'API 格式',
            value: _apiFormat,
            options: _formats,
            onChanged: (v) => setState(() => _apiFormat = v),
            hint: '选择供应商 API 的输入格式',
          ),
          const SizedBox(height: 12),
          _buildDropdown(
            label: '认证字段',
            value: _authField,
            options: _authFields,
            onChanged: (v) => setState(() => _authField = v),
            hint: '选择写入请求头的认证字段名',
          ),

          // ── 模型映射（可折叠）──
          const SizedBox(height: 20),
          const Divider(),
          InkWell(
            onTap: () => setState(() => _mappingExpanded = !_mappingExpanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.swap_horiz, size: 18, color: Color(0xFF0D7CB5)),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('模型映射', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                  Icon(_mappingExpanded ? Icons.expand_less : Icons.expand_more, size: 20),
                ],
              ),
            ),
          ),
          if (_mappingExpanded) ...[
            const SizedBox(height: 4),
            Text(
              '显示名称只影响模型菜单；1M 只是给 Agent 的上下文能力声明。',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _quickSetup,
                    icon: const Icon(Icons.flash_on, size: 16),
                    label: const Text('一键设置', style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _fetchingModels ? null : _fetchModels,
                    icon: _fetchingModels
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.download, size: 16),
                    label: const Text('获取模型列表', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Header row
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  SizedBox(width: 56, child: Text('角色', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey[700]))),
                  Expanded(child: Text('实际请求模型', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey[700]))),
                  SizedBox(width: 48, child: Text('1M', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey[700]), textAlign: TextAlign.center)),
                ],
              ),
            ),
            const SizedBox(height: 4),
            ...CustomAiProvider.modelRoles.map((role) => _buildMappingRow(role)),
          ],

          // ── 默认兜底模型 ──
          const SizedBox(height: 16),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.safety_check, size: 18, color: Color(0xFF0D7CB5)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('默认兜底模型', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ),
                Switch(
                  value: _fallbackEnabled,
                  onChanged: (v) => setState(() => _fallbackEnabled = v),
                ),
              ],
            ),
          ),
          Text(
            '开启后，未映射的角色将使用此模型作为兜底',
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
          if (_fallbackEnabled) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _fallbackController,
              decoration: const InputDecoration(
                labelText: '兜底模型名称',
                hintText: 'deepseek-v4-flash',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],

          // ── 测速 + 保存 ──
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pinging ? null : _ping,
                  icon: _pinging
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.speed, size: 18),
                  label: const Text('测速'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0D7CB5),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('保存'),
                ),
              ),
            ],
          ),
          if (_pingResult.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _pingResult,
              style: TextStyle(
                fontSize: 12,
                color: _pingResult.startsWith('测速失败') ? Colors.red : Colors.green[700],
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildMappingRow(String role) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              CustomAiProvider.modelRoleLabels[role] ?? role,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: TextField(
              controller: _modelControllers[role],
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                hintText: role == 'subagent' ? '不显示在菜单' : role,
                hintStyle: TextStyle(fontSize: 11, color: Colors.grey[400]),
                border: const OutlineInputBorder(),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
            ),
          ),
          SizedBox(
            width: 48,
            child: Checkbox(
              value: _supportContext1M.contains(role),
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    _supportContext1M.add(role);
                  } else {
                    _supportContext1M.remove(role);
                  }
                });
              },
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required List<(String, String)> options,
    required ValueChanged<String> onChanged,
    String hint = '',
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: value,
          isExpanded: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: options.map((o) => DropdownMenuItem(value: o.$1, child: Text(o.$2, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
        if (hint.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(hint, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ],
    );
  }
}
