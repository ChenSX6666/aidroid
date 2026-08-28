import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AiProvider {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final Color color;
  final String baseUrl;
  final List<String> defaultModels;
  final String apiKeyHint;
  final bool supportsVision;

  const AiProvider({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
    required this.baseUrl,
    required this.defaultModels,
    required this.apiKeyHint,
    this.supportsVision = true,
  });

  Future<List<String>> getAllModels() async {
    final prefs = await SharedPreferences.getInstance();
    final custom = prefs.getStringList('custom_models_$id') ?? [];
    return [...defaultModels, ...custom];
  }

  Future<void> addCustomModel(String modelId) async {
    final prefs = await SharedPreferences.getInstance();
    final custom = prefs.getStringList('custom_models_$id') ?? [];
    if (!custom.contains(modelId)) {
      custom.add(modelId);
      await prefs.setStringList('custom_models_$id', custom);
    }
  }

  Future<void> removeCustomModel(String modelId) async {
    final prefs = await SharedPreferences.getInstance();
    final custom = prefs.getStringList('custom_models_$id') ?? [];
    custom.remove(modelId);
    await prefs.setStringList('custom_models_$id', custom);
  }

  static const deepseek = AiProvider(
    id: 'deepseek',
    name: 'DeepSeek',
    description: '深度求索 — V4 系列',
    icon: Icons.explore,
    color: Color(0xFF0EA5E9),
    baseUrl: 'https://api.deepseek.com/v1',
    defaultModels: ['deepseek-v4-pro', 'deepseek-v4-flash'],
    apiKeyHint: 'sk-...',
  );

  static const chuyingProvider = AiProvider(
    id: 'chuying',
    name: '智谱 GLM',
    description: '智谱 — GLM 系列',
    icon: Icons.star,
    color: Color(0xFF8B5CF6),
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    defaultModels: ['glm-5.2', 'glm-4.7', 'glm-4.7-flash', 'glm-4-long'],
    apiKeyHint: '智谱 API Key',
  );

  static const anthropic = AiProvider(
    id: 'anthropic',
    name: 'Anthropic',
    description: 'Claude 模型 — 最强推理和编程',
    icon: Icons.psychology,
    color: Color(0xFFD97706),
    baseUrl: 'https://api.anthropic.com/v1',
    defaultModels: ['claude-sonnet-5', 'claude-opus-4-8', 'claude-haiku-4-5', 'claude-sonnet-4-6'],
    apiKeyHint: 'sk-ant-...',
  );

  static const openai = AiProvider(
    id: 'openai',
    name: 'OpenAI',
    description: 'GPT / o 系列模型',
    icon: Icons.auto_awesome,
    color: Color(0xFF10A37F),
    baseUrl: 'https://api.openai.com/v1',
    defaultModels: ['gpt-5.4', 'gpt-4.1', 'gpt-4.1-mini', 'o3', 'o4-mini'],
    apiKeyHint: 'sk-...',
  );

  static const google = AiProvider(
    id: 'google',
    name: 'Google Gemini',
    description: 'Gemini 模型',
    icon: Icons.diamond,
    color: Color(0xFF4285F4),
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
    defaultModels: ['gemini-3.5-flash', 'gemini-2.5-pro', 'gemini-2.5-flash', 'gemini-3.1-pro-preview'],
    apiKeyHint: 'AIza...',
  );

  static const openrouter = AiProvider(
    id: 'openrouter',
    name: 'OpenRouter',
    description: '数百模型的统一 API',
    icon: Icons.route,
    color: Color(0xFF6366F1),
    baseUrl: 'https://openrouter.ai/api/v1',
    defaultModels: [
      'anthropic/claude-sonnet-5',
      'openai/gpt-4.1',
      'google/gemini-3.5-flash',
      'deepseek/deepseek-v4-pro',
      'meta-llama/llama-4-maverick',
    ],
    apiKeyHint: 'sk-or-...',
  );

  static const nvidia = AiProvider(
    id: 'nvidia',
    name: 'NVIDIA NIM',
    description: 'GPU 加速推理端点',
    icon: Icons.memory,
    color: Color(0xFF76B900),
    baseUrl: 'https://integrate.api.nvidia.com/v1',
    defaultModels: [
      'meta/llama-4-maverick',
      'deepseek-ai/deepseek-v3',
      'mistralai/mistral-large',
    ],
    apiKeyHint: 'nvapi-...',
  );

  static const xai = AiProvider(
    id: 'xai',
    name: 'xAI Grok',
    description: 'Grok 系列',
    icon: Icons.bolt,
    color: Color(0xFFEF4444),
    baseUrl: 'https://api.x.ai/v1',
    defaultModels: ['grok-4.3', 'grok-4.20-non-reasoning', 'grok-build-0.1', 'grok-3-mini'],
    apiKeyHint: 'xai-...',
  );

  static const xiaomi = AiProvider(
    id: 'xiaomi',
    name: '小米 MiMo',
    description: '小米 MiMo — 多模态模型',
    icon: Icons.phone_android,
    color: Color(0xFFFF6A00),
    baseUrl: 'https://api.xiaomimimo.com/v1',
    defaultModels: ['mimo-v2.5', 'mimo-v2.5-pro', 'mimo-v2-flash'],
    apiKeyHint: 'mi-...',
  );

  static const all = [deepseek, chuyingProvider, anthropic, openai, google, openrouter, nvidia, xai, xiaomi];
}
