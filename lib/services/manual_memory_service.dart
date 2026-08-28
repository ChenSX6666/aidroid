import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ManualMemory {
  final String id;
  final String content;
  final String createdAt;

  ManualMemory({required this.id, required this.content, required this.createdAt});

  Map<String, dynamic> toJson() =>
      {'id': id, 'content': content, 'createdAt': createdAt};

  static ManualMemory fromJson(Map<String, dynamic> json) => ManualMemory(
        id: json['id'] as String? ?? '',
        content: json['content'] as String? ?? '',
        createdAt: json['createdAt'] as String? ?? '',
      );
}

class ManualMemoryService {
  static const _prefKey = 'manual_memories';
  static List<ManualMemory>? _cache;

  static Future<List<ManualMemory>> getAll() async {
    if (_cache != null) return _cache!;
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_prefKey);
      if (json != null) {
        final decoded = jsonDecode(json) as List<dynamic>;
        _cache = decoded
            .map((e) => ManualMemory.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    _cache ??= [];
    return _cache!;
  }

  static Future<void> addMemory(String content) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;
    final list = await getAll();
    final now = DateTime.now();
    final ts = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    list.insert(
      0,
      ManualMemory(
        id: now.microsecondsSinceEpoch.toString(),
        content: trimmed,
        createdAt: ts,
      ),
    );
    await _save(list);
  }

  static Future<void> removeMemory(String id) async {
    final list = await getAll();
    list.removeWhere((m) => m.id == id);
    await _save(list);
  }

  static Future<void> _save(List<ManualMemory> list) async {
    _cache = list;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefKey,
        jsonEncode(list.map((m) => m.toJson()).toList()),
      );
    } catch (_) {}
  }

  /// Format memories for injection into system prompt.
  static String getAsText(List<ManualMemory> memories) {
    if (memories.isEmpty) return '';
    final sb = StringBuffer('用户记忆:\n');
    for (final m in memories) {
      sb.writeln('- ${m.content}');
    }
    return sb.toString().trimRight();
  }
}
