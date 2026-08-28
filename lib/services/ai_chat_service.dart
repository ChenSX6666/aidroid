import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/conversation.dart';
import '../models/custom_ai_provider.dart';

enum _ApiFormat { openaiCompatible, anthropic, gemini }

class _ProviderConfig {
  final String host;
  final String endpoint;
  final String? authHeader;
  final String authPrefix;
  final Map<String, String> extraHeaders;
  final _ApiFormat format;

  const _ProviderConfig({
    required this.host,
    required this.endpoint,
    this.authHeader = 'Authorization',
    this.authPrefix = 'Bearer ',
    this.extraHeaders = const {},
    this.format = _ApiFormat.openaiCompatible,
  });

  String get url => '$host$endpoint';
}

class AiChatService {
  final Dio _dio;

  AiChatService()
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 180),
          responseType: ResponseType.stream,
        ));

  static const _providers = {
    'deepseek': _ProviderConfig(
      host: 'https://api.deepseek.com/v1',
      endpoint: '/chat/completions',
    ),
    'openai': _ProviderConfig(
      host: 'https://api.openai.com/v1',
      endpoint: '/chat/completions',
    ),
    'anthropic': _ProviderConfig(
      host: 'https://api.anthropic.com/v1',
      endpoint: '/messages',
      authHeader: 'x-api-key',
      authPrefix: '',
      extraHeaders: {
        'anthropic-version': '2023-06-01',
        'anthropic-beta': 'token-efficient-tools-2025-02-19',
      },
      format: _ApiFormat.anthropic,
    ),
    'google': _ProviderConfig(
      host: 'https://generativelanguage.googleapis.com/v1beta',
      endpoint: '',
      authHeader: null,
      authPrefix: '',
      format: _ApiFormat.gemini,
    ),
    'openrouter': _ProviderConfig(
      host: 'https://openrouter.ai/api/v1',
      endpoint: '/chat/completions',
      extraHeaders: {'HTTP-Referer': 'https://aidroid.app'},
    ),
    'nvidia': _ProviderConfig(
      host: 'https://integrate.api.nvidia.com/v1',
      endpoint: '/chat/completions',
    ),
    'xai': _ProviderConfig(
      host: 'https://api.x.ai/v1',
      endpoint: '/chat/completions',
    ),
    'chuying': _ProviderConfig(
      host: 'https://open.bigmodel.cn/api/paas/v4',
      endpoint: '/chat/completions',
    ),
    'xiaomi': _ProviderConfig(
      host: 'https://api.xiaomimimo.com/v1',
      endpoint: '/chat/completions',
    ),
    };

  Future<_ProviderConfig> _configAsync(String providerId) async {
    if (_providers.containsKey(providerId)) return _providers[providerId]!;
    if (providerId.startsWith(CustomAiProvider.idPrefix)) {
      final customs = await CustomAiProvider.loadAll();
      for (final c in customs) {
        if (c.id == providerId) return _customConfig(c);
      }
    }
    return _providers['deepseek']!;
  }

  /// Agent 请求用：返回 provider 的 host、endpoint、认证头等配置
  static Future<({
    String host,
    String endpoint,
    String? authHeader,
    String authPrefix,
    Map<String, String> extraHeaders,
    bool openAiCompatible,
  })> resolveEndpoint(String providerId) async {
    final s = AiChatService();
    final c = await s._configAsync(providerId);
    return (
      host: c.host,
      endpoint: c.endpoint,
      authHeader: c.authHeader,
      authPrefix: c.authPrefix,
      extraHeaders: c.extraHeaders,
      openAiCompatible: c.format == _ApiFormat.openaiCompatible,
    );
  }

  static _ProviderConfig _customConfig(CustomAiProvider c) {
    final host = c.resolveHost();
    switch (c.apiFormat) {
      case 'anthropic':
        return _ProviderConfig(
          host: host,
          endpoint: '/messages',
          authHeader: _authHeader(c.authField),
          authPrefix: _authPrefix(c.authField),
          extraHeaders: {
            'anthropic-version': '2023-06-01',
            'anthropic-beta': 'token-efficient-tools-2025-02-19',
          },
          format: _ApiFormat.anthropic,
        );
      case 'gemini':
        return _ProviderConfig(
          host: host,
          endpoint: '',
          authHeader: null,
          authPrefix: '',
          format: _ApiFormat.gemini,
        );
      default:
        return _ProviderConfig(
          host: host,
          endpoint: '/chat/completions',
          authHeader: _authHeader(c.authField),
          authPrefix: _authPrefix(c.authField),
        );
    }
  }

  static String? _authHeader(String field) {
    switch (field) {
      case 'x_api_key':
        return 'x-api-key';
      case 'auth_token':
        return 'ANTHROPIC_AUTH_TOKEN';
      default:
        return 'Authorization';
    }
  }

  static String _authPrefix(String field) => field == 'authorization' ? 'Bearer ' : '';

  Future<({String content, String reasoning})> sendMessage({
    required String providerId,
    required String modelId,
    required String apiKey,
    required List<Message> history,
    String? systemPrompt,
    String? imageBase64,
    required void Function(String chunk) onChunk,
    void Function(String reasoning)? onReasoning,
  }) async {
    final config = await _configAsync(providerId);

    switch (config.format) {
      case _ApiFormat.openaiCompatible:
        return _sendOpenAi(providerId, config, modelId, apiKey, history, systemPrompt, imageBase64, onChunk, onReasoning);
      case _ApiFormat.anthropic:
        return _sendAnthropic(config, modelId, apiKey, history, systemPrompt, imageBase64, onChunk);
      case _ApiFormat.gemini:
        return _sendGemini(config, modelId, apiKey, history, systemPrompt, imageBase64, onChunk);
    }
  }

  // ── OpenAI-compatible ──

  Future<({String content, String reasoning})> _sendOpenAi(
    String providerId,
    _ProviderConfig config,
    String modelId,
    String apiKey,
    List<Message> history,
    String? systemPrompt,
    String? imageBase64,
    void Function(String) onChunk,
    void Function(String)? onReasoning,
  ) async {
    final messages = <Map<String, dynamic>>[];
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      messages.add({'role': 'system', 'content': systemPrompt});
    }

    for (int i = 0; i < history.length; i++) {
      final msg = history[i];
      final isLast = i == history.length - 1;
      final role = msg.role == MessageRole.user ? 'user' : 'assistant';

      if (isLast && role == 'user' && imageBase64 != null) {
        messages.add({
          'role': role,
          'content': msg.contentParts,
        });
      } else {
        final msgMap = <String, dynamic>{
          'role': role,
          'content': msg.content,
        };
        // DeepSeek V4 requires reasoning_content to be passed back in multi-turn conversations
        if (providerId == 'deepseek' && role == 'assistant') {
          msgMap['reasoning_content'] = msg.reasoningContent ?? '';
        }
        messages.add(msgMap);
      }
    }

    final body = <String, dynamic>{
      'model': modelId,
      'messages': messages,
      'stream': true,
      'temperature': 0.7,
      'max_tokens': 8192,
    };

    // OpenAI / xAI: 内置联网搜索
    if (providerId == 'openai' || providerId == 'xai') {
      body['tools'] = [{'type': 'web_search_preview'}];
    }

    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (config.authHeader != null) config.authHeader!: '${config.authPrefix}$apiKey',
      ...config.extraHeaders,
    };

    final response = await _dio.post(
      config.url,
      data: body,
      options: Options(headers: headers),
    );

    return _streamOpenAi(response, onChunk, onReasoning);
  }

  String _extractThinkContent(String chunk, StringBuffer thinkBuf, void Function(String)? onReasoning) {
    final result = StringBuffer();
    int i = 0;
    while (i < chunk.length) {
      if (chunk.substring(i).startsWith('&lt;think&gt;') || chunk.substring(i).startsWith('<think>')) {
        final tagLen = chunk.substring(i).startsWith('&lt;think&gt;') ? 12 : 7;
        i += tagLen;
        final closeHtml = '&lt;/think&gt;';
        final closePlain = '</think>';
        String? closeTag;
        int endIdx = -1;
        if (chunk.indexOf(closeHtml, i) >= 0) {
          closeTag = closeHtml;
          endIdx = chunk.indexOf(closeHtml, i);
        } else if (chunk.indexOf(closePlain, i) >= 0) {
          closeTag = closePlain;
          endIdx = chunk.indexOf(closePlain, i);
        }
        if (closeTag != null && endIdx >= 0) {
          final thinkText = chunk.substring(i, endIdx);
          thinkBuf.write(thinkText);
          onReasoning?.call(thinkText);
          i = endIdx + closeTag.length;
          continue;
        }
        final thinkText = chunk.substring(i);
        thinkBuf.write(thinkText);
        onReasoning?.call(thinkText);
        i = chunk.length;
      } else if (chunk.substring(i).startsWith('<') || chunk.substring(i).startsWith('&')) {
        // check if this could be a partial tag
        final rest = chunk.substring(i);
        final partials = ['<think>', '<thi', '<th', '<t', '&lt;think&gt;', '&lt;th', '&lt;t', '&lt;', '&l', '&'];
        bool isPartial = false;
        for (final p in partials) {
          if (rest.length <= p.length && p.startsWith(rest)) {
            _pendingText = rest;
            isPartial = true;
            break;
          }
        }
        if (!isPartial) {
          result.write(chunk[i]);
          i++;
        } else {
          i = chunk.length;
        }
      } else {
        result.write(chunk[i]);
        i++;
      }
    }
    return result.toString();
  }

  String _pendingText = '';

  Future<({String content, String reasoning})> _streamOpenAi(
    Response response,
    void Function(String) onChunk,
    void Function(String)? onReasoning,
  ) async {
    final contentBuffer = StringBuffer();
    final reasoningBuffer = StringBuffer();
    final thinkBuffer = StringBuffer();
    final stream = (response.data as ResponseBody).stream;
    String lineBuffer = '';
    _pendingText = '';

    void processEvents() {
      // Normalize \r\n → \n for consistent parsing
      lineBuffer = lineBuffer.replaceAll('\r\n', '\n');
      while (lineBuffer.contains('\n\n')) {
        final eventEnd = lineBuffer.indexOf('\n\n');
        final event = lineBuffer.substring(0, eventEnd);
        lineBuffer = lineBuffer.substring(eventEnd + 2);
        for (final line in event.split('\n')) {
          if (line.startsWith('data: ') && line != 'data: [DONE]') {
            try {
              final json = jsonDecode(line.substring(6));
              final delta = json['choices']?[0]?['delta'];
              if (delta != null) {
                final rawContent = delta['content'] as String?;
                if (rawContent != null && rawContent.isNotEmpty) {
                  final combined = '$_pendingText$rawContent';
                  _pendingText = '';
                  final cleanContent = _extractThinkContent(combined, thinkBuffer, onReasoning);
                  if (cleanContent.isNotEmpty) {
                    contentBuffer.write(cleanContent);
                    onChunk(cleanContent);
                  }
                }
                var reasoningContent = delta['reasoning_content'] as String?;
                reasoningContent ??= delta['thinking'] as String?;
                reasoningContent ??= json['choices']?[0]?['reasoning_content'] as String?;
                reasoningContent ??= json['choices']?[0]?['delta']?['thinking'] as String?;
                if (reasoningContent != null && reasoningContent.isNotEmpty) {
                  reasoningBuffer.write(reasoningContent);
                  onReasoning?.call(reasoningContent);
                }
              }
            } catch (_) {}
          }
        }
      }
    }

    await for (final chunk in stream) {
      lineBuffer += utf8.decode(chunk);
      processEvents();
      // Yield to event loop so Flutter can render the frame
      await Future.delayed(const Duration(milliseconds: 1));
    }

    // Process any remaining data after stream ends
    if (lineBuffer.isNotEmpty) {
      processEvents();
    }

    final finalReasoning = reasoningBuffer.isNotEmpty
        ? reasoningBuffer.toString()
        : thinkBuffer.toString();
    return (content: contentBuffer.toString(), reasoning: finalReasoning);
  }

  // ── Anthropic ──

  Future<({String content, String reasoning})> _sendAnthropic(
    _ProviderConfig config,
    String modelId,
    String apiKey,
    List<Message> history,
    String? systemPrompt,
    String? imageBase64,
    void Function(String) onChunk,
  ) async {
    final messages = <Map<String, dynamic>>[];
    for (int i = 0; i < history.length; i++) {
      final msg = history[i];
      final isLast = i == history.length - 1;
      final role = msg.role == MessageRole.user ? 'user' : 'assistant';

      if (isLast && role == 'user' && imageBase64 != null) {
        final rawBase64 = imageBase64.contains(',') ? imageBase64.split(',').last : imageBase64;
        final mediaType = imageBase64.contains('image/')
            ? RegExp(r'data:(image/\w+);').firstMatch(imageBase64)?.group(1) ?? 'image/jpeg'
            : 'image/jpeg';
        messages.add({
          'role': role,
          'content': [
            if (msg.content.isNotEmpty) {'type': 'text', 'text': msg.content},
            {
              'type': 'image',
              'source': {'type': 'base64', 'media_type': mediaType, 'data': rawBase64},
            },
          ],
        });
      } else {
        messages.add({'role': role, 'content': msg.content});
      }
    }

    final body = <String, dynamic>{
      'model': modelId,
      'messages': messages,
      'max_tokens': 8192,
      'stream': true,
      'tools': [{'type': 'web_search_20250305', 'name': 'web_search', 'max_uses': 5}],
    };
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      body['system'] = systemPrompt;
    }

    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (config.authHeader != null) config.authHeader!: '${config.authPrefix}$apiKey',
      ...config.extraHeaders,
    };

    final response = await _dio.post(
      config.url,
      data: body,
      options: Options(headers: headers),
    );

    return _streamAnthropic(response, onChunk);
  }

  Future<({String content, String reasoning})> _streamAnthropic(Response response, void Function(String) onChunk) async {
    final buffer = StringBuffer();
    final stream = (response.data as ResponseBody).stream;
    String lineBuffer = '';

    void processEvents() {
      lineBuffer = lineBuffer.replaceAll('\r\n', '\n');
      while (lineBuffer.contains('\n\n')) {
        final eventEnd = lineBuffer.indexOf('\n\n');
        final event = lineBuffer.substring(0, eventEnd);
        lineBuffer = lineBuffer.substring(eventEnd + 2);
        for (final line in event.split('\n')) {
          if (line.startsWith('data: ')) {
            try {
              final json = jsonDecode(line.substring(6));
              if (json['type'] == 'content_block_delta') {
                final text = json['delta']?['text'] as String?;
                if (text != null && text.isNotEmpty) {
                  buffer.write(text);
                  onChunk(text);
                }
              }
            } catch (_) {}
          }
        }
      }
    }

    await for (final chunk in stream) {
      lineBuffer += utf8.decode(chunk);
      processEvents();
      await Future.delayed(const Duration(milliseconds: 1));
    }
    if (lineBuffer.isNotEmpty) processEvents();
    return (content: buffer.toString(), reasoning: '');
  }

  // ── Gemini ──

  Future<({String content, String reasoning})> _sendGemini(
    _ProviderConfig config,
    String modelId,
    String apiKey,
    List<Message> history,
    String? systemPrompt,
    String? imageBase64,
    void Function(String) onChunk,
  ) async {
    final contents = <Map<String, dynamic>>[];
    for (int i = 0; i < history.length; i++) {
      final msg = history[i];
      final isLast = i == history.length - 1;
      final role = msg.role == MessageRole.user ? 'user' : 'model';
      final parts = <Map<String, dynamic>>[];

      if (isLast && role == 'user' && imageBase64 != null) {
        final rawBase64 = imageBase64.contains(',') ? imageBase64.split(',').last : imageBase64;
        final mimeType = imageBase64.contains('image/')
            ? RegExp(r'data:(image/\w+);').firstMatch(imageBase64)?.group(1) ?? 'image/jpeg'
            : 'image/jpeg';
        if (msg.content.isNotEmpty) parts.add({'text': msg.content});
        parts.add({'inlineData': {'mimeType': mimeType, 'data': rawBase64}});
      } else {
        parts.add({'text': msg.content});
      }
      contents.add({'role': role, 'parts': parts});
    }

    final body = <String, dynamic>{
      'contents': contents,
      'generationConfig': {
        'temperature': 0.7,
        'maxOutputTokens': 8192,
      },
      'tools': [{'googleSearch': {}}],
    };
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      body['systemInstruction'] = {'parts': [{'text': systemPrompt}]};
    }

    final url = '${config.host}/models/$modelId:streamGenerateContent?alt=sse&key=$apiKey';
    final headers = <String, String>{'Content-Type': 'application/json'};

    final response = await _dio.post(
      url,
      data: body,
      options: Options(headers: headers),
    );

    return _streamGemini(response, onChunk);
  }

  Future<({String content, String reasoning})> _streamGemini(Response response, void Function(String) onChunk) async {
    final buffer = StringBuffer();
    final stream = (response.data as ResponseBody).stream;
    String lineBuffer = '';

    void processEvents() {
      lineBuffer = lineBuffer.replaceAll('\r\n', '\n');
      while (lineBuffer.contains('\n\n')) {
        final eventEnd = lineBuffer.indexOf('\n\n');
        final event = lineBuffer.substring(0, eventEnd);
        lineBuffer = lineBuffer.substring(eventEnd + 2);
        for (final line in event.split('\n')) {
          if (line.startsWith('data: ')) {
            final data = line.substring(6);
            if (data == '[DONE]' || data.isEmpty) continue;
            try {
              final json = jsonDecode(data);
              final candidates = json['candidates'] as List<dynamic>?;
              if (candidates != null && candidates.isNotEmpty) {
                final parts = candidates[0]?['content']?['parts'] as List<dynamic>?;
                if (parts != null && parts.isNotEmpty) {
                  final text = parts[0]?['text'] as String?;
                  if (text != null && text.isNotEmpty) {
                    buffer.write(text);
                    onChunk(text);
                  }
                }
              }
            } catch (_) {}
          }
        }
      }
    }

    await for (final chunk in stream) {
      lineBuffer += utf8.decode(chunk);
      processEvents();
      await Future.delayed(const Duration(milliseconds: 1));
    }
    if (lineBuffer.isNotEmpty) processEvents();
    return (content: buffer.toString(), reasoning: '');
  }

  // ── Error mapping ──

  /// 测速：GET 探测端点连通性与延迟，失败返回 null。
  static Future<({int code, int ms})?> pingEndpoint(String url) async {
    final stopwatch = Stopwatch()..start();
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        followRedirects: false,
      ));
      final response = await dio.get<dynamic>(url);
      return (code: response.statusCode ?? 0, ms: stopwatch.elapsedMilliseconds);
    } catch (_) {
      return null;
    }
  }

  String mapError(dynamic error) {
    if (error is DioException) {
      final code = error.response?.statusCode;
      switch (code) {
        case 400:
          return '模型名称无效或请求参数错误，请检查模型选择';
        case 401:
          return 'API Key 无效，请在设置中配置有效的密钥';
        case 402:
          return '账户余额不足，请充值后重试';
        case 403:
          return '访问被拒绝，请检查 API Key 权限';
        case 429:
          return '请求太频繁，请稍后再试';
        case 500:
        case 502:
        case 503:
          return '服务暂时不可用，请稍后重试';
        default:
          if (error.type == DioExceptionType.connectionTimeout || error.type == DioExceptionType.connectionError) {
            return '网络连接失败，请检查网络设置';
          }
          if (error.type == DioExceptionType.receiveTimeout) {
            return '响应超时，请重试';
          }
          return error.message ?? '请求失败，请重试';
      }
    }
    return '未知错误，请重试';
  }
}
