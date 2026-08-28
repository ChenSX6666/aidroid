import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ai_provider.dart';

/// 自定义 AI 厂商配置（模型配置 → 添加自定义模型）
class CustomAiProvider {
  final String id; // 'custom_<ts>'
  final String name; // 供应商名称
  final String note; // 备注
  final String website; // 官网链接（可选）
  final String baseUrl; // 请求地址（不带尾部斜杠）
  final bool isFullUrl; // 完整 URL 开关
  final String apiFormat; // 'openai' | 'anthropic' | 'gemini'
  final String authField; // 'authorization' | 'x_api_key' | 'auth_token'
  final Map<String, String> modelMapping; // 角色 → 实际模型 ID
  final Set<String> supportContext1M; // 声明支持 1M 上下文的角色
  final bool fallbackEnabled; // 默认兜底模型开关
  final String fallbackModel; // 兜底模型名称

  const CustomAiProvider({
    required this.id,
    required this.name,
    this.note = '',
    this.website = '',
    required this.baseUrl,
    this.isFullUrl = false,
    this.apiFormat = 'openai',
    this.authField = 'authorization',
    this.modelMapping = const {},
    this.supportContext1M = const {},
    this.fallbackEnabled = true,
    this.fallbackModel = 'deepseek-v4-flash',
  });

  static const prefsKey = 'custom_ai_providers';
  static const idPrefix = 'custom_';

  String get formatLabel => switch (apiFormat) {
        'anthropic' => 'Anthropic 原生',
        'gemini' => 'Gemini 原生',
        _ => 'OpenAI Chat Completions',
      };

  String get authLabel => switch (authField) {
        'x_api_key' => 'x-api-key',
        'auth_token' => 'ANTHROPIC_AUTH_TOKEN',
        _ => 'Authorization (Bearer)',
      };

  /// 解析后的请求 host（不拼 endpoint）
  String resolveHost() {
    // 如果用户填的地址已经包含 /v1 等路径，直接使用
    final trimmed = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    if (isFullUrl) return trimmed;
    // 如果已经以 /v1 结尾，不再重复拼接
    if (trimmed.endsWith('/v1') || trimmed.endsWith('/v1beta')) return trimmed;
    return switch (apiFormat) {
      'gemini' => '$trimmed/v1beta',
      _ => '$trimmed/v1',
    };
  }

  AiProvider toAiProvider() => AiProvider(
        id: id,
        name: name,
        description: note.isNotEmpty ? note : baseUrl,
        icon: Icons.dns,
        color: const Color(0xFF0D7CB5),
        baseUrl: resolveHost(),
        defaultModels: const [],
        apiKeyHint: '',
      );

  /// 模型角色列表（固定）
  static const modelRoles = ['sonnet', 'opus', 'fable', 'haiku', 'subagent'];

  static const modelRoleLabels = {
    'sonnet': 'Sonnet',
    'opus': 'Opus',
    'fable': 'Fable',
    'haiku': 'Haiku',
    'subagent': 'Subagent',
  };

  /// 根据角色解析实际模型 ID；无映射时返回 fallback 或原始 modelId
  String resolveModel(String modelId) {
    final mapped = modelMapping[modelId];
    if (mapped != null && mapped.isNotEmpty) return mapped;
    if (fallbackEnabled && fallbackModel.isNotEmpty) return fallbackModel;
    return modelId;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'note': note,
        'website': website,
        'baseUrl': baseUrl,
        'isFullUrl': isFullUrl,
        'apiFormat': apiFormat,
        'authField': authField,
        'modelMapping': modelMapping,
        'supportContext1M': supportContext1M.toList(),
        'fallbackEnabled': fallbackEnabled,
        'fallbackModel': fallbackModel,
      };

  factory CustomAiProvider.fromJson(Map<String, dynamic> json) => CustomAiProvider(
        id: json['id'] as String? ?? '$idPrefix${DateTime.now().millisecondsSinceEpoch}',
        name: json['name'] as String? ?? '',
        note: json['note'] as String? ?? '',
        website: json['website'] as String? ?? '',
        baseUrl: json['baseUrl'] as String? ?? '',
        isFullUrl: json['isFullUrl'] as bool? ?? false,
        apiFormat: json['apiFormat'] as String? ?? 'openai',
        authField: json['authField'] as String? ?? 'authorization',
        modelMapping: (json['modelMapping'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, v as String)) ?? {},
        supportContext1M: (json['supportContext1M'] as List<dynamic>?)?.cast<String>().toSet() ?? {},
        fallbackEnabled: json['fallbackEnabled'] as bool? ?? true,
        fallbackModel: json['fallbackModel'] as String? ?? 'deepseek-v4-flash',
      );

  CustomAiProvider copyWith({
    String? name,
    String? note,
    String? website,
    String? baseUrl,
    bool? isFullUrl,
    String? apiFormat,
    String? authField,
    Map<String, String>? modelMapping,
    Set<String>? supportContext1M,
    bool? fallbackEnabled,
    String? fallbackModel,
  }) =>
      CustomAiProvider(
        id: id,
        name: name ?? this.name,
        note: note ?? this.note,
        website: website ?? this.website,
        baseUrl: baseUrl ?? this.baseUrl,
        isFullUrl: isFullUrl ?? this.isFullUrl,
        apiFormat: apiFormat ?? this.apiFormat,
        authField: authField ?? this.authField,
        modelMapping: modelMapping ?? this.modelMapping,
        supportContext1M: supportContext1M ?? this.supportContext1M,
        fallbackEnabled: fallbackEnabled ?? this.fallbackEnabled,
        fallbackModel: fallbackModel ?? this.fallbackModel,
      );

  static Future<List<CustomAiProvider>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => CustomAiProvider.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveAll(List<CustomAiProvider> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      prefsKey,
      jsonEncode(list.map((e) => e.toJson()).toList()),
    );
  }
}
