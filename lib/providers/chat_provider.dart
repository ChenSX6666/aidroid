import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/conversation.dart';
import '../models/ai_provider.dart';
import '../models/custom_ai_provider.dart';
import '../services/ai_chat_service.dart';
import '../services/conversation_service.dart';
import '../services/phone_control_service.dart';
import '../services/shizuku_service.dart';
import '../services/phone_agent_service.dart';
import '../services/experience_service.dart';
import '../services/native_bridge.dart';
import '../services/blind_screen_navigator.dart';
import '../services/device_scan_service.dart';
import '../services/root_service.dart';
import '../services/manual_memory_service.dart';

class ChatProvider extends ChangeNotifier {
  final AiChatService _chatService = AiChatService();
  final ConversationService _convService = ConversationService();

  List<Conversation> _conversations = [];
  Conversation? _currentConversation;
  bool _isLoading = false;
  bool _isStreaming = false;
  String _streamingText = '';
  String _streamingReasoning = '';
  bool _hasStreamingReasoning = false;
  bool _hasContentStarted = false;
  String? _errorMessage;
  String _selectedProviderId = 'deepseek';
  String _selectedModelId = 'deepseek-v4-pro';
  String? _agentProviderId;
  String? _agentModelId;
  List<AiProvider> _customProviders = [];

  /// 内置厂商 + 自定义厂商
  List<AiProvider> get allProviders => [...AiProvider.all, ..._customProviders];
  String? _currentImageBase64;
  bool _phoneControlAvailable = false;
  bool _shizukuAvailable = false;
  final PhoneAgentService _agentService = PhoneAgentService();
  bool _agentRunning = false;
  bool get agentRunning => _agentRunning;
  bool _agentPaused = false;
  bool get agentPaused => _agentPaused;
  String _agentStatus = '';
  String get agentStatus => _agentStatus;
  int _agentStep = 0;
  int get agentStep => _agentStep;
  String _agentReason = '';
  String get agentReason => _agentReason;
  bool _agentMode = false;
  bool get agentMode => _agentMode;
  bool _agentUseVision = false;
  bool get agentUseVision => _agentUseVision;
  bool _agentSpeedMode = true;
  bool get agentSpeedMode => _agentSpeedMode;
  bool _overlayEnabled = true;
  bool get overlayEnabled => _overlayEnabled;
  bool _ocrEnabled = true;
  bool get ocrEnabled => _ocrEnabled;
  bool _fileSystemAccess = false;
  bool get fileSystemAccess => _fileSystemAccess;
  bool _autoPlanMode = false;
  bool get autoPlanMode => _autoPlanMode;
  String _executionMode = 'both';
  String get executionMode => _executionMode;

  List<Conversation> get conversations => _conversations;
  Conversation? get currentConversation => _currentConversation;
  bool get isLoading => _isLoading;
  bool get isStreaming => _isStreaming;
  String get streamingText => _streamingText;
  String get streamingReasoning => _streamingReasoning;
  bool get hasStreamingReasoning => _hasStreamingReasoning;
  bool get hasContentStarted => _hasContentStarted;
  String? get errorMessage => _errorMessage;
  String get selectedProviderId => _selectedProviderId;
  String get selectedModelId => _selectedModelId;
  String get agentProviderId => _agentProviderId ?? _selectedProviderId;
  String get agentModelId => _agentModelId ?? _selectedModelId;
  String? get currentImageBase64 => _currentImageBase64;
  bool get hasApiKey {
    return _apiKeyCache[_selectedProviderId]?.isNotEmpty == true;
  }
  bool get phoneControlAvailable => _phoneControlAvailable;
  bool get shizukuAvailable => _shizukuAvailable;

  final Map<String, String?> _apiKeyCache = {};

