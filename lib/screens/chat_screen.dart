import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/chat_provider.dart';
import '../models/conversation.dart';
import '../widgets/chat_message_bubble.dart';
import '../widgets/model_selector.dart';
import '../widgets/image_picker_button.dart';
import '../widgets/scenario_selector.dart';
import '../services/action_recorder.dart';
import 'history_drawer.dart';
import 'new_settings_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  bool _showScrollButton = false;
  bool _wasStreaming = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final atBottom = _scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 100;
    if (_showScrollButton == atBottom) {
      setState(() => _showScrollButton = !atBottom);
    }
  }

  void _sendMessage() {
    final text = _textController.text.trim();
    final chat = context.read<ChatProvider>();

    // If agent is paused, resume with user message as feedback
    if (chat.agentRunning && chat.agentPaused) {
      if (text.isNotEmpty) {
        chat.resumeAgent(feedback: text);
        _textController.clear();
      }
      return;
    }

    if (chat.isStreaming) return;
    if (text.isEmpty && chat.currentImageBase64 == null) return;
    _textController.clear();
    chat.sendMessage(text, imageBase64: chat.currentImageBase64);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _showRenameDialog(ChatProvider chat) {
    final conv = chat.currentConversation;
    if (conv == null) return;
    final controller = TextEditingController(text: conv.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名对话'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '输入新名称',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                chat.renameConversation(conv.id, name);
                Navigator.pop(ctx);
              }
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

  Future<void> _exportMarkdown() async {
    final chat = context.read<ChatProvider>();
    if (chat.currentConversation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有可导出的对话')),
      );
      return;
    }
    final md = chat.exportToMarkdown();
    if (md.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final customPath = prefs.getString('export_path') ?? '';
    final dirPath = customPath.isNotEmpty
        ? customPath
        : '/storage/emulated/0/Download/aidroid';

    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final safeTitle = chat.currentConversation!.title
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .substring(0, 19);
      final file = File('${dir.path}/$safeTitle-$timestamp.md');
      await file.writeAsString(md);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导出: ${file.path}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      drawer: const HistoryDrawer(),
      body: Column(
        children: [
          Expanded(child: _buildMessageList()),
          Consumer<ChatProvider>(
            builder: (context, chat, _) {
              return ModelSelector(
                selectedProviderId: chat.selectedProviderId,
                selectedModelId: chat.selectedModelId,
                providers: chat.allProviders,
                onProviderChanged: (p) => chat.setProvider(p),
                onModelChanged: (m) => chat.setModel(m),
                trailingActions: [
                  _buildAgentToggle(chat),
                  const SizedBox(width: 3),
                  _buildExecutionModeChip(chat),
                  const SizedBox(width: 3),
                  _buildVisionChip(chat),
                  const SizedBox(width: 3),
                  _buildOcrChip(chat),
                  const SizedBox(width: 3),
                  _buildPlanChip(chat),
                  const SizedBox(width: 3),
                  _buildScenarioButton(chat),
                  const SizedBox(width: 3),
                  _buildRecordButton(chat),
                ],
              );
            },
          ),
          const Divider(height: 1),
          Consumer<ChatProvider>(
            builder: (context, chat, _) {
              if (!chat.agentMode) return const SizedBox.shrink();
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                color: const Color(0xFF0D7CB5).withAlpha(25),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 14, color: Color(0xFF0D7CB5)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '操控模式已开启，消息将发送给 Agent。输入 /chat 切换对话',
                        style: TextStyle(fontSize: 11, color: const Color(0xFF0D7CB5).withAlpha(200)),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      surfaceTintColor: Colors.transparent,
      leading: Builder(
        builder: (ctx) => IconButton(
          icon: const Icon(Icons.menu, size: 22),
          onPressed: () => Scaffold.of(ctx).openDrawer(),
        ),
      ),
      title: Consumer<ChatProvider>(
        builder: (context, chat, _) {
          final title = chat.currentConversation?.title ?? 'Aidroid';
          return GestureDetector(
            onDoubleTap: () {
              if (chat.currentConversation != null) {
                _showRenameDialog(chat);
              }
            },
            child: Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          );
        },
      ),
      centerTitle: true,
      actions: [
        IconButton(
          icon: const Icon(Icons.file_download_outlined, size: 22),
          onPressed: _exportMarkdown,
          tooltip: '导出 Markdown',
        ),
        IconButton(
          icon: const Icon(Icons.settings_outlined, size: 22),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const NewSettingsScreen()),
          ),
        ),
      ],
    );
  }

  Widget _buildMessageList() {
    return Consumer<ChatProvider>(
      builder: (context, chat, _) {
        final messages = chat.currentConversation?.messages ?? [];
        final convId = chat.currentConversation?.id ?? 'empty';

        if (messages.isEmpty && !chat.isStreaming) {
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _buildEmptyState(),
          );
        }

        if (chat.isStreaming) {
          _wasStreaming = true;
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
        } else if (_wasStreaming) {
          _wasStreaming = false;
        }

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: Stack(
            key: ValueKey(convId),
            children: [
            ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.only(top: 12, bottom: 80),
              itemCount: messages.length + (chat.isStreaming ? 1 : 0),
              itemBuilder: (context, index) {
                if (chat.isStreaming && index == messages.length) {
                  return ChatMessageBubble(
                    key: const ValueKey('streaming-bubble'),
                    message: Message(
                      id: 'streaming',
                      role: MessageRole.assistant,
                      content: chat.streamingText,
                    ),
                    isStreaming: true,
                    streamingText: chat.streamingText,
                    streamingReasoning: chat.streamingReasoning,
                    hasStreamingReasoning: chat.hasStreamingReasoning,
                    hasContentStarted: chat.hasContentStarted,
                  );
                }
                final msg = messages[index];
                return ChatMessageBubble(
                  message: msg,
                  onFork: () => chat.forkFromMessage(msg.id),
                );
              },
            ),
            if (_showScrollButton && !chat.isStreaming)
              Positioned(
                bottom: 8,
                right: 16,
                child: FloatingActionButton.small(
                  onPressed: _scrollToBottom,
                  child: const Icon(Icons.keyboard_arrow_down),
                ),
              ),
            if (chat.agentRunning)
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color: const Color(0xFF1F2937),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0D7CB5)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Agent 第 ${chat.agentStep} 步',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
                            Text(chat.agentStatus,
                              style: const TextStyle(fontSize: 13, color: Colors.white)),
                            if (chat.agentReason.isNotEmpty)
                              Text(chat.agentReason,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11, color: const Color(0xFF9CA3AF).withAlpha(180))),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          if (chat.agentPaused) {
                            chat.resumeAgent();
                          } else {
                            chat.pauseAgent();
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B).withAlpha(30),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            chat.agentPaused ? '继续' : '暂停',
                            style: const TextStyle(fontSize: 12, color: Color(0xFFF59E0B)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => chat.stopAgent(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444).withAlpha(30),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('停止', style: TextStyle(fontSize: 12, color: Color(0xFFEF4444))),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (chat.errorMessage != null)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: MaterialBanner(
                  content: Text(chat.errorMessage!),
                  actions: [
                    TextButton(
                      onPressed: () => chat.clearError(),
                      child: const Text('关闭'),
                    ),
                  ],
                ),
              ),
          ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 56,
            color: Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(80),
          ),
          const SizedBox(height: 16),
          Text(
            '开始新对话',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }

  void _showRecordSheet() {
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: 16, right: 16, top: 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            const Text('录制操作', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text('输入任务描述，然后手动操作手机。系统会通过 UI 变化自动学习。', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '例如: 在微信给张三发消息',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  final task = controller.text.trim();
                  if (task.isNotEmpty) {
                    Navigator.pop(ctx);
                    _startRecording(task);
                  }
                },
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
                child: const Text('开始录制'),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _startRecording(String task) {
    final chat = context.read<ChatProvider>();
    final recorder = ActionRecorder();
    recorder.onStatusChange = (status) {
      if (mounted) setState(() {});
    };
    recorder.start(task);
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('录制中 — 请手动操作手机，完成后点红色按钮停止'), duration: Duration(seconds: 2)),
    );
  }

  Future<void> _stopRecording() async {
    final recorder = ActionRecorder();
    final task = recorder.task;
    await recorder.stop();
    setState(() {});

    final chat = context.read<ChatProvider>();
    final apiKey = await chat.getApiKey(chat.selectedProviderId);
    if (apiKey == null || apiKey.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先配置 API Key'), duration: Duration(seconds: 2)),
        );
      }
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('分析录制数据...'), duration: Duration(seconds: 1)),
    );

    final result = await recorder.analyzeAndSave(
      apiKey: apiKey,
      providerId: chat.selectedProviderId,
      modelId: chat.selectedModelId,
    );

    if (mounted) {
      final msg = result.plan.isNotEmpty
          ? '已学习: ${result.plan.length > 50 ? '${result.plan.substring(0, 50)}...' : result.plan}'
          : '录制已保存到知识库';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
      );
    }
  }

  Widget _buildInputBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF121212) : const Color(0xFFF9FAFB),
            border: Border(
              top: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
            Consumer<ChatProvider>(
              builder: (context, chat, _) {
                return ImagePickerButton(
                  selectedImageBase64: chat.currentImageBase64,
                  onImagePicked: (b64) => chat.setImage(b64),
                );
              },
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 120),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isDark ? Colors.white10 : Colors.black12,
                  ),
                ),
                child: Consumer<ChatProvider>(
                  builder: (context, chat, _) {
                    return TextField(
                      controller: _textController,
                      focusNode: _focusNode,
                      textInputAction: TextInputAction.send,
                      maxLines: null,
                      minLines: 1,
                      style: TextStyle(
                        fontSize: 15,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      decoration: InputDecoration(
                        hintText: chat.agentPaused
                            ? '输入新指令或反馈并发送...'
                            : chat.agentMode ? '描述操作，或用 /chat 对话' : '输入消息，或用 /agent 操控',
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            Consumer<ChatProvider>(
              builder: (context, chat, _) {
                if (chat.isLoading && !chat.agentPaused) {
                  return IconButton(
                    icon: const Icon(Icons.stop_circle, color: Color(0xFF0D7CB5)),
                    onPressed: () => chat.stopStreaming(),
                  );
                }
                return IconButton(
                  icon: const Icon(Icons.send_rounded, color: Color(0xFF0D7CB5)),
                  onPressed: _sendMessage,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAgentToggle(ChatProvider chat) {
    return GestureDetector(
      onTap: () => chat.toggleAgentMode(),
      child: Container(
        width: 26, height: 26,
        decoration: BoxDecoration(
          color: chat.agentMode
              ? const Color(0xFF0D7CB5).withAlpha(40)
              : const Color(0xFF0D7CB5).withAlpha(20),
          borderRadius: BorderRadius.circular(13),
          border: chat.agentMode
              ? Border.all(color: const Color(0xFF0D7CB5), width: 1.5)
              : null,
        ),
        child: Icon(
          Icons.smart_toy,
          size: 14,
          color: chat.agentMode ? const Color(0xFF0D7CB5) : const Color(0xFF9CA3AF),
        ),
      ),
    );
  }

  Widget _buildExecutionModeChip(ChatProvider chat) {
    const modes = {
      'root': 'Root',
      'a11y': '无障碍',
      'shizuku': 'Shizuku',
      'both': '同时',
    };
    final label = modes[chat.executionMode] ?? '同时';
    return PopupMenuButton<String>(
      offset: const Offset(0, -300),
      onSelected: (m) => chat.setExecutionMode(m),
      itemBuilder: (_) => modes.entries.map((e) {
        return PopupMenuItem(
          value: e.key,
          child: Row(
            children: [
              Text(e.value, style: const TextStyle(fontSize: 13)),
              if (e.key == chat.executionMode)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.check, size: 16, color: Color(0xFF0D7CB5)),
                ),
            ],
          ),
        );
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF0D7CB5).withAlpha(30),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: const Color(0xFF0D7CB5).withAlpha(80), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.settings_applications, size: 13, color: Color(0xFF0D7CB5)),
            const SizedBox(width: 3),
            Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF0D7CB5))),
          ],
        ),
      ),
    );
  }

  Widget _buildVisionChip(ChatProvider chat) {
    return _buildToggleChip(
      active: chat.agentUseVision,
      activeColor: const Color(0xFF8B5CF6),
      icon: Icons.visibility_outlined,
      label: '截图',
      onTap: () => chat.setAgentUseVision(!chat.agentUseVision),
    );
  }

  Widget _buildOcrChip(ChatProvider chat) {
    return _buildToggleChip(
      active: chat.ocrEnabled,
      activeColor: const Color(0xFF22C55E),
      icon: Icons.text_fields,
      label: 'OCR',
      onTap: () => chat.setOcrEnabled(!chat.ocrEnabled),
    );
  }

  Widget _buildPlanChip(ChatProvider chat) {
    return _buildToggleChip(
      active: chat.autoPlanMode,
      activeColor: const Color(0xFFF59E0B),
      icon: Icons.checklist,
      label: '计划',
      onTap: () => chat.setAutoPlanMode(!chat.autoPlanMode),
    );
  }

  Widget _buildToggleChip({
    required bool active,
    required Color activeColor,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final color = active ? activeColor : const Color(0xFF9CA3AF);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        decoration: BoxDecoration(
          color: active ? activeColor.withAlpha(25) : Colors.transparent,
          borderRadius: BorderRadius.circular(13),
          border: active ? Border.all(color: activeColor, width: 1) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 3),
            Text(label, style: TextStyle(fontSize: 11, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildScenarioButton(ChatProvider chat) {
    return GestureDetector(
      onTap: () {
        ScenarioSelector.show(context, onSelect: (prompt) {
          chat.sendMessage(prompt);
        });
      },
      child: Container(
        width: 32, height: 32,
        decoration: BoxDecoration(
          color: const Color(0xFF8B5CF6).withAlpha(25),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.flash_on, size: 16, color: Color(0xFF8B5CF6)),
      ),
    );
  }

  Widget _buildRecordButton(ChatProvider chat) {
    final isRecording = ActionRecorder().isRecording;
    return GestureDetector(
      onTap: () {
        if (ActionRecorder().isRecording) {
          _stopRecording();
        } else {
          _showRecordSheet();
        }
      },
      child: Container(
        width: 32, height: 32,
        decoration: BoxDecoration(
          color: isRecording
              ? const Color(0xFFEF4444)
              : const Color(0xFFEF4444).withAlpha(25),
          borderRadius: BorderRadius.circular(16),
          border: isRecording
              ? Border.all(color: const Color(0xFFEF4444), width: 1.5)
              : null,
        ),
        child: Icon(
          isRecording ? Icons.stop : Icons.fiber_manual_record,
          size: 14,
          color: isRecording ? Colors.white : const Color(0xFFEF4444),
        ),
      ),
    );
  }
}
