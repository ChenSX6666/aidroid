import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'phone_control_service.dart';
import 'ui_tree_parser.dart';
import 'experience_service.dart';
import 'log_service.dart';

class UIFrame {
  final String xml;
  final DateTime timestamp;
  final int index;
  final String changeDesc;

  const UIFrame({
    required this.xml,
    required this.timestamp,
    required this.index,
    required this.changeDesc,
  });
}

class ActionRecorder {
  static final ActionRecorder _instance = ActionRecorder._();
  factory ActionRecorder() => _instance;
  ActionRecorder._();

  bool _isRecording = false;
  bool get isRecording => _isRecording;

  String _task = '';
  String get task => _task;

  Timer? _pollTimer;
  String? _prevXml;
  final List<UIFrame> _frames = [];
  int _frameIndex = 0;

  void Function(String status)? onStatusChange;

  static const _analyzePrompt = '''分析以下手机操作录制数据，提取抽象操作计划。

任务: {task}

录制帧 (共 {frameCount} 帧，展示关键 UI 变化):

{frameDescriptions}

请分析以上 UI 变化序列，推理用户手动执行了什么操作，并生成一个抽象操作计划。

回复格式:
```
计划: 1. 步骤一  2. 步骤二  ...
抽象: 可复用的通用模式描述
变通: 这个模式如何在其他应用/场景中适配(以一反三)
```''';

  Future<void> start(String task) async {
    _task = task;
    _isRecording = true;
    _frames.clear();
    _frameIndex = 0;
    _prevXml = null;
    LogService.info('录制开始: $task');
    onStatusChange?.call('录制中...');
    _pollTimer = Timer.periodic(const Duration(milliseconds: 400), (_) => _poll());
  }

  Future<void> stop() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    _isRecording = false;
    _prevXml = null;
    LogService.info('录制停止，共 ${_frames.length} 帧');
    onStatusChange?.call('录制完成');
  }

  Future<void> _poll() async {
    if (!_isRecording) return;
    try {
      final xml = await PhoneControlService.dumpUI();
      if (!xml.contains('<?xml')) return;

      if (_prevXml == null) {
        _prevXml = xml;
        _frames.add(UIFrame(
          xml: xml,
          timestamp: DateTime.now(),
          index: _frameIndex++,
          changeDesc: '初始状态',
        ));
        return;
      }

      final changeHint = _detectFrameChange(_prevXml!, xml);
      if (changeHint != null) {
        _frames.add(UIFrame(
          xml: xml,
          timestamp: DateTime.now(),
          index: _frameIndex++,
          changeDesc: changeHint,
        ));
        _prevXml = xml;
      }
    } catch (_) {}
  }

  String? _detectFrameChange(String before, String after) {
    if (before == after) return null;

    final beforeElements = UITreeParser.parse(before);
    final afterElements = UITreeParser.parse(after);
    final diff = afterElements.length - beforeElements.length;

    if (diff > 5) return '新增 $diff 个元素，可能新页面';
    if (diff < -5) return '减少 ${-diff} 个元素，可能跳转';

    final beforeTexts = beforeElements.map((e) => e.label).where((l) => l.isNotEmpty).toSet();
    final afterTexts = afterElements.map((e) => e.label).where((l) => l.isNotEmpty).toSet();
    final newTexts = afterTexts.difference(beforeTexts);
    final lostTexts = beforeTexts.difference(afterTexts);

    if (newTexts.isEmpty && lostTexts.isEmpty) return null;

    final parts = <String>[];
    if (newTexts.isNotEmpty) parts.add('新增: ${newTexts.take(3).join(", ")}');
    if (lostTexts.isNotEmpty) parts.add('消失: ${lostTexts.take(3).join(", ")}');
    return parts.join('; ');
  }

  Future<({String plan, String abstract, String generalize})> analyzeAndSave({
    required String apiKey,
    required String providerId,
    required String modelId,
  }) async {
    if (_frames.isEmpty) {
      return (plan: '', abstract: '', generalize: '');
    }

    // Build frame descriptions
    final frameBuf = StringBuffer();
    final displaySize = await PhoneControlService.getDisplaySize();
    for (final f in _frames.take(30)) {
      final desc = UITreeParser.buildScreenDescription(f.xml, displaySize);
      frameBuf.writeln('--- 帧 ${f.index}: ${f.changeDesc} ---');
      // Truncate per frame to save tokens
      final lines = desc.split('\n');
      for (final line in lines.take(20)) {
        frameBuf.writeln(line);
      }
      frameBuf.writeln();
    }

    final prompt = _analyzePrompt
        .replaceAll('{task}', _task)
        .replaceAll('{frameCount}', '${_frames.length}')
        .replaceAll('{frameDescriptions}', frameBuf.toString());

    const hosts = {
      'deepseek': 'https://api.deepseek.com/v1',
      'openai': 'https://api.openai.com/v1',
      'openrouter': 'https://openrouter.ai/api/v1',
      'nvidia': 'https://integrate.api.nvidia.com/v1',
      'xai': 'https://api.x.ai/v1',
      'chuying': 'https://open.bigmodel.cn/api/paas/v4',
      'xiaomi': 'https://api.xiaomimimo.com/v1',
    };

    final host = hosts[providerId] ?? hosts['deepseek']!;

    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 60),
      ));

      final response = await dio.post(
        '$host/chat/completions',
        data: {
          'model': modelId,
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
          'stream': false,
          'temperature': 0.3,
          'max_tokens': 1024,
        },
        options: Options(headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        }),
      );

      final text = response.data?['choices']?[0]?['message']?['content'] as String? ?? '';

      String plan = '';
      String abstract = '';
      String generalize = '';

      final planMatch = RegExp(r'计划:\s*(.+)').firstMatch(text);
      if (planMatch != null) plan = planMatch.group(1)!.trim();

      final abstractMatch = RegExp(r'抽象:\s*(.+)').firstMatch(text);
      if (abstractMatch != null) abstract = abstractMatch.group(1)!.trim();

      final generalizeMatch = RegExp(r'变通:\s*(.+)').firstMatch(text);
      if (generalizeMatch != null) generalize = generalizeMatch.group(1)!.trim();

      // Save to knowledge base
      await ExperienceService.saveRecording(
        task: _task,
        plan: plan.isNotEmpty ? plan : text,
        abstract: abstract,
        generalize: generalize,
        frameCount: _frames.length,
      );

      LogService.info('录制分析完成: plan=${plan.length}chars, abstract=${abstract.length}chars');
      return (plan: plan, abstract: abstract, generalize: generalize);
    } catch (e) {
      LogService.error('录制分析失败: $e');
      // Still save raw recording even if analysis fails
      await ExperienceService.saveRecording(
        task: _task,
        plan: '录制 ${_frames.length} 帧，分析失败: $e',
        abstract: '',
        generalize: '',
        frameCount: _frames.length,
      );
      return (plan: '', abstract: '', generalize: '');
    }
  }
}
