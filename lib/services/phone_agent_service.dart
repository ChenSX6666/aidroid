import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'log_service.dart';
import 'phone_control_service.dart';
import 'ui_tree_parser.dart';
import 'knowledge_search.dart';
import 'ocr_service.dart';
import 'ui_enhancer.dart';
import 'device_file_service.dart';
import 'blind_screen_navigator.dart';
import 'ai_chat_service.dart';
import '../models/custom_ai_provider.dart';
import 'web_search_service.dart';
import 'tool_permission_service.dart';
import 'browser_service.dart';

class PhoneAgentService {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 120),
  ));
  bool _isRunning = false;
  bool get isRunning => _isRunning;

  bool _paused = false;
  bool get isPaused => _paused;
  String? _pendingFeedback;
  Function(String)? _onAskUser;
  Function(String, int)? _onStatusForAction;
  int _currentStep = 0;

  void pause() => _paused = true;

  void resume({String? feedback}) {
    _paused = false;
    _pendingFeedback = feedback;
  }

  static const _systemPrompt = '''你是 Android 手机智能助手，运行在用户已 root 的手机上。你有两套手：Shell 命令（直接高效）和 UI 操作（精确点击）。根据任务自由选择最快的方式。

【绝对规则】
1. 绝对不能说"我无法/我不能/抱歉"。你拥有完整手机控制权。
2. 不确定的信息不编造，先搜索再回答。
3. 遇到困难换方式重试，不放弃。
4. 优先用 shell 命令完成系统级操作，比点 UI 快 10 倍。

【Shell 命令 — 系统操作首选】
- shell {"action":"shell","command":"..."}  执行任意 root shell 命令
- settings_get {"action":"settings_get","namespace":"global","key":"wifi_on"}  读系统设置
- settings_put {"action":"settings_put","namespace":"global","key":"wifi_on","value":"0"}  写设置
- broadcast {"action":"broadcast","broadcast_action":"android.intent.action.XXX"}  发广播
- force_stop {"action":"force_stop","package":"微信"}  强制停止应用
- clear_data {"action":"clear_data","package":"微信"}  清除应用数据
- grant_permission {"action":"grant_permission","package":"微信","permission":"android.permission.CAMERA"}  授权
- get_content {"action":"get_content","uri":"content://sms/inbox"}  读 ContentProvider

【打开App — 必须用open_app，不要用shell】
打开微信: {"action":"open_app","package":"微信","reason":"打开微信"}
打开游戏: {"action":"open_app","package":"部落冲突","reason":"打开游戏"}
打开浏览器: {"action":"open_app","package":"chrome","reason":"打开浏览器"}

【Shell 示例 — 仅用于系统操作】
关WiFi: {"action":"settings_put","namespace":"global","key":"wifi_on","value":"0","reason":"关闭WiFi"}
开蓝牙: {"action":"shell","command":"svc bluetooth enable","reason":"开启蓝牙"}
调亮度: {"action":"settings_put","namespace":"system","key":"screen_brightness","value":"100","reason":"调低亮度"}
查短信: {"action":"get_content","uri":"content://sms/inbox","reason":"读取最近短信"}
查已装应用: {"action":"shell","command":"pm list packages -3","reason":"列出第三方应用"}
打开设置页: {"action":"shell","command":"am start -a android.settings.WIFI_SETTINGS","reason":"打开WiFi设置"}
清缓存: {"action":"shell","command":"pm clear com.tencent.mm","reason":"清除微信缓存"}
截图: {"action":"shell","command":"screencap -p /sdcard/screenshot.png","reason":"截屏"}
查电量: {"action":"shell","command":"dumpsys battery","reason":"查看电池状态"}
查存储: {"action":"shell","command":"df -h","reason":"查看存储空间"}

【搜索】
- web_search {"action":"web_search","query":"搜索关键词"}  直接搜索互联网获取结果（无需打开浏览器）
- web_fetch {"action":"web_fetch","url":"https://..."}  获取指定网页内容
- 浏览器搜索: open_app → tap 地址栏 → input_text → key_event 回车 → 等待 → 读取（备选方案）

【浏览器自动化】(内置 WebView 浏览器)
- browser_open {"action":"browser_open","url":"https://..."}  打开网页
- browser_get_structure {"action":"browser_get_structure"}  读取当前页面可交互元素列表(带编号)
- browser_click {"action":"browser_click","index":N}  点击元素 N
- browser_input {"action":"browser_input","index":N,"text":"内容"}  在输入框 N 输入文字
- browser_scroll {"action":"browser_scroll","direction":"down"}  向下/向上滚动网页
- 用法: browser_open → browser_get_structure 看元素 → browser_input/browser_click 操作

【写内容】直接 input_text 写出完整文章/文案/代码，禁止拒绝

回复格式：每一步只输出一个 JSON {"action":"...","target":N,"reason":"为什么"}
连招: 快速连续操作输出 JSON 数组: [{"action":"tap","x":100,"y":200,"reason":"A"},{"action":"tap","x":300,"y":400,"reason":"B"}]
- 完成输出 DONE: 说明
- 需判断时输出 ASK_USER: 内容

【UI 操作 — App 内交互用】
- tap {"action":"tap","x":500,"y":800}
- double_tap / rapid_tap {"action":"rapid_tap","x":500,"y":800,"count":3}
- long_press {"action":"long_press","x":500,"y":800,"duration":1000}
- swipe {"action":"swipe","x1":100,"y1":800,"x2":100,"y2":200,"duration":500}
- drag {"action":"drag","x1":100,"y1":500,"x2":100,"y2":200,"duration":300}
- input_text {"action":"input_text","text":"内容"}  先 tap 输入框
- key_event {"action":"key_event","key":"home"}  home/back/recents
- wait {"action":"wait","ms":1000}
- open_app {"action":"open_app","package":"微信"}  中文名自动匹配
- list_apps {"action":"list_apps"}
- ask_user {"action":"ask_user","message":"请告诉我验证码"}
- click_node {"action":"click_node","target":"按钮文字或resourceId"}
- long_click_node / scroll_forward / scroll_backward / append_text / set_node_text

定位: 优先 target #N; 找不到用坐标 {"action":"tap","x":540,"y":1200}

策略（严格遵守，不能全用shell）:
- 打开App → open_app，不要用shell am start
- App内点击/滑动/输入 → tap/swipe/input_text，不要用shell
- 系统设置/查信息/文件操作 → shell
- 搜索 → web_search
- 开App后直接tap操作，不要反复dumpsys检查焦点
- 遇到问题换方式重试，绝不放弃
- "屏幕无变化"警告 → 换target/偏移/长按
- 点击无响应 → long_press / 偏移±20px
- 定位优先级: target #N → 文本匹配 → 坐标估算
- 弹窗/权限对话框优先处理(允许/确定/跳过)
- 输入前确认 EditText 已聚焦([E,F]标志)
- 找不到目标 → 滑动，最多滑5次
- 主动 list_apps 确认应用存在，再 open_app 启动

规则:
- open_app 直接启动，不回桌面找图标
- 广告找"跳过"/"×"/"关闭"，找不到点屏幕边缘
- 验证码: 滑块drag，图片tap，计算题input_text
- EditText 先 tap 聚焦再 input_text

盲屏模式(UI树为空):
- 坐标tap，不用 target #N
- 优先点OCR检测到文字的区域
- 中央按钮(w/2, h*0.4~0.6) → 右上关闭(w*0.9, h*0.1) → 滑动
- 无响应: 偏移±30px / 长按 / 滑动切换区域
- 连续2次无效操作后必须切换区域''';

  static const _speedPrompt = '''你是 Android 手机智能助手，运行在用户已 root 的手机上。Shell 命令和 UI 操作都能用，自由选择最快方式。

【绝对规则】不能说"我无法/我不能/抱歉"。系统操作优先 shell 命令。

Skills: web_search {"action":"web_search","query":"关键词"} 搜索互联网 | web_fetch {"action":"web_fetch","url":"..."} 获取网页内容
浏览器: browser_open/browser_get_structure/browser_click/browser_input/browser_scroll 操控内置WebView网页
Shell: shell/settings_get/settings_put/broadcast/force_stop/clear_data/grant_permission/get_content
示例: 关WiFi {"action":"settings_put","namespace":"global","key":"wifi_on","value":"0","reason":"关WiFi"}
查应用 {"action":"shell","command":"pm list packages -3","reason":"列应用"}
打开设置 {"action":"shell","command":"am start -a android.settings.WIFI_SETTINGS","reason":"开WiFi设置"}

UI: tap/double_tap/rapid_tap/long_press/swipe/drag/input_text/key_event/wait/open_app/list_apps/ask_user/click_node/scroll_forward/scroll_backward/append_text/set_node_text

回复: 只输出一个 JSON {"action":"...","...":"...","reason":"简短原因"}
连招: JSON数组 | 完成 DONE: 说明 | 需判断 ASK_USER: 内容

策略（严格遵守）: 打开App→open_app | App内点击滑动→tap/swipe | 系统设置→shell | 搜索→web_search
规则: open_app直接启动不反复检查 | 开App后直接操作不要dumpsys | 广告找关闭 | 输入框先tap再input | 找不到就滑动
盲屏: 坐标tap+优先文字区域+无响应偏移±30px+切换滑动''';

  void stop() => _isRunning = false;

  Future<String> runAgent({
    required String task,
    required String providerId,
    required String modelId,
    required String apiKey,
    required Function(String) onChunk,
    required Function(String status, int step) onStatus,
    bool useVision = false,
    bool speedMode = true,
    bool ocrEnabled = false,
    bool autoPlan = false,
    void Function(int step, String action, String target, String reason, bool success, String? error)? onStepRecord,
    void Function(String message)? onAskUser,
  }) async {
    _isRunning = true;
    _onAskUser = onAskUser;
    _onStatusForAction = onStatus;
    String result = '';
    int step = 0;
    int consecutiveNoChange = 0;
    final executedHistory = <String>[];
    List<String>? currentPlan;
    int stepsSincePlan = 0;
    String planHint = '';

    // Resolve provider endpoint (supports custom providers)
    final ep = await AiChatService.resolveEndpoint(providerId);
    if (!ep.openAiCompatible) {
      return '该模型格式暂不支持 Agent 操控，请选择 OpenAI 兼容格式的模型';
    }

    // Resolve model ID via mapping for custom providers
    String resolvedModelId = modelId;
    if (providerId.startsWith(CustomAiProvider.idPrefix)) {
      final customs = await CustomAiProvider.loadAll();
      for (final c in customs) {
        if (c.id == providerId) {
          resolvedModelId = c.resolveModel(modelId);
          break;
        }
      }
    }

    try {
      onStatus('分析屏幕...', 0);

      // Reset blind screen OCR tracking for new agent run
      BlindScreenNavigator.resetBlindTracking();

      // Parallel: getDisplaySize + dumpUI
      final initResults = await Future.wait([
        PhoneControlService.getDisplaySize(),
        PhoneControlService.dumpUI(),
      ]);
      final displaySize = initResults[0] as String;
      final xml = initResults[1] as String;
      if (!xml.contains('<?xml')) return '无法获取屏幕信息，请确认 root 权限已授予';

      if (ocrEnabled && BlindScreenNavigator.isBlind(xml)) {
        onStatus('🖼️ 检测盲屏，启用视觉...', 0);
      }
      String screenDesc = await _buildScreenDesc(xml, displaySize, ocrEnabled, onStatus: (msg) => onStatus(msg ?? '', 0));

      // Search knowledge base for similar past tasks
      String? knowledgeHint;
      try {
        final entries = await KnowledgeSearch.search(task);
        if (entries.isNotEmpty) {
          final kb = StringBuffer();
          kb.writeln('参考经验:');
          for (final e in entries) {
            kb.writeln('- 任务: ${e.task}');
            if (e.abstract.isNotEmpty) kb.writeln('  模式: ${e.abstract}');
            if (e.generalize.isNotEmpty) kb.writeln('  变通: ${e.generalize}');
          }
          knowledgeHint = kb.toString();
          LogService.info('知识库匹配到 ${entries.length} 条经验');
        }
      } catch (_) {}

      final prompt = speedMode ? _speedPrompt : _systemPrompt;

      // Auto-search game rules before starting
      String? gameRules;
      if (_isGameTask(task)) {
        try {
          gameRules = await _searchGameRules(task, ep, resolvedModelId, apiKey)
              .timeout(const Duration(seconds: 3), onTimeout: () => null);
          if (gameRules != null) LogService.info('已加载游戏规则');
        } catch (_) {}
      }

      final systemParts = [prompt];
      if (knowledgeHint != null) systemParts.add(knowledgeHint);
      if (gameRules != null) systemParts.add('游戏规则参考:\n$gameRules');
      final systemContent = systemParts.join('\n\n');
      final messages = <Map<String, dynamic>>[
        {'role': 'system', 'content': systemContent},
      ];

      final planPrefix = autoPlan
          ? '自动计划模式: 先输出执行计划，再按计划逐步执行。\n'
            '格式(可同时输出计划和一个操作): {"plan":["步骤1","步骤2",...],"action":{"action":"第一步操作","...":"..."},"reason":"原因"}\n'
            '也可以先只输出 EXECUTION_PLAN 计划文本，下一步再输出操作。\n'
            '每3步重新评估计划一次。\n\n'
          : '';
      final firstContent = <String, dynamic>{
        'type': 'text',
        'text': '$planPrefix$screenDesc\n\n任务: $task\n\n开始。',
      };

      if (useVision) {
        onStatus('截图+分析...', 0);
        final shot = await PhoneControlService.captureScreenshotJpeg();
        messages.add({
          'role': 'user',
          'content': [
            firstContent,
            {
              'type': 'image_url',
              'image_url': {'url': 'data:image/jpeg;base64,$shot'},
            },
          ],
        });
      } else {
        messages.add({'role': 'user', 'content': '$planPrefix$screenDesc\n\n任务: $task\n\n开始。'});
      }

      var currentXml = xml;

      while (_isRunning) {
        // Wait while paused
        while (_paused && _isRunning) {
          onStatus('已暂停', step);
          await Future.delayed(const Duration(milliseconds: 500));
        }
        if (!_isRunning) break;

        // Inject pending user feedback
        if (_pendingFeedback != null) {
          final fb = _pendingFeedback!;
          _pendingFeedback = null;
          messages.add({
            'role': 'user',
            'content': '用户反馈: $fb\n\n请根据此反馈调整后续操作。',
          });
          if (useVision) {
            onStatus('处理反馈...', step);
            // Don't add image for feedback — let next iteration capture fresh screen
          }
        }

        step++;
        _currentStep = step;
        onStatus('分析...', step);

        // Token 压缩：历史过长时把旧的屏幕描述折叠为执行摘要
        _compressMessages(messages, executedHistory);

        final response = await _dio.post(
          '${ep.host}${ep.endpoint}',
          data: {
            'model': resolvedModelId,
            'messages': messages,
            'stream': false,
            'temperature': 0.3,
            'max_tokens': 4096,
          },
          options: Options(headers: {
            'Content-Type': 'application/json',
            if (ep.authHeader != null) ep.authHeader!: '${ep.authPrefix}$apiKey',
            ...ep.extraHeaders,
          }),
        );

        final text = response.data?['choices']?[0]?['message']?['content'] as String? ?? '';
        onChunk(text);

        // autoPlan: 解析执行计划
        if (autoPlan) {
          final plan = _extractPlan(text);
          if (plan != null) {
            currentPlan = plan;
            stepsSincePlan = 0;
            planHint = '执行计划:\n${plan.map((s) => '- $s').join('\n')}';
            onStatus('📋 计划(${plan.length}步): ${plan.first}', step);
            LogService.agent('生成计划: ${plan.join(' / ')}');
          }
        }

        // 检测 API 内容审核拦截
        if (text.contains('high risk') || text.contains('rejected') || text.contains('违规') || text.contains('拒绝') || text.contains('敏感')) {
          result = 'API 内容审核拦截，请尝试切换模型（如 Gemini/Claude）或简化任务描述';
          break;
        }

        final actions = _parseActions(text);
        if (actions.isEmpty) {
          // autoPlan: 若响应只有计划文本无动作，确认计划后让 LLM 输出第一步操作
          if (autoPlan && currentPlan != null) {
            messages.add({'role': 'assistant', 'content': text});
            messages.add({'role': 'user', 'content': '计划已确认，请直接输出第一步操作 JSON。'});
            continue;
          }
          result = '无法解析: ${text.length > 200 ? '${text.substring(0, 200)}...' : text}';
          break;
        }
        if (actions[0]['type'] == 'DONE') {
          onStatus('完成', step);
          result = actions[0]['message'] ?? '完成';
          break;
        }
        if (actions[0]['type'] == 'ASK_USER') {
          final msg = actions[0]['message'] ?? '需要您的输入';
          onStatus('等待用户输入: $msg', step);
          onAskUser?.call(msg);
          _paused = true;
          // Wait for user input via overlay
          while (_paused && _isRunning) {
            await Future.delayed(const Duration(milliseconds: 300));
          }
          if (!_isRunning) break;
          // _pendingFeedback will be injected at top of loop
          continue;
        }

        // Execute all actions in sequence (combo/chain support)
        String? lastActionError;
        String? lastActionType;
        String lastDesc = '';
        for (int ai = 0; ai < actions.length; ai++) {
          final action = actions[ai];
          final desc = _actionDesc(action);
          onStatus(actions.length > 1 ? '连招${ai + 1}/${actions.length}: $desc' : '$desc', step);
          lastActionType = action['action'];
          lastDesc = desc;
          try {
            _lastActionResult = null;
            LogService.agent('第$step步${actions.length > 1 ? "[${ai + 1}/${actions.length}]" : ""}: $desc');
            await _executeAction(action, xml: currentXml);
            executedHistory.add(desc);
            onStepRecord?.call(step, action['action']!, desc, action['reason'] ?? '', true, null);
          } catch (e) {
            lastActionError = e.toString();
            LogService.error('第$step步异常: $lastActionError');
            onStepRecord?.call(step, action['action']!, desc, action['reason'] ?? '', false, lastActionError);
          }
          // Small delay between chained actions
          if (actions.length > 1 && ai < actions.length - 1) {
            await Future.delayed(const Duration(milliseconds: 50));
          }
        }
        if (!speedMode) {
          await Future.delayed(const Duration(milliseconds: 150));
        }

        messages.add({'role': 'assistant', 'content': text});

        if (lastActionType == 'list_apps' && _lastActionResult != null) {
          messages.add({'role': 'user', 'content': _lastActionResult! + '\n\n选择目标应用，用 open_app 直接启动。'});
          _lastActionResult = null;
        } else if (lastActionType == 'read_file' || lastActionType == 'list_files' || lastActionType == 'search_files') {
          if (_lastActionResult != null) {
            messages.add({'role': 'user', 'content': _lastActionResult! + '\n\n继续任务。'});
            _lastActionResult = null;
          }
        } else if (lastActionType == 'web_search' || lastActionType == 'web_fetch') {
          if (_lastActionResult != null) {
            messages.add({'role': 'user', 'content': _lastActionResult! + '\n\n根据以上信息继续任务。'});
            _lastActionResult = null;
          }
        } else if (lastActionError != null) {
          messages.add({'role': 'user', 'content': '⚠️ 操作异常: $lastActionError\n\n请尝试其他方式继续。'});
        } else if (_lastActionResult != null && _lastActionResult!.startsWith('⚠️')) {
          messages.add({'role': 'user', 'content': '$_lastActionResult\n\n请重新选择元素或使用坐标定位。'});
          _lastActionResult = null;
        } else {
          // In speed mode, start JPEG screenshot in parallel with dumpUI
          final newShotFuture = (speedMode && useVision)
              ? PhoneControlService.captureScreenshotJpeg()
              : null;

          final newXml = await PhoneControlService.dumpUI();
          // 盲屏(游戏/Unity)画面持续变化，必须每次重分析；普通界面 XML 未变则跳过重分析
          final isBlindScreen = BlindScreenNavigator.isBlind(newXml);
          final changed = isBlindScreen || newXml != currentXml;

          String feedback;
          if (changed) {
            final newDesc = speedMode
                ? UITreeParser.buildScreenDescription(newXml, displaySize)
                : await _buildScreenDesc(newXml, displaySize, ocrEnabled, onStatus: (msg) => onStatus(msg ?? '', step));
            consecutiveNoChange = 0;
            if (speedMode) {
              feedback = '已执行: $lastDesc\n\n$newDesc\n\n继续。';
            } else {
              final changeHint = _detectChange(currentXml, newXml);
              feedback = '已执行: $lastDesc。$changeHint\n\n$newDesc\n\n继续。';
            }
          } else {
            // 屏幕未变化：不重复全量分析，直接提示换策略（省 token、加速）
            consecutiveNoChange++;
            feedback = consecutiveNoChange >= 2
                ? '⚠️ 屏幕无变化(连续$consecutiveNoChange次)，请切换策略或调整操作！\n\n继续。'
                : '⚠️ 屏幕无变化，尝试其他方式。\n\n继续。';
          }

          currentXml = newXml;

          // autoPlan: 注入计划进度，每3步要求重新评估
          if (autoPlan && currentPlan != null) {
            stepsSincePlan++;
            planHint = '执行计划($stepsSincePlan/${currentPlan!.length}步):\n${currentPlan!.map((s) => '- $s').join('\n')}';
            if (stepsSincePlan >= 3) {
              feedback = '$feedback\n\n$planHint\n\n请评估进度：完成则输出 DONE，需要调整请重新输出计划。';
            } else {
              feedback = '$feedback\n\n$planHint';
            }
          }

          if (useVision) {
            final newShot = newShotFuture != null
                ? await newShotFuture
                : await PhoneControlService.captureScreenshotJpeg();
            messages.add({
              'role': 'user',
              'content': [
                {'type': 'text', 'text': feedback},
                {
                  'type': 'image_url',
                  'image_url': {'url': 'data:image/jpeg;base64,$newShot'},
                },
              ],
            });
          } else {
            messages.add({
              'role': 'user',
              'content': feedback,
            });
          }
        }
      }
    } catch (e) {
      if (e is DioException) {
        final code = e.response?.statusCode;
        final data = e.response?.data;
        String detail = '';
        if (data is Map) {
          detail = data['error']?['message'] ?? data['error']?.toString() ?? '';
        }
        switch (code) {
          case 400: result = '请求参数错误: $detail'; break;
          case 401: result = 'API Key 无效'; break;
          case 402: result = '余额不足'; break;
          case 429: result = '频率限制，稍后重试'; break;
          default: result = 'API 错误($code): $detail';
        }
      } else {
        result = '异常: $e';
      }
    }

    _isRunning = false;
    if (result.isEmpty) result = '已暂停(执行 $step 步)';
    return result;
  }

  // ── Multi-strategy JSON extraction ──

  /// Parse LLM response into a list of actions (supports single object or JSON array)
  List<Map<String, String>> _parseActions(String text) {
    if (text.contains('DONE:')) {
      return [{'type': 'DONE', 'message': text.split('DONE:').last.trim()}];
    }
    if (text.contains('ASK_USER:')) {
      return [{'type': 'ASK_USER', 'message': text.split('ASK_USER:').last.trim()}];
    }

    // Try JSON array first: [{"action":"tap",...},{"action":"swipe",...}]
    final arrayStr = _extractJsonArray(text);
    if (arrayStr != null) {
      try {
        final arr = jsonDecode(arrayStr) as List;
        final actions = <Map<String, String>>[];
        for (final item in arr) {
          if (item is Map<String, dynamic>) {
            final parsed = _mapToAction(item);
            if (parsed != null) actions.add(parsed);
          }
        }
        if (actions.isNotEmpty) return actions;
      } catch (_) {}
    }

    // Fall back to single object
    final single = _parseSingleAction(text);
    return single != null ? [single] : [];
  }

  /// Extract the execution plan (list of steps) from LLM response.
  /// Supports both {"plan":[...]} JSON and EXECUTION_PLAN: text blocks.
  List<String>? _extractPlan(String text) {
    // Strategy 1: JSON object with "plan" array
    final jsonStr = _extractJson(text);
    if (jsonStr != null) {
      try {
        final obj = jsonDecode(jsonStr) as Map<String, dynamic>;
        final plan = obj['plan'];
        if (plan is List && plan.isNotEmpty) {
          final items = plan
              .map((e) => e.toString().trim())
              .where((s) => s.isNotEmpty)
              .toList();
          if (items.isNotEmpty) return items;
        }
      } catch (_) {}
    }

    // Strategy 2: EXECUTION_PLAN: markdown numbered list
    final m = RegExp(
      r'EXECUTION_PLAN[:：]\s*\n?((?:[0-9一二三四五六七八九十]+[.、)．]?\s*.*\n?)+)',
      caseSensitive: false,
    ).firstMatch(text);
    if (m != null) {
      final lines = m
          .group(1)!
          .trim()
          .split('\n')
          .map((l) => l.replaceFirst(RegExp(r'^[0-9一二三四五六七八九十]+[.、)．]?\s*'), '').trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (lines.isNotEmpty) return lines;
    }
    return null;
  }

  Map<String, String>? _parseSingleAction(String text) {
    final jsonStr = _extractJson(text);
    if (jsonStr == null) return null;

    try {
      final obj = jsonDecode(jsonStr) as Map<String, dynamic>;
      return _mapToAction(obj);
    } catch (_) {
      return null;
    }
  }

  Map<String, String>? _mapToAction(Map<String, dynamic> obj) {
    final action = obj['action'] as String? ?? '';
    if (action.isEmpty) return null;
    // Pass ALL keys except 'action' and 'reason' as params
    final params = <String, dynamic>{};
    for (final entry in obj.entries) {
      if (entry.key != 'action' && entry.key != 'reason') {
        params[entry.key] = entry.value;
      }
    }
    // Normalize common aliases
    if (params.containsKey('target_id') && !params.containsKey('target')) {
      params['target'] = params.remove('target_id');
    }
    if (params.containsKey('keycode') && !params.containsKey('key')) {
      params['key'] = params.remove('keycode');
    }
    final reason = obj['reason'] as String? ?? '';

    return {'type': 'action', 'action': action, 'params': jsonEncode(params), 'reason': reason};
  }

  /// Extract JSON array [...] from text
  String? _extractJsonArray(String text) {
    // Strategy 1: ```json [ ... ] ```
    final m1 = RegExp(r'```json\s*(\[[\s\S]*?\])\s*```').firstMatch(text);
    if (m1 != null) return m1.group(1)!.trim();

    // Strategy 2: ``` [ ... ] ```
    final m1b = RegExp(r'```\s*(\[[\s\S]*?\])\s*```').firstMatch(text);
    if (m1b != null) return m1b.group(1)!.trim();

    // Strategy 3: Bracket counting — find first complete [...] pair
    final start = text.indexOf('[');
    if (start >= 0) {
      int depth = 0;
      bool inString = false;
      bool escaped = false;
      for (int i = start; i < text.length; i++) {
        final c = text[i];
        if (escaped) { escaped = false; continue; }
        if (c == '\\') { escaped = true; continue; }
        if (c == '"') { inString = !inString; continue; }
        if (inString) continue;
        if (c == '[') depth++;
        if (c == ']') {
          depth--;
          if (depth == 0) {
            final candidate = text.substring(start, i + 1).trim();
            try { jsonDecode(candidate); return candidate; } catch (_) {}
            break;
          }
        }
      }
    }

    return null;
  }

  /// Multi-strategy JSON extraction
  String? _extractJson(String text) {
    // Strategy 1: ```json { ... } ```
    final m1 = RegExp(r'```json\s*(\{[\s\S]*?\})\s*```').firstMatch(text);
    if (m1 != null) return m1.group(1)!.trim();

    // Strategy 2: ``` { ... } ``` (no language tag)
    final m1b = RegExp(r'```\s*(\{[\s\S]*?\})\s*```').firstMatch(text);
    if (m1b != null) return m1b.group(1)!.trim();

    // Strategy 3: Bracket counting — find first complete { ... } pair
    final start = text.indexOf('{');
    if (start >= 0) {
      int depth = 0;
      bool inString = false;
      bool escaped = false;
      for (int i = start; i < text.length; i++) {
        final c = text[i];
        if (escaped) { escaped = false; continue; }
        if (c == '\\') { escaped = true; continue; }
        if (c == '"') { inString = !inString; continue; }
        if (inString) continue;
        if (c == '{') depth++;
        if (c == '}') {
          depth--;
          if (depth == 0) {
            final candidate = text.substring(start, i + 1).trim();
            try { jsonDecode(candidate); return candidate; } catch (_) {}
            break;
          }
        }
      }
    }

    // Strategy 5: Try to parse the whole text as JSON
    try { jsonDecode(text.trim()); return text.trim(); } catch (_) {}

    return null;
  }

  // ── Execute ──

  Future<bool> _checkToolPermission(String tool) async {
    final level = await ToolPermissionService.getPermission(tool);
    if (level == ToolPermissionService.allow) return true;
    if (level == ToolPermissionService.deny) {
      _lastActionResult = '已拒绝执行 $tool，如需使用请在设置-工具权限中开启';
      return false;
    }
    // ask: pause and confirm
    _onStatusForAction?.call('请求权限: $tool', _currentStep);
    _onAskUser?.call('是否允许执行 $tool？回复"允许/是"继续，其他取消');
    _paused = true;
    while (_paused && _isRunning) {
      await Future.delayed(const Duration(milliseconds: 300));
    }
    if (!_isRunning) return false;
    return true;
  }

  Future<void> _executeAction(Map<String, String> act, {String? xml}) async {
    final action = act['action']!;
    Map<String, dynamic> p;
    try { p = jsonDecode(act['params'] ?? '{}'); } catch (_) { p = {}; }

    if (p.containsKey('target') && !p.containsKey('x') && !p.containsKey('y')) {
      try {
        final resolvedXml = xml ?? await PhoneControlService.dumpUI();
        final elements = UITreeParser.parse(resolvedXml);
        final idx = (p['target'] as num).toInt();
        if (idx < elements.length) {
          p['x'] = elements[idx].cx;
          p['y'] = elements[idx].cy;
        } else {
          _lastActionResult = '⚠️ 元素 #$idx 不存在(当前共${elements.length}个交互元素)，请重新选择目标';
          return;
        }
      } catch (_) {}
      p.remove('target');
    }

    // Validate coords
    if (p.containsKey('x')) {
      p['x'] = (p['x'] as num).toInt().clamp(0, 5000);
      p['y'] = (p['y'] as num).toInt().clamp(0, 5000);
    }

    // Tool permission gate for risky actions
    if (ToolPermissionService.riskyTools.contains(action)) {
      final allowed = await _checkToolPermission(action);
      if (!allowed) return;
    }

    switch (action) {
      case 'tap':
        await PhoneControlService.tap(p['x'] as int, p['y'] as int);
      case 'double_tap':
        final dx = p['x'] as int, dy = p['y'] as int;
        await PhoneControlService.tap(dx, dy);
        await Future.delayed(const Duration(milliseconds: 60));
        await PhoneControlService.tap(dx, dy);
      case 'rapid_tap':
        final rx = p['x'] as int, ry = p['y'] as int;
        final count = (p['count'] as int?) ?? 3;
        final interval = (p['ms'] as int?) ?? 80;
        for (int i = 0; i < count; i++) {
          await PhoneControlService.tap(rx, ry);
          if (i < count - 1) await Future.delayed(Duration(milliseconds: interval));
        }
      case 'long_press':
        final dur = (p['duration'] as int?) ?? 1000;
        await PhoneControlService.swipe(p['x'] as int, p['y'] as int, p['x'] as int, p['y'] as int, dur);
      case 'drag':
        await PhoneControlService.swipe(
          p['x1'] as int, p['y1'] as int,
          p['x2'] as int, p['y2'] as int,
          (p['duration'] as int?) ?? 500,
        );
      case 'swipe':
        await PhoneControlService.swipe(
          p['x1'] as int, p['y1'] as int,
          p['x2'] as int, p['y2'] as int,
          (p['duration'] as int?) ?? 500,
        );
      case 'input_text':
      case 'input':
        await PhoneControlService.inputText(p['text'] as String? ?? '');
      case 'key_event':
        await _key(p['key'] as String? ?? '');
      case 'wait':
        await Future.delayed(Duration(milliseconds: (p['ms'] as int?) ?? 1000));
      case 'open_app':
        final pkg = p['package'] as String? ?? '';
        // Try fuzzy match first — handles Chinese names like "微信"
        final resolved = await PhoneControlService.findPackage(pkg);
        await PhoneControlService.openApp(resolved ?? pkg);
      case 'list_apps':
        final apps2 = await PhoneControlService.listInstalledApps();
        final buf2 = StringBuffer('已安装应用:\n');
        for (final a in apps2.take(50)) {
          buf2.writeln('- ${a['label']} (${a['package']})');
        }
        _lastActionResult = buf2.toString();
      case 'read_file':
        final fpath = p['path'] as String? ?? '';
        final maxB = (p['maxBytes'] as int?) ?? 65536;
        if (fpath.isEmpty) {
          _lastActionResult = '⚠️ read_file 需要 path 参数';
        } else {
          final content = await DeviceFileService.readText(fpath, maxBytes: maxB);
          _lastActionResult = content.isEmpty ? '文件为空或无法读取: $fpath' : content;
        }
      case 'list_files':
        final dpath = p['path'] as String? ?? '/';
        final entries = await DeviceFileService.listDir(dpath);
        final buf3 = StringBuffer('目录列表: $dpath\n');
        for (final e in entries.take(50)) {
          final icon = e.isDirectory ? '[D]' : '[F]';
          final sizeStr = e.sizeBytes != null ? ' (${e.sizeBytes!}B)' : '';
          buf3.writeln('$icon ${e.name}$sizeStr');
        }
        _lastActionResult = buf3.toString();
      case 'search_files':
        final root = p['root'] as String? ?? '/';
        final pat = p['pattern'] as String? ?? '*';
        final results = await DeviceFileService.search(root, pat);
        if (results.isEmpty) {
          _lastActionResult = '未找到匹配 "$pat" 的文件';
        } else {
          final buf4 = StringBuffer('搜索结果 ($pat):\n');
          for (final r in results.take(50)) {
            buf4.writeln(r);
          }
          _lastActionResult = buf4.toString();
        }
      case 'ask_user':
        final msg = p['message'] as String? ?? '需要您的输入';
        _onStatusForAction?.call('等待用户输入: $msg', _currentStep);
        _onAskUser?.call(msg);
        _paused = true;
        while (_paused && _isRunning) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
        _lastActionResult = '用户已回复';
      case 'shell':
        final cmd = p['command'] as String? ?? '';
        if (cmd.isEmpty) throw Exception('shell 命令不能为空');
        final out = await PhoneControlService.shellExec(cmd);
        _lastActionResult = out.isNotEmpty ? out : '执行完成';
      case 'settings_get':
        final ns = p['namespace'] as String? ?? 'system';
        final key = p['key'] as String? ?? '';
        _lastActionResult = await PhoneControlService.getSetting(ns, key);
      case 'settings_put':
        final ns = p['namespace'] as String? ?? 'system';
        final key = p['key'] as String? ?? '';
        final val = p['value'] as String? ?? '';
        await PhoneControlService.putSetting(ns, key, val);
        _lastActionResult = '已设置 $ns/$key = $val';
      case 'broadcast':
        final broadcastAction = p['broadcast_action'] as String? ?? p['action_name'] as String? ?? '';
        final extras = p['extras'] as String? ?? '';
        _lastActionResult = await PhoneControlService.sendBroadcast(broadcastAction, extras);
      case 'force_stop':
        final pkg = p['package'] as String? ?? '';
        await PhoneControlService.forceStop(pkg);
        _lastActionResult = '已停止 $pkg';
      case 'clear_data':
        final pkg = p['package'] as String? ?? '';
        final ok = await PhoneControlService.clearData(pkg);
        _lastActionResult = ok ? '已清除 $pkg 数据' : '清除失败';
      case 'grant_permission':
        final pkg = p['package'] as String? ?? '';
        final perm = p['permission'] as String? ?? '';
        await PhoneControlService.grantPermission(pkg, perm);
        _lastActionResult = '已授权 $perm 给 $pkg';
      case 'get_content':
        final uri = p['uri'] as String? ?? '';
        _lastActionResult = await PhoneControlService.getContent(uri);
      case 'web_search':
        final query = p['query'] as String? ?? '';
        if (query.isEmpty) throw Exception('搜索关键词不能为空');
        _onStatusForAction?.call('搜索: $query', _currentStep);
        _lastActionResult = await WebSearchService.search(query);
      case 'web_fetch':
        final url = p['url'] as String? ?? '';
        if (url.isEmpty) throw Exception('URL 不能为空');
        _onStatusForAction?.call('获取: $url', _currentStep);
        _lastActionResult = await WebSearchService.fetchUrl(url);
      case 'click_node':
        final label = p['target'] as String? ?? p['text'] as String? ?? '';
        await PhoneControlService.clickNode(label);
        _lastActionResult = '已点击节点: $label';
      case 'long_click_node':
        final label = p['target'] as String? ?? p['text'] as String? ?? '';
        await PhoneControlService.longClickNode(label);
        _lastActionResult = '已长按节点: $label';
      case 'scroll_forward':
        await PhoneControlService.scrollForward();
        _lastActionResult = '已向前滚动';
      case 'scroll_backward':
        await PhoneControlService.scrollBackward();
        _lastActionResult = '已向后滚动';
      case 'append_text':
        final text = p['text'] as String? ?? '';
        await PhoneControlService.appendText(text);
        _lastActionResult = '已追加文本: $text';
      case 'set_node_text':
        final text = p['text'] as String? ?? '';
        final resId = p['resourceId'] as String? ?? '';
        await PhoneControlService.setNodeText(text, resId);
        _lastActionResult = '已设置节点文本: $text';
      case 'browser_open':
        final url = p['url'] as String? ?? '';
        if (url.isEmpty) throw Exception('URL 不能为空');
        _onStatusForAction?.call('打开网页: $url', _currentStep);
        final opened = await BrowserService.open(url);
        _lastActionResult = opened ? '已打开网页: $url' : '打开网页失败';
      case 'browser_get_structure':
        _onStatusForAction?.call('读取网页结构', _currentStep);
        _lastActionResult = await BrowserService.getStructureAsText();
      case 'browser_click':
        final idx = (p['index'] as num?)?.toInt() ?? -1;
        if (idx < 0) throw Exception('index 参数必须为数字');
        _onStatusForAction?.call('点击网页元素 #$idx', _currentStep);
        await BrowserService.click(idx);
        _lastActionResult = '已点击网页元素 #$idx';
      case 'browser_input':
        final idx = (p['index'] as num?)?.toInt() ?? -1;
        final text = p['text'] as String? ?? '';
        if (idx < 0) throw Exception('index 参数必须为数字');
        _onStatusForAction?.call('网页输入: $text', _currentStep);
        await BrowserService.input(idx, text);
        _lastActionResult = '已在元素 #$idx 输入: $text';
      case 'browser_scroll':
        final direction = p['direction'] as String? ?? 'down';
        _onStatusForAction?.call('网页滚动: $direction', _currentStep);
        await BrowserService.scroll(direction);
        _lastActionResult = '已向$direction滚动网页';
      default:
        throw Exception('未知操作: $action，可用: tap/swipe/input_text/shell/open_app/key_event/web_search/web_fetch/browser_open/browser_get_structure/browser_click/browser_input/browser_scroll');
    }
  }

  String? _lastActionResult;

  // ── Game rule auto-search ──

  static bool _isGameTask(String task) {
    const keywords = [
      '金铲铲', 'TFT', '云顶', '原神', '王者', '和平精英', '吃鸡',
      '游戏', '手游', '对战', '副本', '关卡', '抽卡', '十连',
      '英雄联盟', 'LOL', 'DOTA', '永劫', '第五人格', '明日方舟',
      '崩坏', '鸣尘', '幻塔', '阴阳师', 'FGO', '碧蓝',
    ];
    final lower = task.toLowerCase();
    return keywords.any((k) => lower.contains(k.toLowerCase()));
  }

  static Future<String?> _searchGameRules(
    String task,
    ({
      String host,
      String endpoint,
      String? authHeader,
      String authPrefix,
      Map<String, String> extraHeaders,
      bool openAiCompatible,
    }) ep,
    String modelId,
    String apiKey,
  ) async {
    // Extract game name from task
    const gameKeywords = ['金铲铲', 'TFT', '云顶', '原神', '王者', '和平精英', '吃鸡',
        '英雄联盟', 'LOL', '永劫', '第五人格', '明日方舟', '崩坏', '鸣尘', '幻塔'];
    String gameName = task;
    for (final kw in gameKeywords) {
      if (task.toLowerCase().contains(kw.toLowerCase())) {
        gameName = kw;
        break;
      }
    }

    final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 5), receiveTimeout: const Duration(seconds: 10)));
    try {
      final response = await dio.post(
        '${ep.host}${ep.endpoint}',
        data: {
          'model': modelId,
          'messages': [
            {'role': 'system', 'content': '你是游戏攻略助手。用200字以内概括游戏的基本操作界面和关键按钮位置。包括: 主菜单按钮位置、开始游戏按钮、常用操作区域、关键快捷操作。只输出内容，不要废话。'},
            {'role': 'user', 'content': '概括 $gameName 的基本操作界面和关键按钮位置'},
          ],
          'stream': false,
          'temperature': 0.3,
          'max_tokens': 500,
        },
        options: Options(headers: {
          'Content-Type': 'application/json',
          if (ep.authHeader != null) ep.authHeader!: '${ep.authPrefix}$apiKey',
          ...ep.extraHeaders,
        }),
      );
      return response.data?['choices']?[0]?['message']['content'] as String?;
    } catch (_) {
      return null;
    } finally {
      dio.close();
    }
  }

  /// 三级智能记忆管理：
  /// Level 1 (短期): 最近 3 轮对话 (6 条消息) 保留原样
  /// Level 2 (中期): 第 4-N 轮的操作序列压缩为摘要
  /// Level 3 (长期): 任务目标 + 关键状态始终保留
  static void _compressMessages(List<Map<String, dynamic>> messages, List<String> executedHistory) {
    // 估算总字符数
    int totalChars = 0;
    for (final m in messages) {
      final c = m['content'];
      if (c is String) {
        totalChars += c.length;
      } else if (c is List) {
        for (final part in c) {
          if (part is Map && part['type'] == 'text') {
            totalChars += (part['text'] as String? ?? '').length;
          }
        }
      }
    }
    // 低于阈值不压缩 (降低到 8000 减少不必要压缩)
    if (totalChars < 8000) return;

    // 结构: [0]=system, [1]=首条user(含任务), 中间操作... , 末尾最近 6 条 (3 轮)
    if (messages.length <= 8) return;

    final system = messages[0];
    final firstUser = messages[1];
    final recentMessages = messages.sublist(messages.length - 6);

    // Level 3 — 长期记忆：任务目标 + 关键状态
    final firstContent = firstUser['content']?.toString() ?? '';
    final taskMatch = RegExp(r'任务:\s*(.+)').firstMatch(firstContent);
    final taskGoal = taskMatch?.group(1) ?? (firstContent.length > 200 ? firstContent.substring(0, 200) : firstContent);

    final stepCount = executedHistory.length;
    final longTermBuf = StringBuffer('[长期记忆]\n');
    longTermBuf.writeln('任务: $taskGoal');
    longTermBuf.writeln('已执行: $stepCount 步');
    if (executedHistory.isNotEmpty) {
      longTermBuf.writeln('最后操作: ${executedHistory.last}');
    }

    // Level 2 — 中期记忆：操作摘要
    final midTermBuf = StringBuffer('[中期记忆] 已执行 $stepCount 步:\n');
    if (executedHistory.isEmpty) {
      midTermBuf.writeln('（暂无操作记录）');
    } else {
      for (int i = 0; i < executedHistory.length; i += 5) {
        final end = (i + 5).clamp(0, executedHistory.length);
        final chunk = executedHistory.sublist(i, end);
        midTermBuf.writeln('步骤${i + 1}-${end}: ${chunk.join(' → ')}');
      }
    }

    final compressed = <Map<String, dynamic>>[
      system,
      firstUser,
      {
        'role': 'user',
        'content': '${longTermBuf.toString()}\n\n${midTermBuf.toString()}\n\n继续当前任务。',
      },
      ...recentMessages,
    ];

    messages
      ..clear()
      ..addAll(compressed);
    LogService.info('三级记忆压缩: $stepCount 步, ${totalChars}字符 → 摘要 + 最近3轮');
  }

  static String _detectChange(String beforeXml, String afterXml) {
    // For blind screens, use OCR-based change detection
    if (BlindScreenNavigator.isBlind(afterXml)) {
      return BlindScreenNavigator.lastChangeDescription ?? '屏幕无变化';
    }
    if (beforeXml == afterXml) return '屏幕无变化';
    final before = UITreeParser.parse(beforeXml);
    final after = UITreeParser.parse(afterXml);
    final diff = after.length - before.length;
    if (diff > 5) return '屏幕新增 $diff 个元素，可能新页面或弹窗';
    if (diff < -5) return '屏幕减少 ${-diff} 个元素，可能已跳转';
    final beforeTexts = before.map((e) => e.label).toSet();
    final afterTexts = after.map((e) => e.label).toSet();
    final newTexts = afterTexts.difference(beforeTexts);
    if (newTexts.isEmpty) return '屏幕内容无明显变化';
    return '文本变化: ${newTexts.take(3).join(", ")}';
  }

  Future<void> _key(String k) async {
    switch (k) {
      case 'home': await PhoneControlService.pressHome();
      case 'back': await PhoneControlService.pressBack();
      case 'recents': await PhoneControlService.pressRecents();
    }
  }

  String _actionDesc(Map<String, String> act) {
    Map<String, dynamic> p;
    try { p = jsonDecode(act['params'] ?? '{}'); } catch (_) { p = {}; }
    switch (act['action']) {
      case 'tap': return p.containsKey('x') ? '点击(${p['x']},${p['y']})' : '点击元素#${p['target']}';
      case 'double_tap': return '双击(${p['x']},${p['y']})';
      case 'rapid_tap': return '连点${p['count'] ?? 3}次(${p['x']},${p['y']})';
      case 'long_press': return '长按(${p['x']},${p['y']})${p['duration']}ms';
      case 'drag': return '拖拽(${p['x1']},${p['y1']})→(${p['x2']},${p['y2']})';
      case 'swipe': return '滑动';
      case 'input_text':
      case 'input': return '输入"${p['text']}"';
      case 'key_event': return '按键${p['key']}';
      case 'wait': return '等待${p['ms'] ?? 1000}ms';
      case 'open_app': return '打开${p['package']}';
      case 'list_apps': return '获取应用列表';
      case 'read_file': return '读取文件(${p['path']})';
      case 'list_files': return '列表目录(${p['path']})';
      case 'search_files': return '搜索文件(${p['pattern']})';
      case 'ask_user': return '询问用户: ${p['message']}';
      case 'shell': return '执行命令(${p['command']})';
      case 'settings_get': return '读设置(${p['namespace']}/${p['key']})';
      case 'settings_put': return '写设置(${p['namespace']}/${p['key']})';
      case 'broadcast': return '广播(${p['broadcast_action'] ?? p['action_name']})';
      case 'force_stop': return '停止${p['package']}';
      case 'clear_data': return '清除${p['package']}数据';
      case 'grant_permission': return '授权${p['permission']}';
      case 'get_content': return '读ContentProvider(${p['uri']})';
      case 'web_search': return '搜索(${p['query']})';
      case 'web_fetch': return '获取网页(${p['url']})';
      case 'click_node': return '点击节点"${p['target']}"';
      case 'long_click_node': return '长按节点"${p['target']}"';
      case 'scroll_forward': return '向前滚动';
      case 'scroll_backward': return '向后滚动';
      case 'append_text': return '追加文本"${p['text']}"';
      case 'set_node_text': return '设置节点文本"${p['text']}"';
      case 'browser_open': return '打开网页(${p['url']})';
      case 'browser_get_structure': return '读取网页结构';
      case 'browser_click': return '点击网页元素#${p['index']}';
      case 'browser_input': return '网页输入"${p['text']}"到元素#${p['index']}';
      case 'browser_scroll': return '网页滚动(${p['direction'] ?? 'down'})';
      default: return act['action'] ?? '';
    }
  }

  /// Build screen description from XML, optionally enhanced with OCR and blind-screen vision
  Future<String> _buildScreenDesc(String xml, String displaySize, bool ocr, {void Function(String?)? onStatus}) async {
    // Blind screen detection: Unity/WebGL/game engines where UI tree is empty
    if (ocr && BlindScreenNavigator.isBlind(xml)) {
      try {
        return await BlindScreenNavigator.buildVisualReport(xml: xml, displaySize: displaySize, onStatus: onStatus);
      } catch (_) {}
    }

    if (!ocr) return UITreeParser.buildScreenDescription(xml, displaySize);

    try {
      // Use cached OCR blocks if fresh enough
      final cached = BlindScreenNavigator.getCachedOcrBlocks();
      List<OCRBlock> blocks;
      if (cached != null) {
        blocks = cached;
      } else {
        final shotPath = await PhoneControlService.captureScreenshot();
        blocks = await OCRService.recognizeFile(shotPath);
        if (blocks.isNotEmpty) BlindScreenNavigator.cacheOcrBlocks(blocks);
      }
      if (blocks.isNotEmpty) {
        return UIEnhancer.enhance(xml, blocks, displaySize);
      }
    } catch (_) {}

    return UITreeParser.buildScreenDescription(xml, displaySize);
  }
}
