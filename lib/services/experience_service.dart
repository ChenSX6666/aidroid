import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

class AgentStepRecord {
  final int step;
  final String action;
  final String target;
  final String reason;
  final bool success;
  final String? error;

  const AgentStepRecord({
    required this.step,
    required this.action,
    required this.target,
    required this.reason,
    this.success = true,
    this.error,
  });
}

class ExperienceService {
  static const String baseDir = '/storage/emulated/0/aidroid/knowledge';
  static bool _recordingEnabled = true;
  static bool _loaded = false;

  static bool get recordingEnabled => _recordingEnabled;

  static Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _recordingEnabled = prefs.getBool('experience_recording') ?? true;
    _loaded = true;
  }

  static Future<void> setRecordingEnabled(bool v) async {
    _recordingEnabled = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('experience_recording', v);
  }

  static Future<void> generateKnowledgeBase({
    required String task,
    required List<AgentStepRecord> steps,
  }) async {
    await _ensureLoaded();
    if (!_recordingEnabled || steps.isEmpty) return;

    try {
      final dir = Directory(baseDir);
      if (!await dir.exists()) await dir.create(recursive: true);

      final now = DateTime.now();
      final safeTitle = task.length > 30 ? '${task.substring(0, 30)}' : task;
      final safeName = safeTitle.replaceAll(RegExp(r'[\\/:*?"<>|\s]'), '_');
      final timestamp = now.toIso8601String().replaceAll(':', '-').substring(0, 19);
      final file = File('$baseDir/${safeName}_$timestamp.md');

      final buf = StringBuffer();
      buf.writeln('---');
      buf.writeln('task: $task');
      buf.writeln('date: ${now.toIso8601String().substring(0, 19)}');
      buf.writeln('steps: ${steps.length}');
      buf.writeln('success: ${steps.every((s) => s.success)}');
      buf.writeln('---');
      buf.writeln();
      buf.writeln('# $task');
      buf.writeln();
      buf.writeln('> 执行时间: ${now.toIso8601String().substring(0, 19)}');
      buf.writeln('> 总步数: ${steps.length}');
      buf.writeln('> 成功率: ${steps.where((s) => s.success).length}/${steps.length}');
      buf.writeln();

      for (final s in steps) {
        buf.writeln('## 步骤 ${s.step}: ${s.action}');
        buf.writeln();
        buf.writeln('- 动作: ${s.action}');
        buf.writeln('- 目标: ${s.target}');
        buf.writeln('- 原因: ${s.reason}');
        buf.writeln('- 结果: ${s.success ? "成功" : "失败"}');
        if (s.error != null) buf.writeln('- 错误: ${s.error}');
        buf.writeln();
      }

      buf.writeln('---');
      buf.writeln();
      buf.writeln('*由 Aidroid 自动生成*');

      await file.writeAsString(buf.toString());
    } catch (_) {
      // Silently fail — don't block the main flow for KB writing
    }
  }

  static Future<List<FileSystemEntity>> listKnowledgeFiles() async {
    final dir = Directory(baseDir);
    if (!await dir.exists()) return [];
    final entities = dir.listSync();
    entities.sort((a, b) {
      final aStat = a.statSync();
      final bStat = b.statSync();
      return bStat.modified.compareTo(aStat.modified);
    });
    return entities;
  }

  static Future<String> exportAll() async {
    final dir = Directory(baseDir);
    if (!await dir.exists()) return '';

    final exportDir = Directory('/storage/emulated/0/Download/aidroid');
    if (!await exportDir.exists()) await exportDir.create(recursive: true);

    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
    final exportFile = File('${exportDir.path}/knowledge_export_$timestamp.md');
    final buf = StringBuffer();

    buf.writeln('# Aidroid 知识库导出');
    buf.writeln();
    buf.writeln('> 导出时间: ${DateTime.now().toIso8601String().substring(0, 19)}');
    buf.writeln();

    final files = await listKnowledgeFiles();
    for (final entity in files) {
      if (entity is File && entity.path.endsWith('.md')) {
        buf.writeln(await entity.readAsString());
        buf.writeln();
      }
    }

    await exportFile.writeAsString(buf.toString());
    return exportFile.path;
  }

  static Future<int> importFrom(File file) async {
    if (!await file.exists()) return 0;

    final dir = Directory(baseDir);
    if (!await dir.exists()) await dir.create(recursive: true);

    final content = await file.readAsString();
    // Split by markdown frontmatter sections
    final sections = content.split(RegExp(r'(?=^---$)'));
    int count = 0;

    for (final section in sections) {
      final trimmed = section.trim();
      if (trimmed.isEmpty || !trimmed.contains('task:')) continue;
      final targetFile = File('$baseDir/import_${DateTime.now().millisecondsSinceEpoch}_$count.md');
      await targetFile.writeAsString(trimmed);
      count++;
    }

    return count;
  }

  static Future<({int fileCount, String totalSize, String lastUpdate})> getStats() async {
    final dir = Directory(baseDir);
    if (!await dir.exists()) {
      return (fileCount: 0, totalSize: '0 KB', lastUpdate: '暂无');
    }

    final entities = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.md')).toList();
    int totalBytes = 0;
    DateTime? latest;

    for (final f in entities) {
      totalBytes += await f.length();
      final modified = await f.lastModified();
      if (latest == null || modified.isAfter(latest)) {
        latest = modified;
      }
    }

    String sizeStr;
    if (totalBytes < 1024) {
      sizeStr = '$totalBytes B';
    } else if (totalBytes < 1024 * 1024) {
      sizeStr = '${(totalBytes / 1024).toStringAsFixed(1)} KB';
    } else {
      sizeStr = '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }

    return (
      fileCount: entities.length,
      totalSize: sizeStr,
      lastUpdate: latest != null ? latest.toString().substring(0, 19) : '暂无',
    );
  }

  static Future<void> clearAll() async {
    final dir = Directory(baseDir);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// Save a recording-based knowledge entry
  static Future<void> saveRecording({
    required String task,
    required String plan,
    required String abstract,
    required String generalize,
    required int frameCount,
  }) async {
    await _ensureLoaded();
    if (!_recordingEnabled) return;

    try {
      final dir = Directory(baseDir);
      if (!await dir.exists()) await dir.create(recursive: true);

      final now = DateTime.now();
      final safeTitle = task.length > 30 ? '${task.substring(0, 30)}' : task;
      final safeName = safeTitle.replaceAll(RegExp(r'[\\/:*?"<>|\s]'), '_');
      final timestamp = now.toIso8601String().replaceAll(':', '-').substring(0, 19);
      final file = File('$baseDir/${safeName}_$timestamp.md');

      final buf = StringBuffer();
      buf.writeln('---');
      buf.writeln('task: $task');
      buf.writeln('plan: $plan');
      buf.writeln('abstract: $abstract');
      buf.writeln('generalize: $generalize');
      buf.writeln('date: ${now.toIso8601String().substring(0, 19)}');
      buf.writeln('frames: $frameCount');
      buf.writeln('source: recording');
      buf.writeln('---');
      buf.writeln();
      buf.writeln('# $task');
      buf.writeln();
      if (plan.isNotEmpty) {
        buf.writeln('## 计划');
        buf.writeln(plan);
        buf.writeln();
      }
      if (abstract.isNotEmpty) {
        buf.writeln('## 抽象模式');
        buf.writeln(abstract);
        buf.writeln();
      }
      if (generalize.isNotEmpty) {
        buf.writeln('## 以一反三');
        buf.writeln(generalize);
        buf.writeln();
      }
      buf.writeln('---');
      buf.writeln();
      buf.writeln('*由 Aidroid 录制学习生成*');

      await file.writeAsString(buf.toString());
    } catch (_) {}
  }
}
