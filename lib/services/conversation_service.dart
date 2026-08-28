import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/conversation.dart';

class ConversationService {
  static final ConversationService _instance = ConversationService._();
  factory ConversationService() => _instance;
  ConversationService._();

  SharedPreferences? _prefs;
  List<Conversation> _conversations = [];

  static const _key = 'conversations_v2';

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _load();
  }

  List<Conversation> getAll() {
    final sorted = List<Conversation>.from(_conversations);
    sorted.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return sorted;
  }

  Conversation? getById(String id) {
    try {
      return _conversations.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<Conversation> createNew({String? providerId, String? modelId}) async {
    final conv = Conversation(
      providerId: providerId ?? 'deepseek',
      modelId: modelId ?? 'deepseek-chat',
    );
    _conversations.add(conv);
    await _persist();
    return conv;
  }

  Future<Conversation> createFork({
    required List<Message> messages,
    String? providerId,
    String? modelId,
  }) async {
    final conv = Conversation(
      providerId: providerId ?? 'deepseek',
      modelId: modelId ?? 'deepseek-chat',
      messages: messages.map((m) => m.copyWith()).toList(),
    );
    _conversations.add(conv);
    await _persist();
    return conv;
  }

  Future<void> save(Conversation conv) async {
    final idx = _conversations.indexWhere((c) => c.id == conv.id);
    if (idx >= 0) {
      _conversations[idx] = conv;
    } else {
      _conversations.add(conv);
    }
    await _persist();
  }

  Future<void> delete(String id) async {
    _conversations.removeWhere((c) => c.id == id);
    await _persist();
  }

  Future<void> addMessage(String convId, Message msg) async {
    final conv = getById(convId);
    if (conv == null) return;
    conv.messages.add(msg);
    conv.updatedAt = DateTime.now();
    await _persist();
  }

  void _load() {
    try {
      final raw = _prefs?.getString(_key);
      if (raw == null || raw.isEmpty) {
        _conversations = [];
        return;
      }
      final list = jsonDecode(raw) as List<dynamic>;
      _conversations = list
          .map((e) => Conversation.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      _conversations = [];
    }
  }

  Future<void> _persist() async {
    try {
      final list = _conversations.map((c) => c.toJson()).toList();
      await _prefs?.setString(_key, jsonEncode(list));
    } catch (_) {}
  }
}
