import 'dart:convert';
import 'package:dio/dio.dart';
import 'log_service.dart';

/// Web search skill for the Agent — uses DuckDuckGo (free, no API key)
class WebSearchService {
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    headers: {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36',
    },
  ));

  /// Search DuckDuckGo and return formatted results
  static Future<String> search(String query, {int maxResults = 5}) async {
    try {
      // Use DuckDuckGo Lite for easy parsing
      final response = await _dio.get(
        'https://lite.duckduckgo.com/lite/',
        queryParameters: {'q': query},
      );

      final html = response.data as String;
      final results = _parseLiteResults(html, maxResults);

      if (results.isEmpty) {
        return '搜索"$query"未找到结果';
      }

      final buf = StringBuffer('搜索"$query"的结果:\n\n');
      for (int i = 0; i < results.length; i++) {
        final r = results[i];
        buf.writeln('${i + 1}. ${r['title']}');
        if (r['snippet'] != null && r['snippet']!.isNotEmpty) {
          buf.writeln('   ${r['snippet']}');
        }
        if (r['url'] != null && r['url']!.isNotEmpty) {
          buf.writeln('   ${r['url']}');
        }
        buf.writeln();
      }
      return buf.toString().trim();
    } catch (e) {
      LogService.error('WebSearch error: $e');
      // Fallback: try DuckDuckGo instant answer API
      return _instantAnswer(query);
    }
  }

  /// Fetch a URL and return its text content
  static Future<String> fetchUrl(String url, {int maxChars = 5000}) async {
    try {
      final response = await _dio.get(url);
      final html = response.data as String;
      // Simple HTML to text: strip tags
      final text = html
          .replaceAll(RegExp(r'<script[^>]*>[\s\S]*?</script>', caseSensitive: false), '')
          .replaceAll(RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false), '')
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (text.length > maxChars) {
        return '${text.substring(0, maxChars)}...(已截断)';
      }
      return text.isEmpty ? '页面内容为空' : text;
    } catch (e) {
      LogService.error('FetchUrl error: $e');
      return '获取网页失败: $e';
    }
  }

  /// Parse DuckDuckGo Lite HTML results
  static List<Map<String, String>> _parseLiteResults(String html, int max) {
    final results = <Map<String, String>>[];
    // Lite page has results in <a class="result-link"> and snippets in <td class="result-snippet">
    final linkPattern = RegExp(r'<a[^>]+class="result-link"[^>]*href="([^"]*)"[^>]*>(.*?)</a>', dotAll: true);
    final snippetPattern = RegExp(r'<td\s+class="result-snippet"[^>]*>(.*?)</td>', dotAll: true);

    final links = linkPattern.allMatches(html).toList();
    final snippets = snippetPattern.allMatches(html).toList();

    for (int i = 0; i < links.length && i < max; i++) {
      final url = links[i].group(1) ?? '';
      final title = _stripHtml(links[i].group(2) ?? '');
      final snippet = i < snippets.length ? _stripHtml(snippets[i].group(1) ?? '') : '';
      if (title.isNotEmpty) {
        results.add({'title': title, 'url': url, 'snippet': snippet});
      }
    }
    return results;
  }

  /// Fallback: DuckDuckGo Instant Answer API
  static Future<String> _instantAnswer(String query) async {
    try {
      final response = await _dio.get(
        'https://api.duckduckgo.com/',
        queryParameters: {'q': query, 'format': 'json', 'no_html': 1},
      );
      final data = response.data is String ? jsonDecode(response.data) : response.data;
      final buf = StringBuffer('搜索"$query":\n');

      final answer = data['AbstractText'] as String?;
      if (answer != null && answer.isNotEmpty) {
        buf.writeln(answer);
        if (data['AbstractURL'] != null) buf.writeln('来源: ${data['AbstractURL']}');
        return buf.toString();
      }

      final related = data['RelatedTopics'] as List?;
      if (related != null && related.isNotEmpty) {
        for (int i = 0; i < related.length && i < 5; i++) {
          final topic = related[i];
          if (topic is Map && topic['Text'] != null) {
            buf.writeln('- ${topic['Text']}');
          }
        }
        return buf.toString();
      }

      return '搜索"$query"未找到直接结果，请尝试用浏览器搜索';
    } catch (e) {
      return '搜索失败: $e';
    }
  }

  static String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ')
        .trim();
  }
}
