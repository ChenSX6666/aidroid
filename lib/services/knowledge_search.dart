import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

class KnowledgeEntry {
  final String task;
  final String plan;
  final String abstract;
  final String generalize;
  final String filePath;
  final double relevance;

  const KnowledgeEntry({
    required this.task,
    required this.plan,
    required this.abstract,
    required this.generalize,
    required this.filePath,
    this.relevance = 0,
  });
}

class KnowledgeSearch {
  static const _baseDir = '/storage/emulated/0/aidroid/knowledge';

  /// Search knowledge base for tasks similar to [query].
  /// Returns up to 2 best matches sorted by relevance.
  static Future<List<KnowledgeEntry>> search(String query) async {
    final dir = Directory(_baseDir);
    if (!await dir.exists()) return [];

    final files = await dir.list().toList();
    final entries = <KnowledgeEntry>[];

    for (final entity in files) {
      if (entity is! File || !entity.path.endsWith('.md')) continue;
      try {
        final content = await entity.readAsString();
        final entry = _parseEntry(content, entity.path);
        if (entry != null) {
          final relevance = _score(query.toLowerCase(), entry);
          if (relevance > 0) {
            entries.add(KnowledgeEntry(
              task: entry.task,
              plan: entry.plan,
              abstract: entry.abstract,
              generalize: entry.generalize,
              filePath: entity.path,
              relevance: relevance,
            ));
          }
        }
      } catch (_) {}
    }

    entries.sort((a, b) => b.relevance.compareTo(a.relevance));
    return entries.take(2).toList();
  }

  static ({String task, String plan, String abstract, String generalize})? _parseEntry(
    String content, String path) {
    String task = '';
    String plan = '';
    String abstract = '';
    String generalize = '';

    // Parse frontmatter
    final taskMatch = RegExp(r'^task:\s*(.+)$', multiLine: true).firstMatch(content);
    if (taskMatch != null) task = taskMatch.group(1)!.trim();

    // Parse plan section
    final planMatch = RegExp(r'^plan:\s*(.+)$', multiLine: true).firstMatch(content);
    if (planMatch != null) plan = planMatch.group(1)!.trim();

    // Parse abstract section
    final abstractMatch = RegExp(r'^abstract:\s*(.+)$', multiLine: true).firstMatch(content);
    if (abstractMatch != null) abstract = abstractMatch.group(1)!.trim();

    // Parse generalize section
    final generalizeMatch = RegExp(r'^generalize:\s*((?:.|\n)*?)(?:^---|\z)', multiLine: true).firstMatch(content);
    if (generalizeMatch != null) {
      generalize = generalizeMatch.group(1)!.trim();
    }

    if (task.isEmpty) {
      // Try extracting title from markdown heading
      final headingMatch = RegExp(r'^#\s*(.+)$', multiLine: true).firstMatch(content);
      if (headingMatch != null) task = headingMatch.group(1)!.trim();
    }

    if (task.isEmpty) return null;
    return (task: task, plan: plan, abstract: abstract, generalize: generalize);
  }

  /// Simple keyword relevance scoring
  static double _score(String queryLower, ({String task, String plan, String abstract, String generalize}) entry) {
    double score = 0;
    final queryWords = queryLower.split(RegExp(r'[\s,，。、]+')).where((w) => w.length > 1).toList();

    for (final word in queryWords) {
      if (entry.task.toLowerCase().contains(word)) score += 3;
      if (entry.plan.toLowerCase().contains(word)) score += 2;
      if (entry.abstract.toLowerCase().contains(word)) score += 2;
      if (entry.generalize.toLowerCase().contains(word)) score += 1;
    }

    // Bonus for shared action keywords
    const actionKeywords = ['打开', '发送', '搜索', '点击', '输入', '滑动', '下载', '播放',
      'open', 'send', 'search', 'tap', 'input', 'swipe', 'download', 'play'];
    for (final kw in actionKeywords) {
      if (queryLower.contains(kw) && entry.task.toLowerCase().contains(kw)) {
        score += 1;
      }
    }

    return score;
  }
}
