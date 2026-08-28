import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ScenarioItem {
  final String id;
  final String name;
  final IconData icon;
  final Color color;
  final String prompt;
  final bool isCustom;
  int order;

  ScenarioItem({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.prompt,
    this.isCustom = false,
    this.order = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'prompt': prompt,
        'order': order,
      };

  factory ScenarioItem.fromJson(Map<String, dynamic> json) => ScenarioItem(
        id: json['id'] as String,
        name: json['name'] as String,
        icon: Icons.auto_fix_high,
        color: const Color(0xFF0D7CB5),
        prompt: json['prompt'] as String,
        isCustom: true,
        order: json['order'] as int? ?? 999,
      );
}

class ScenarioSelector {
  static final List<ScenarioItem> _builtIn = [
    ScenarioItem(id: 'built_0', name: '极速晨间播报', icon: Icons.wb_sunny, color: Color(0xFFF59E0B), prompt: '帮我做晨间播报：查看今天的天气、日程安排和新闻摘要', order: 0),
    ScenarioItem(id: 'built_1', name: '一键通勤导航', icon: Icons.navigation, color: Color(0xFF3B82F6), prompt: '打开地图应用，帮我导航到公司', order: 1),
    ScenarioItem(id: 'built_2', name: '睡前清理残留', icon: Icons.cleaning_services, color: Color(0xFF8B5CF6), prompt: '清理后台应用，关闭不需要的通知，打开勿扰模式', order: 2),
    ScenarioItem(id: 'built_3', name: '自动抢红包', icon: Icons.card_giftcard, color: Color(0xFFEF4444), prompt: '打开微信，查看是否有未领取的红包，如果有帮我领取', order: 3),
    ScenarioItem(id: 'built_4', name: '智能自动回复', icon: Icons.reply, color: Color(0xFF10B981), prompt: '帮我设置微信自动回复：收到消息时自动回复"正在忙，稍后回复"', order: 4),
    ScenarioItem(id: 'built_5', name: '验证码自动填充', icon: Icons.pin, color: Color(0xFF6366F1), prompt: '帮我查找最新短信验证码并复制到剪贴板', order: 5),
    ScenarioItem(id: 'built_6', name: '会议自动静音', icon: Icons.mic_off, color: Color(0xFF6B7280), prompt: '打开系统静音模式，并把铃声音量调到最低', order: 6),
    ScenarioItem(id: 'built_7', name: '每日签到领红包', icon: Icons.check_circle, color: Color(0xFFF97316), prompt: '依次打开我常用的签到应用（支付宝、淘宝、京东），帮我完成每日签到', order: 7),
    ScenarioItem(id: 'built_8', name: '自动收蚂蚁能量', icon: Icons.energy_savings_leaf, color: Color(0xFF22C55E), prompt: '打开支付宝，进入蚂蚁森林，帮我收取所有可收取的能量', order: 8),
    ScenarioItem(id: 'built_9', name: '外卖一键复购', icon: Icons.fastfood, color: Color(0xFFEF4444), prompt: '打开美团，进入历史订单页面，帮我再来一单上次点过的外卖', order: 9),
    ScenarioItem(id: 'built_10', name: '自动记账', icon: Icons.receipt_long, color: Color(0xFF0EA5E9), prompt: '帮我打开记账应用，记录今天的消费情况。如果没有消费记录，查看微信支付或支付宝的账单', order: 10),
    ScenarioItem(id: 'built_11', name: '夜间极简模式', icon: Icons.nightlight_round, color: Color(0xFF1E293B), prompt: '开启系统深色模式，降低屏幕亮度到最低，关闭所有非必要的通知', order: 11),
    ScenarioItem(id: 'built_12', name: '智能Wi-Fi切换', icon: Icons.wifi, color: Color(0xFF2563EB), prompt: '检查当前连接的WiFi信号强度，如果信号太弱就切换到移动数据', order: 12),
    ScenarioItem(id: 'built_13', name: '定时杀毒清理', icon: Icons.security, color: Color(0xFF14B8A6), prompt: '运行手机安全扫描检测系统安全状态，清除缓存文件和临时文件释放空间', order: 13),
    ScenarioItem(id: 'built_14', name: '屏幕刷新率切换', icon: Icons.speed, color: Color(0xFF7C3AED), prompt: '把屏幕刷新率切换到60Hz省电模式，如果设备支持高刷的话', order: 14),
    ScenarioItem(id: 'built_15', name: '长文一键摘要', icon: Icons.summarize, color: Color(0xFF6366F1), prompt: '帮我打开剪贴板中的链接，提取并总结这篇文章的核心要点和关键信息', order: 15),
    ScenarioItem(id: 'built_16', name: '自动翻页', icon: Icons.auto_stories, color: Color(0xFFD97706), prompt: '打开阅读应用，在当前阅读界面自动向下滑动翻页，每页停留5秒钟', order: 16),
    ScenarioItem(id: 'built_17', name: '一键保存图片', icon: Icons.save_alt, color: Color(0xFFEC4899), prompt: '打开相册查看最新一张截图，帮我保存到 Download/aidroid 文件夹', order: 17),
    ScenarioItem(id: 'built_18', name: '游戏自动收菜', icon: Icons.sports_esports, color: Color(0xFF84CC16), prompt: '打开我最近玩的放置类游戏，检查并收取所有可以收获的资源', order: 18),
    ScenarioItem(id: 'built_19', name: '棋类最优落子', icon: Icons.grid_view, color: Color(0xFF475569), prompt: '帮我分析当前棋盘局面，给出最优的下一步落子位置和策略建议', order: 19),
  ];

  static List<ScenarioItem> _customScenarios = [];
  static bool _loaded = false;

  static List<ScenarioItem> get allScenarios {
    final list = <ScenarioItem>[..._builtIn, ..._customScenarios];
    list.sort((a, b) => a.order.compareTo(b.order));
    return list;
  }

  static List<ScenarioItem> get customScenarios => List.unmodifiable(_customScenarios);

  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('custom_scenarios');
    if (json != null && json.isNotEmpty) {
      try {
        final list = jsonDecode(json) as List;
        _customScenarios = list.map((e) => ScenarioItem.fromJson(e as Map<String, dynamic>)).toList();
      } catch (_) {
        _customScenarios = [];
      }
    }
    _loaded = true;
  }

  static Future<void> _saveCustom() async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(_customScenarios.map((e) => e.toJson()).toList());
    await prefs.setString('custom_scenarios', json);
  }

  static Future<void> addCustom(String name, String prompt) async {
    await ensureLoaded();
    final maxOrder = _customScenarios.fold<int>(0, (max, s) => s.order > max ? s.order : max);
    _customScenarios.add(ScenarioItem(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      icon: Icons.auto_fix_high,
      color: const Color(0xFF0D7CB5),
      prompt: prompt,
      isCustom: true,
      order: maxOrder > 0 ? maxOrder + 1 : _builtIn.length + _customScenarios.length,
    ));
    await _saveCustom();
  }

  static Future<void> deleteCustom(String id) async {
    await ensureLoaded();
    _customScenarios.removeWhere((s) => s.id == id);
    await _saveCustom();
  }

  static Future<void> copyToCustom(ScenarioItem builtIn) async {
    await ensureLoaded();
    final maxOrder = _customScenarios.fold<int>(0, (max, s) => s.order > max ? s.order : max);
    _customScenarios.add(ScenarioItem(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: builtIn.name,
      icon: builtIn.icon,
      color: builtIn.color,
      prompt: builtIn.prompt,
      isCustom: true,
      order: maxOrder > 0 ? maxOrder + 1 : _builtIn.length + _customScenarios.length,
    ));
    await _saveCustom();
  }

  static Future<void> updateOrder(List<ScenarioItem> reordered) async {
    await ensureLoaded();
    for (int i = 0; i < reordered.length; i++) {
      final s = reordered[i];
      if (s.isCustom) {
        final idx = _customScenarios.indexWhere((cs) => cs.id == s.id);
        if (idx >= 0) {
          _customScenarios[idx].order = i;
        }
      }
    }
    await _saveCustom();
  }

  static Future<void> resetToDefault() async {
    _customScenarios = [];
    await _saveCustom();
  }

  static Future<String> exportToFile() async {
    await ensureLoaded();
    final data = jsonEncode(_customScenarios.map((e) => e.toJson()).toList());
    final dir = Directory('/storage/emulated/0/Download/aidroid');
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File('${dir.path}/scenarios_backup_${DateTime.now().millisecondsSinceEpoch}.json');
    await file.writeAsString(data);
    return file.path;
  }

  static Future<int> importFromFile(String path) async {
    await ensureLoaded();
    final file = File(path);
    if (!await file.exists()) return 0;
    final content = await file.readAsString();
    final list = jsonDecode(content) as List;
    int count = 0;
    for (final e in list) {
      final s = ScenarioItem.fromJson(e as Map<String, dynamic>);
      if (!_customScenarios.any((cs) => cs.id == s.id)) {
        _customScenarios.add(s);
        count++;
      }
    }
    if (count > 0) await _saveCustom();
    return count;
  }

  static void show(BuildContext context, {required Function(String prompt) onSelect}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ScenarioSheet(onSelect: onSelect),
    );
  }
}

