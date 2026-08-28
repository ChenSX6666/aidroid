import 'dart:convert';
import 'native_bridge.dart';

class BrowserElement {
  final int idx;
  final String type;
  final String text;
  final String href;

  BrowserElement({required this.idx, required this.type, required this.text, required this.href});

  factory BrowserElement.fromJson(Map<String, dynamic> json) => BrowserElement(
        idx: (json['idx'] as num?)?.toInt() ?? 0,
        type: json['type'] as String? ?? 'button',
        text: json['text'] as String? ?? '',
        href: json['href'] as String? ?? '',
      );

  /// Label for the LLM: e.g. `[1] 按钮: 搜索` or `[2] 链接: 新闻`
  String get label {
    final label = text.isNotEmpty ? text : (href.isNotEmpty ? href : '(无文本)');
    final typeName = switch (type) {
      'a' => '链接',
      'input' => '输入框',
      'textarea' => '输入框',
      'select' => '下拉',
      _ => '按钮',
    };
    return '[$idx] $typeName: $label';
  }
}

class BrowserService {
  /// Open a page in the WebView browser. Returns true on success.
  static Future<bool> open(String url) async {
    return NativeBridge.browserOpen(url);
  }

  /// Extract the interactive element list from the current page.
  static Future<List<BrowserElement>> getStructure() async {
    final raw = await NativeBridge.browserGetStructure();
    if (raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => BrowserElement.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Compact single-line description of the page for the LLM prompt.
  static Future<String> getStructureAsText() async {
    final els = await getStructure();
    if (els.isEmpty) return '（页面无可交互元素，或浏览器未打开）';
    final lines = els.map((e) => e.label).take(60).toList();
    return '页面可交互元素:\n${lines.join('\n')}';
  }

  static Future<bool> click(int index) async {
    return NativeBridge.browserClick(index);
  }

  static Future<bool> input(int index, String text) async {
    return NativeBridge.browserInput(index, text);
  }

  static Future<bool> scroll(String direction) async {
    return NativeBridge.browserScroll(direction);
  }
}