  Future<void> init() async {
    await _convService.init();
    _conversations = _convService.getAll();
    await _loadSettings();
    await DeviceScanService.init();
    await RootService.loadPersistedApps();
    if (_currentConversation == null && _conversations.isNotEmpty) {
      _currentConversation = _conversations.first;
    }
    NativeBridge.setOverlayActionCallback((action, text) {
      if (action == 'pause') {
        pauseAgent();
      } else if (action == 'resume') {
        resumeAgent();
      } else if (action == 'input' && text != null && text.isNotEmpty) {
        resumeAgent(feedback: text);
      }
    });
    PhoneControlService.checkAvailability().then((_) {
      _phoneControlAvailable = PhoneControlService.isAvailable;
      _shizukuAvailable = ShizukuService.isAvailable;
      notifyListeners();
    });
    notifyListeners();
  }

  Future<void> refreshPhoneAvailability() async {
    PhoneControlService.resetAvailability();
    await PhoneControlService.checkAvailability();
    _phoneControlAvailable = PhoneControlService.isAvailable;
    _shizukuAvailable = ShizukuService.isAvailable;
    notifyListeners();
  }

  Future<void> createNewChat() async {
    if (_currentConversation != null && _currentConversation!.messages.isEmpty) return;

    final conv = await _convService.createNew(
      providerId: _selectedProviderId,
      modelId: _selectedModelId,
    );
    _conversations = _convService.getAll();
    _currentConversation = conv;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> selectConversation(String id) async {
    _currentConversation = _convService.getById(id);
    _currentImageBase64 = null;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> deleteConversation(String id) async {
    await _convService.delete(id);
    if (_currentConversation?.id == id) {
      _currentConversation = null;
    }
    _conversations = _convService.getAll();
    if (_currentConversation == null && _conversations.isNotEmpty) {
      _currentConversation = _conversations.first;
    }
    notifyListeners();
  }

  Future<void> renameConversation(String id, String newTitle) async {
    final conv = _convService.getById(id);
    if (conv != null) {
      conv.title = newTitle;
      await _convService.save(conv);
      _conversations = _convService.getAll();
      notifyListeners();
    }
  }

  Future<void> forkFromMessage(String messageId) async {
    final conv = _currentConversation;
    if (conv == null) return;
    final index = conv.messages.indexWhere((m) => m.id == messageId);
    if (index < 0) return;
    final fork = await _convService.createFork(
      messages: conv.messages.sublist(0, index + 1),
      providerId: _selectedProviderId,
      modelId: _selectedModelId,
    );
    _conversations = _convService.getAll();
    _currentConversation = fork;
    _currentImageBase64 = null;
    _errorMessage = null;
    notifyListeners();
  }

  void toggleAgentMode() {
    _agentMode = !_agentMode;
    final prefs = SharedPreferences.getInstance();
    prefs.then((p) => p.setBool('agent_mode', _agentMode));
    notifyListeners();
  }

  Future<void> setAgentUseVision(bool v) async {
    _agentUseVision = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('agent_use_vision', v);
    notifyListeners();
  }

  Future<void> setAgentSpeedMode(bool v) async {
    _agentSpeedMode = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('agent_speed_mode', v);
    notifyListeners();
  }

  Future<void> setAutoPlanMode(bool v) async {
    _autoPlanMode = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_plan_mode', v);
    notifyListeners();
  }

  Future<void> setOverlayEnabled(bool v) async {
    _overlayEnabled = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('overlay_enabled', v);
    notifyListeners();
  }

  Future<void> setOcrEnabled(bool v) async {
    _ocrEnabled = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('ocr_enabled', v);
    notifyListeners();
  }

  Future<void> setFileSystemAccess(bool v) async {
    _fileSystemAccess = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('file_system_access', v);
    notifyListeners();
  }

  Future<void> setExecutionMode(String mode) async {
    _executionMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('execution_mode', mode);
    notifyListeners();
  }

  // ── Privacy mode ──

  bool _privacyMode = true;
  bool get privacyMode => _privacyMode;

  Future<void> setPrivacyMode(bool v) async {
    _privacyMode = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('privacy_mode', v);
    notifyListeners();
  }

  Future<void> sendMessage(String text, {String? imageBase64}) async {
    final imageToSend = imageBase64 ?? _currentImageBase64;
    // Determine if this is an agent command
    // /chat prefix forces normal chat (even in agent mode)
    // /agent or 操控手机: triggers agent (in normal mode)
    // In agent mode, everything goes to agent unless /chat
    final bool isAgentCommand;
    String cleanedText = text.trim();

    if (cleanedText.startsWith('/chat ')) {
      isAgentCommand = false;
      cleanedText = cleanedText.substring(6).trim();
    } else if (cleanedText.startsWith('/agent ') || cleanedText.startsWith('操控手机:')) {
      isAgentCommand = true;
    } else {
      isAgentCommand = _agentMode;
    }

    if (cleanedText.isEmpty && imageToSend == null) return;
    if (_isStreaming) return;

    if (_currentConversation == null) await createNewChat();
    if (_currentConversation == null) return;

    final providerForRequest = isAgentCommand ? agentProviderId : _selectedProviderId;
    String? apiKey;
    apiKey = await getApiKey(providerForRequest);
    if (apiKey == null || apiKey.isEmpty) {
      _errorMessage = '请先在设置中配置 $providerForRequest 的 API Key';
      notifyListeners();
      return;
    }

    // Extract agent task from prefixed commands
    String displayText = cleanedText;
    String agentTask = '';
    if (isAgentCommand) {
      if (text.trim().startsWith('/agent ')) {
        agentTask = text.trim().substring(7).trim();
        displayText = text.trim();
      } else if (text.trim().startsWith('操控手机:')) {
        agentTask = text.trim().substring(5).trim();
        displayText = text.trim();
      } else {
        // In agent mode, no prefix needed — whole message is the task
        agentTask = cleanedText;
      }
    }

    if (isAgentCommand && agentTask.isNotEmpty) {
      await _runAgentInChat(agentTask, displayText, apiKey);
      return;
    }

    // ── Normal chat flow ──
    final userMsg = Message(
      role: MessageRole.user,
      content: displayText,
      imageBase64: imageToSend,
    );
    await _convService.addMessage(_currentConversation!.id, userMsg);
    _currentConversation = _convService.getById(_currentConversation!.id);
    _currentImageBase64 = null;
    _isLoading = true;
    _streamingText = '';
    _streamingReasoning = '';
    _hasStreamingReasoning = false;
    _hasContentStarted = false;
    _isStreaming = true;
    _errorMessage = null;
    notifyListeners();

    final history = _currentConversation!.messages;

    // Build system prompt from manual memories when privacy mode is on
    String? systemPrompt;
    if (_privacyMode) {
      final memories = await ManualMemoryService.getAll();
      final memText = ManualMemoryService.getAsText(memories);
      if (memText.isNotEmpty) {
        systemPrompt = '你是一个智能助手，名叫"Aidroid"。以下是用户希望你知道的信息，请自然地融入这些信息来回复用户，但不要刻意提及你在使用记忆。\n\n$memText';
      }
    }

    try {
      final response = await _chatService.sendMessage(
        providerId: _selectedProviderId,
        modelId: _selectedModelId,
        apiKey: apiKey,
        history: history,
        systemPrompt: systemPrompt,
        imageBase64: imageToSend,
        onChunk: (chunk) {
          _streamingText += chunk;
          _hasContentStarted = true;
          notifyListeners();
        },
        onReasoning: (reasoning) {
          _streamingReasoning += reasoning;
          _hasStreamingReasoning = true;
          notifyListeners();
        },
      );

      final assistantMsg = Message(
        role: MessageRole.assistant,
        content: response.content,
        reasoningContent: response.reasoning.isNotEmpty ? response.reasoning : null,
      );
      await _convService.addMessage(_currentConversation!.id, assistantMsg);
      _currentConversation = _convService.getById(_currentConversation!.id);

      if (_currentConversation!.title == '新对话' && text.trim().isNotEmpty) {
        _currentConversation!.title = text.trim().length > 30
            ? '${text.trim().substring(0, 30)}...'
            : text.trim();
        await _convService.save(_currentConversation!);
      }

      _streamingText = '';
      _streamingReasoning = '';
      _hasStreamingReasoning = false;
      _hasContentStarted = false;
      _isStreaming = false;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = _chatService.mapError(e);
      _isLoading = false;
      _isStreaming = false;
      _streamingText = '';
      _streamingReasoning = '';
      _hasStreamingReasoning = false;
      _hasContentStarted = false;
      notifyListeners();
    }
  }

  // ── Agent integrated into chat ──

  Future<void> _runAgentInChat(String task, String displayText, String apiKey) async {
    if (!PhoneControlService.isAvailable) {
      _errorMessage = '请先授予 root 权限';
      notifyListeners();
      return;
    }

    // Add user message
    final userMsg = Message(
      role: MessageRole.user,
      content: displayText,
    );
    await _convService.addMessage(_currentConversation!.id, userMsg);
    _currentConversation = _convService.getById(_currentConversation!.id);

    _agentRunning = true;
    _agentPaused = false;
    _agentStatus = '准备中...';
    _agentStep = 0;
    _agentReason = '';
    _streamingText = '';
    _streamingReasoning = '';
    _isStreaming = true;
    _isLoading = true;
    notifyListeners();

    // Inject manual memory for agent task
    String finalTask = task;
    if (_privacyMode) {
      final memories = await ManualMemoryService.getAll();
      final memText = ManualMemoryService.getAsText(memories);
      if (memText.isNotEmpty) {
        finalTask = '$finalTask\n\n$memText';
      }
    }
    if (_fileSystemAccess) {
      finalTask = '$finalTask\n\n文件系统访问已启用:\n'
          '- read_file {"action":"read_file","path":"<完整路径>"}  读取设备文件内容\n'
          '- list_files {"action":"list_files","path":"<目录>"}  列出目录\n'
          '- search_files {"action":"search_files","root":"<搜索根>","pattern":"<文件名模式>"}  搜索文件\n'
          '适用场景: 直接读应用配置文件获取状态、查看日志定位问题、列出下载文件';
    }
    // Device scan injection removed — was causing hang on large app lists

    // Set execution mode
    PhoneControlService.setExecutionMode(_executionMode);

    // ── Auto-plan mode: detect screen type, status hint only ──
    bool autoPlanActive = _autoPlanMode;
    if (_autoPlanMode) {
      try {
        final xml = await PhoneControlService.dumpUI();
        if (xml.contains('<?xml')) {
          final isBlind = BlindScreenNavigator.isBlind(xml);
          if (isBlind && !_agentUseVision) {
            _agentStatus = '盲屏（游戏/画面），建议开启截图模式提升效果';
            notifyListeners();
          }
        }
      } catch (_) {
        autoPlanActive = false; // Fall back to normal mode if analysis fails
      }
    }

    // Show system overlay if enabled
    if (_overlayEnabled) {
      final hasOverlayPerm = await NativeBridge.hasOverlayPermission();
      if (!hasOverlayPerm) {
        await NativeBridge.requestOverlayPermission();
        await Future.delayed(const Duration(milliseconds: 500));
      }
      await NativeBridge.showAgentOverlay(_agentStatus, _agentStep);
    }

    final stepRecords = <AgentStepRecord>[];

    final result = await _agentService.runAgent(
      task: finalTask,
      providerId: agentProviderId,
      modelId: agentModelId,
      apiKey: apiKey,
      useVision: _agentUseVision,
      speedMode: _agentSpeedMode,
      ocrEnabled: _ocrEnabled,
      autoPlan: autoPlanActive,
      onChunk: (chunk) {
        _streamingText += chunk;
        _hasContentStarted = true;
        notifyListeners();
      },
      onStatus: (status, step) {
        _agentStatus = status;
        _agentStep = step;
        if (_overlayEnabled) {
          NativeBridge.updateAgentOverlay(status, step);
        }
        notifyListeners();
      },
      onStepRecord: (step, action, target, reason, success, error) {
        _agentReason = reason;
        stepRecords.add(AgentStepRecord(
          step: step,
          action: action,
          target: target,
          reason: reason,
          success: success,
          error: error,
        ));
        notifyListeners();
      },
      onAskUser: (message) {
        _agentPaused = true;
        if (_overlayEnabled) {
          NativeBridge.updateAgentOverlay('等待输入: $message', _agentStep, paused: true);
          NativeBridge.showAgentInput(message);
        }
        notifyListeners();
      },
    );

    // Generate knowledge base on successful completion
    if (!result.startsWith('异常') && !result.startsWith('API 错误') && !result.startsWith('无法')) {
      ExperienceService.generateKnowledgeBase(task: task, steps: stepRecords);
    }

    if (_overlayEnabled) {
      await NativeBridge.hideAgentOverlay();
    }

    // Save final result as assistant message
    final resultMsg = Message(role: MessageRole.assistant, content: result);
    await _convService.addMessage(_currentConversation!.id, resultMsg);
    _currentConversation = _convService.getById(_currentConversation!.id);

    // Auto-title if new conversation
    if (_currentConversation!.title == '新对话') {
      _currentConversation!.title = task.length > 30 ? '${task.substring(0, 30)}...' : task;
      await _convService.save(_currentConversation!);
    }

    _agentRunning = false;
    _agentPaused = false;
    _isStreaming = false;
    _isLoading = false;
    _streamingText = '';
    _agentStatus = '';
    _agentStep = 0;
    _agentReason = '';
    notifyListeners();
  }

  void stopStreaming() {
    if (_agentRunning) {
      _agentService.stop();
      _agentRunning = false;
      _agentPaused = false;
      if (_overlayEnabled) NativeBridge.hideAgentOverlay();
    }
    _isLoading = false;
    _isStreaming = false;
    if (_streamingText.isNotEmpty) {
      _convService.addMessage(
        _currentConversation!.id,
        Message(role: MessageRole.assistant, content: _streamingText),
      );
    }
    _streamingText = '';
    _streamingReasoning = '';
    _hasStreamingReasoning = false;
    _hasContentStarted = false;
    notifyListeners();
  }

  void stopAgent() {
    _agentService.stop();
    _agentRunning = false;
    _agentPaused = false;
    _isStreaming = false;
    _isLoading = false;
    if (_overlayEnabled) NativeBridge.hideAgentOverlay();
    notifyListeners();
  }

  void pauseAgent() {
    if (!_agentRunning || _agentPaused) return;
    _agentPaused = true;
    _agentService.pause();
    if (_overlayEnabled) {
      NativeBridge.updateAgentOverlay(_agentStatus, _agentStep, paused: true);
    }
    notifyListeners();
  }

  Future<void> resumeAgent({String? feedback}) async {
    if (!_agentRunning || !_agentPaused) return;
    _agentPaused = false;
    _agentService.resume(feedback: feedback);
    if (_overlayEnabled) {
      NativeBridge.hideAgentInput();
      NativeBridge.updateAgentOverlay(_agentStatus, _agentStep, paused: false);
    }
    notifyListeners();
  }

  void setProvider(String providerId) {
    if (_selectedProviderId == providerId) return;
    _selectedProviderId = providerId;
    final provider = allProviders.firstWhere(
      (p) => p.id == providerId,
      orElse: () => allProviders.first,
    );
    if (provider.defaultModels.isNotEmpty) {
      _selectedModelId = provider.defaultModels.first;
    }
    _saveSettings();
    notifyListeners();
  }

  void setModel(String modelId) {
    _selectedModelId = modelId;
    _saveSettings();
    notifyListeners();
  }

  void setAgentProvider(String providerId) {
    _agentProviderId = providerId;
    final provider = allProviders.firstWhere(
      (p) => p.id == providerId,
      orElse: () => allProviders.first,
    );
    if (provider.defaultModels.isNotEmpty) {
      _agentModelId = provider.defaultModels.first;
    }
    _saveSettings();
    notifyListeners();
  }

  void setAgentModel(String modelId) {
    _agentModelId = modelId;
    _saveSettings();
    notifyListeners();
  }

  void setImage(String? base64) {
    _currentImageBase64 = base64;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  Future<String?> getApiKey(String providerId) async {
    if (_apiKeyCache.containsKey(providerId)) return _apiKeyCache[providerId];
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString('api_key_$providerId');
    _apiKeyCache[providerId] = key;
    return key;
  }

  Future<void> saveApiKey(String providerId, String apiKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_key_$providerId', apiKey);
    _apiKeyCache[providerId] = apiKey;
    notifyListeners();
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_provider', _selectedProviderId);
    await prefs.setString('selected_model', _selectedModelId);
    if (_agentProviderId != null) {
      await prefs.setString('agent_provider', _agentProviderId!);
    }
    if (_agentModelId != null) {
      await prefs.setString('agent_model', _agentModelId!);
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _selectedProviderId = prefs.getString('selected_provider') ?? 'deepseek';
    _selectedModelId = prefs.getString('selected_model') ?? 'deepseek-v4-pro';
    _agentProviderId = prefs.getString('agent_provider');
    _agentModelId = prefs.getString('agent_model');
    _agentMode = false;  // 始终以普通对话模式启动，避免持久化劫持
    _agentUseVision = prefs.getBool('agent_use_vision') ?? false;
    _agentSpeedMode = prefs.getBool('agent_speed_mode') ?? true;
    _overlayEnabled = prefs.getBool('overlay_enabled') ?? true;
    _ocrEnabled = prefs.getBool('ocr_enabled') ?? true;
    _fileSystemAccess = prefs.getBool('file_system_access') ?? false;
    _autoPlanMode = prefs.getBool('auto_plan_mode') ?? false;
    _executionMode = prefs.getString('execution_mode') ?? 'both';
    _privacyMode = prefs.getBool('privacy_mode') ?? true;
    _customProviders = (await CustomAiProvider.loadAll()).map((e) => e.toAiProvider()).toList();
  }

  /// 保存/删除自定义厂商后刷新列表
  Future<void> refreshCustomProviders() async {
    _customProviders = (await CustomAiProvider.loadAll()).map((e) => e.toAiProvider()).toList();
    notifyListeners();
  }

  // ── Export ──

  String exportToMarkdown() {
    if (_currentConversation == null) return '';
    final conv = _currentConversation!;
    final buf = StringBuffer();
    buf.writeln('# ${conv.title}');
    buf.writeln();
    buf.writeln('> 模型: ${conv.providerId} / ${conv.modelId}');
    buf.writeln('> 时间: ${conv.createdAt.toString().substring(0, 19)}');
    buf.writeln();
    for (final msg in conv.messages) {
      final role = msg.role == MessageRole.user ? '用户' : '助手';
      buf.writeln('### $role');
      if (msg.reasoningContent != null && msg.reasoningContent!.isNotEmpty) {
        buf.writeln();
        buf.writeln('<details><summary>思考过程</summary>');
        buf.writeln();
        buf.writeln(msg.reasoningContent!);
        buf.writeln();
        buf.writeln('</details>');
      }
      buf.writeln();
      buf.writeln(msg.content);
      buf.writeln();
      buf.writeln('---');
      buf.writeln();
    }
    return buf.toString();
  }
}