class _ScenarioSheet extends StatefulWidget {
  final Function(String) onSelect;
  const _ScenarioSheet({required this.onSelect});

  @override
  State<_ScenarioSheet> createState() => _ScenarioSheetState();
}

class _ScenarioSheetState extends State<_ScenarioSheet> {
  List<ScenarioItem> _scenarios = [];
  bool _editMode = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await ScenarioSelector.ensureLoaded();
    if (mounted) {
      setState(() {
        _scenarios = ScenarioSelector.allScenarios;
        _loaded = true;
      });
    }
  }

  void _refresh() {
    setState(() => _scenarios = ScenarioSelector.allScenarios);
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final item = _scenarios.removeAt(oldIndex);
      _scenarios.insert(newIndex, item);
    });
    ScenarioSelector.updateOrder(_scenarios);
  }

  Future<void> _showAddDialog() async {
    final nameCtrl = TextEditingController();
    final promptCtrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建场景'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '场景名称',
                hintText: '例如：一键截屏分享',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: promptCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '操作指令',
                hintText: '描述要执行的操作...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0D7CB5)),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (result == true) {
      final name = nameCtrl.text.trim();
      final prompt = promptCtrl.text.trim();
      if (name.isNotEmpty && prompt.isNotEmpty) {
        await ScenarioSelector.addCustom(name, prompt);
        _refresh();
      }
    }
  }

  Future<void> _copyBuiltIn(ScenarioItem item) async {
    await ScenarioSelector.copyToCustom(item);
    _refresh();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已复制「${item.name}」到自定义场景')),
      );
    }
  }

  Future<void> _deleteCustom(ScenarioItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除场景'),
        content: Text('确定要删除「${item.name}」吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await ScenarioSelector.deleteCustom(item.id);
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('快速场景',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const Spacer(),
              if (!_editMode)
                TextButton.icon(
                  onPressed: () => setState(() => _editMode = true),
                  icon: const Icon(Icons.reorder, size: 16),
                  label: const Text('排序', style: TextStyle(fontSize: 12)),
                )
              else
                TextButton.icon(
                  onPressed: () => setState(() => _editMode = false),
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('完成', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text('选择一个场景，将自动执行',
              style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          const SizedBox(height: 14),
          Expanded(child: _buildBody(isDark)),
        ],
      ),
    );
  }

  Widget _buildBody(bool isDark) {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_editMode) {
      return _buildEditList(isDark);
    }
    return _buildGrid(isDark);
  }

  Widget _buildGrid(bool isDark) {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 2.0,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: _scenarios.length + 1, // +1 for add card
      itemBuilder: (context, index) {
        if (index == _scenarios.length) {
          return _buildAddCard(isDark);
        }
        final s = _scenarios[index];
        return GestureDetector(
          onTap: () {
            Navigator.pop(context);
            widget.onSelect(s.prompt);
          },
          onLongPress: () => _showItemMenu(s),
          child: Stack(
            children: [
              _buildCard(s, isDark),
              if (s.isCustom)
                Positioned(
                  top: 2, right: 2,
                  child: GestureDetector(
                    onTap: () => _deleteCustom(s),
                    child: Container(
                      width: 20, height: 20,
                      decoration: const BoxDecoration(
                        color: Color(0xFFEF4444),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, size: 12, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEditList(bool isDark) {
    return ReorderableListView.builder(
      itemCount: _scenarios.length,
      onReorder: _onReorder,
      buildDefaultDragHandles: false,
      itemBuilder: (context, index) {
        final s = _scenarios[index];
        return Container(
          key: ValueKey(s.id),
          margin: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: const Icon(Icons.drag_handle, color: Colors.grey, size: 20),
              ),
              const SizedBox(width: 4),
              Expanded(child: _buildCard(s, isDark)),
              if (s.isCustom)
                IconButton(
                  icon: const Icon(Icons.close, size: 18, color: Color(0xFFEF4444)),
                  onPressed: () => _deleteCustom(s),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCard(ScenarioItem s, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2937) : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF374151) : const Color(0xFFE5E7EB),
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(s.icon, size: 20, color: s.color),
              if (s.isCustom) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D7CB5).withAlpha(30),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('自定', style: TextStyle(fontSize: 8, color: Color(0xFF0D7CB5))),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            s.name,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : const Color(0xFF1F2937),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildAddCard(bool isDark) {
    return GestureDetector(
      onTap: _showAddDialog,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1F2937) : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? const Color(0xFF374151) : const Color(0xFFE5E7EB),
            strokeAlign: BorderSide.strokeAlignInside,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_circle_outline, size: 28, color: Colors.grey[500]),
              const SizedBox(height: 4),
              Text('新建场景', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            ],
          ),
        ),
      ),
    );
  }

  void _showItemMenu(ScenarioItem s) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 12),
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(s.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(s.prompt, style: TextStyle(fontSize: 12, color: Colors.grey[500]), maxLines: 2),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.copy, color: Color(0xFF0D7CB5)),
              title: const Text('复制到自定义'),
              onTap: () {
                Navigator.pop(ctx);
                _copyBuiltIn(s);
              },
            ),
            if (s.isCustom)
              ListTile(
                leading: const Icon(Icons.delete, color: Color(0xFFEF4444)),
                title: const Text('删除'),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteCustom(s);
                },
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
