import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../models/conversation.dart';
import '../services/native_bridge.dart';
import 'glass_widgets.dart';

class ChatMessageBubble extends StatefulWidget {
  final Message message;
  final bool isStreaming;
  final String? streamingText;
  final String? streamingReasoning;
  final bool hasStreamingReasoning;
  final bool hasContentStarted;
  final VoidCallback? onPlay;
  final VoidCallback? onFork;

  const ChatMessageBubble({
    super.key,
    required this.message,
    this.isStreaming = false,
    this.streamingText,
    this.streamingReasoning,
    this.hasStreamingReasoning = false,
    this.hasContentStarted = false,
    this.onPlay,
    this.onFork,
  });

  @override
  State<ChatMessageBubble> createState() => _ChatMessageBubbleState();
}

class _ChatMessageBubbleState extends State<ChatMessageBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;
  late Animation<Offset> _slide;
  late Animation<double> _fade;
  bool _reasoningOpen = false;
  bool _hasAnimated = false;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _slide = Tween<Offset>(
      begin: Offset(0, widget.message.role == MessageRole.user ? 0.15 : 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    _fade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _anim, curve: Curves.easeOut),
    );
    if (widget.isStreaming) {
      _anim.value = 1.0;
    } else {
      _anim.forward();
    }
    _hasAnimated = true;
  }

  @override
  void didUpdateWidget(ChatMessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isStreaming &&
        oldWidget.isStreaming &&
        !_hasAnimated) {
      _anim.forward();
      _hasAnimated = true;
    }
    // reasoning stays collapsed by default; user expands manually
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  bool get _isUser => widget.message.role == MessageRole.user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SlideTransition(
      position: _slide,
      child: FadeTransition(
        opacity: _fade,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: GestureDetector(
            onLongPress:
                widget.onFork != null && !widget.isStreaming ? _showForkMenu : null,
            child: Row(
            mainAxisAlignment:
                _isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!_isUser) _buildAvatar(isDark),
              if (!_isUser) const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: _isUser
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    if (!_isUser) _buildNameLabel(isDark),
                    if (!_isUser) const SizedBox(height: 2),
                    _buildBubble(context, isDark),
                    if (!widget.isStreaming && !_isUser)
                      _buildActionRow(isDark),
                  ],
                ),
              ),
              if (_isUser) const SizedBox(width: 8),
              if (_isUser) _buildAvatar(isDark),
            ],
          ),
          ),
        ),
      ),
    );
  }

  void _showForkMenu() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1F2937) : Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.call_split),
              title: const Text('从此分叉'),
              subtitle: const Text('从这里开始一段新的对话，原对话保留'),
              onTap: () {
                Navigator.pop(context);
                widget.onFork?.call();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(bool isDark) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: _isUser
            ? const Color(0xFF0D7CB5)
            : isDark
                ? const Color(0xFF374151)
                : const Color(0xFFE5E7EB),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Text(
        _isUser ? '我' : '助',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: _isUser
              ? Colors.white
              : isDark
                  ? const Color(0xFF9CA3AF)
                  : const Color(0xFF6B7280),
        ),
      ),
    );
  }

  Widget _buildNameLabel(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(
        'Aidroid',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
        ),
      ),
    );
  }

  Widget _buildBubble(BuildContext context, bool isDark) {
    final text = widget.isStreaming
        ? (widget.streamingText ?? widget.message.content)
        : widget.message.content;
    final hasImage =
        widget.message.imageBase64 != null &&
        widget.message.imageBase64!.isNotEmpty;
    final reasoning = widget.isStreaming
        ? (widget.streamingReasoning ?? '')
        : (widget.message.reasoningContent ?? '');
    final hasReasoning = reasoning.isNotEmpty || widget.hasStreamingReasoning;

    // Use GlassCard for assistant messages when glass mode is enabled
    if (!_isUser) {
      return ValueListenableBuilder<bool>(
        valueListenable: glassModeEnabled,
        builder: (context, glassOn, _) {
          if (glassOn) {
            return GlassCard(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(16),
              ),
              padding: EdgeInsets.zero,
              child: _buildBubbleContent(context, isDark, text, hasImage, reasoning, hasReasoning),
            );
          }
          return _buildBubbleContainer(context, isDark, text, hasImage, reasoning, hasReasoning);
        },
      );
    }

    return _buildBubbleContainer(context, isDark, text, hasImage, reasoning, hasReasoning);
  }

  Widget _buildBubbleContent(BuildContext context, bool isDark, String text, bool hasImage, String reasoning, bool hasReasoning) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasImage) _buildImagePreview(context),
        if (hasReasoning) _buildReasoningSection(isDark, reasoning),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: widget.isStreaming && text.isEmpty && !widget.hasStreamingReasoning
              ? _buildTypingIndicator(isDark)
              : widget.isStreaming && text.isEmpty && widget.hasStreamingReasoning
                  ? _buildThinkingIndicator(isDark)
                  : text.isNotEmpty
                      ? _buildContent(text, isDark, widget.isStreaming)
                      : const SizedBox.shrink(),
        ),
        if (widget.isStreaming && text.isNotEmpty)
          _buildCursor(isDark),
      ],
    );
  }

  Widget _buildBubbleContainer(BuildContext context, bool isDark, String text, bool hasImage, String reasoning, bool hasReasoning) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.82,
      ),
      decoration: BoxDecoration(
        color: _isUser
            ? const Color(0xFF0D7CB5)
            : isDark
                ? const Color(0xFF1F2937)
                : Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(_isUser ? 16 : 4),
          bottomRight: Radius.circular(_isUser ? 4 : 16),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(_isUser ? 25 : 10),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: !_isUser && !isDark
            ? Border.all(color: const Color(0xFFE5E7EB))
            : null,
      ),
      child: _buildBubbleContent(context, isDark, text, hasImage, reasoning, hasReasoning),
    );
  }

  // Remove markdown heading markers (#, ##, ###, etc.) from line starts
  // so the text looks clean when rendered as plain text
  static String _cleanMarkdown(String text) {
    return text.replaceAll(RegExp(r'^#{1,4}\s+', multiLine: true), '');
  }

  Widget _buildContent(String text, bool isDark, [bool isStreaming = false]) {
    final cleaned = _isUser ? text : _cleanMarkdown(text);
    // During streaming, render text directly — never parse, never strip.
    // Incomplete code blocks or other markdown can't cause invisible content
    // when we simply show everything as-is.
    if (isStreaming) {
      // 最稳妥方案：流式时零处理，直接渲染原始文本
      // 用户会看到 ```json\n 等 markdown 标记，但绝不会空白
      return SelectableText(
        cleaned,
        style: TextStyle(
          color: _isUser ? Colors.white : (isDark ? const Color(0xFFF3F4F6) : const Color(0xFF1F2937)),
          fontSize: 14.5,
          height: 1.6,
        ),
      );
    }

    final codeBlocks = _extractCodeBlocks(cleaned);

    if (codeBlocks.isEmpty) {
      return SelectableText(
        cleaned,
        style: TextStyle(
          color: _isUser ? Colors.white : (isDark ? const Color(0xFFF3F4F6) : const Color(0xFF1F2937)),
          fontSize: 14.5,
          height: 1.6,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final block in codeBlocks) ...[
          if (block['text'] != null && (block['text'] as String).isNotEmpty)
            SelectableText(
              block['text'] as String,
              style: TextStyle(
                color: _isUser ? Colors.white : (isDark ? const Color(0xFFF3F4F6) : const Color(0xFF1F2937)),
                fontSize: 14.5,
                height: 1.6,
              ),
            ),
          if (block['code'] != null)
            _buildCodeBlock(block['code'] as String, block['lang'] as String?, isDark),
        ],
      ],
    );
  }

  Widget _buildCodeBlock(String code, String? lang, bool isDark) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111827) : const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 0),
            child: Row(
              children: [
                if (lang != null)
                  Text(
                    lang,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('代码已复制'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                  child: const Icon(Icons.copy, size: 14, color: Color(0xFF9CA3AF)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              code,
              style: const TextStyle(
                fontFamily: 'DejaVuSansMono',
                fontSize: 12,
                height: 1.5,
                color: Color(0xFFE5E7EB),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _extractCodeBlocks(String text) {
    final blocks = <Map<String, dynamic>>[];
    final regex = RegExp(r'```(\w*)\n([\s\S]*?)```');
    int lastEnd = 0;

    for (final match in regex.allMatches(text)) {
      if (match.start > lastEnd) {
        blocks.add({'text': text.substring(lastEnd, match.start)});
      }
      blocks.add({
        'code': match.group(2)?.trim() ?? '',
        'lang': match.group(1)?.isNotEmpty == true ? match.group(1) : null,
      });
      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      blocks.add({'text': text.substring(lastEnd)});
    }

    return blocks;
  }

  Widget _buildReasoningSection(bool isDark, String reasoning) {
    return GestureDetector(
      onTap: () => setState(() => _reasoningOpen = !_reasoningOpen),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF374151).withAlpha(60) : const Color(0xFFF3F4F6),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lightbulb_outline,
                  size: 14,
                  color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
                ),
                const SizedBox(width: 4),
                Text(
                  widget.isStreaming ? '思考中...' : '思考过程',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  _reasoningOpen ? Icons.expand_less : Icons.expand_more,
                  size: 14,
                  color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
                ),
              ],
            ),
            if (_reasoningOpen) ...[
              const SizedBox(height: 6),
              Text(
                reasoning,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionRow(bool isDark) {
    final content = widget.message.content;
    final hasHtml = content.contains('<html') || content.contains('<!DOCTYPE html');

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildMiniButton(
            Icons.copy,
            '复制',
            () {
              Clipboard.setData(ClipboardData(text: content));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('已复制到剪贴板'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
          if (widget.onPlay != null) ...[
            const SizedBox(width: 8),
            _buildMiniButton(Icons.volume_up, '朗读', () => widget.onPlay?.call()),
          ],
          if (hasHtml) ...[
            const SizedBox(width: 8),
            _buildMiniButton(
              Icons.save_alt,
              '保存 HTML',
              () => _saveHtml(content),
            ),
            const SizedBox(width: 8),
            _buildMiniButton(
              Icons.open_in_browser,
              '运行 HTML',
              () => _runHtml(content),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMiniButton(IconData icon, String label, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF374151).withAlpha(80) : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280)),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveHtml(String html) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/output_${DateTime.now().millisecondsSinceEpoch}.html');
      await file.writeAsString(html);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已保存到: ${file.path}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    }
  }

  Future<void> _runHtml(String html) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/preview_${DateTime.now().millisecondsSinceEpoch}.html');
      await file.writeAsString(html);
      final ok = await NativeBridge.openHtmlFile(file.path);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('打开 HTML 失败，请检查浏览器是否可用')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('运行失败: $e')),
        );
      }
    }
  }

  Widget _buildImagePreview(BuildContext context) {
    return GestureDetector(
      onTap: () => _showFullImage(context, widget.message.imageBase64!),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 200),
        child: Image.memory(
          _decodeBase64(widget.message.imageBase64!),
          fit: BoxFit.cover,
          width: double.infinity,
        ),
      ),
    );
  }

  Widget _buildThinkingIndicator(bool isDark) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.92, end: 1.05),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeInOut,
      builder: (context, scale, _) {
        return Transform.scale(
          scale: scale,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF0D7CB5).withAlpha(30),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.pending, size: 16, color: Color(0xFF0D7CB5)),
              ),
              const SizedBox(width: 8),
              Text(
                '思考中...',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTypingIndicator(bool isDark) {
    return SizedBox(
      height: 18,
      width: 36,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _dot(isDark, 0),
          const SizedBox(width: 3),
          _dot(isDark, 150),
          const SizedBox(width: 3),
          _dot(isDark, 300),
        ],
      ),
    );
  }

  Widget _dot(bool isDark, int delayMs) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.3, end: 1.0),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOut,
      builder: (context, val, _) {
        return Opacity(
          opacity: val,
          child: Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCursor(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        builder: (context, val, _) {
          return Opacity(
            opacity: val > 0.5 ? 1.0 : 0.0,
            child: Container(
              width: 2,
              height: 16,
              color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
            ),
          );
        },
      ),
    );
  }

  void _showFullImage(BuildContext context, String base64) {
    showDialog(
      context: context,
      builder: (_) => GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Dialog(
          backgroundColor: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.memory(_decodeBase64(base64), fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  Uint8List _decodeBase64(String base64) {
    final clean = base64.contains(',') ? base64.split(',').last : base64;
    return base64Decode(clean);
  }
}
