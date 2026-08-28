import 'dart:convert';
import 'package:uuid/uuid.dart';

enum MessageRole { user, assistant, system }

class Message {
  final String id;
  final MessageRole role;
  final String content;
  final String? reasoningContent;
  final String? imageBase64;
  final DateTime timestamp;

  Message({
    String? id,
    required this.role,
    required this.content,
    this.reasoningContent,
    this.imageBase64,
    DateTime? timestamp,
  })  : id = id ?? const Uuid().v4(),
        timestamp = timestamp ?? DateTime.now();

  String get roleString {
    switch (role) {
      case MessageRole.user:
        return 'user';
      case MessageRole.assistant:
        return 'assistant';
      case MessageRole.system:
        return 'system';
    }
  }

  List<Map<String, dynamic>> get contentParts {
    final parts = <Map<String, dynamic>>[];
    if (content.isNotEmpty) {
      parts.add({'type': 'text', 'text': content});
    }
    if (imageBase64 != null) {
      parts.add({
        'type': 'image_url',
        'image_url': {'url': imageBase64},
      });
    }
    return parts;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': roleString,
        'content': content,
        'reasoningContent': reasoningContent,
        'imageBase64': imageBase64,
        'timestamp': timestamp.toIso8601String(),
      };

  factory Message.fromJson(Map<String, dynamic> json) {
    final roleStr = json['role'] as String;
    final role = switch (roleStr) {
      'user' => MessageRole.user,
      'assistant' => MessageRole.assistant,
      _ => MessageRole.system,
    };
    return Message(
      id: json['id'] as String?,
      role: role,
      content: json['content'] as String? ?? '',
      reasoningContent: json['reasoningContent'] as String?,
      imageBase64: json['imageBase64'] as String?,
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Message copyWith({String? content, String? imageBase64, String? reasoningContent}) => Message(
        id: id,
        role: role,
        content: content ?? this.content,
        reasoningContent: reasoningContent ?? this.reasoningContent,
        imageBase64: imageBase64 ?? this.imageBase64,
        timestamp: timestamp,
      );
}

class Conversation {
  final String id;
  String title;
  final List<Message> messages;
  final String providerId;
  final String modelId;
  final DateTime createdAt;
  DateTime updatedAt;

  Conversation({
    String? id,
    String? title,
    List<Message>? messages,
    this.providerId = 'deepseek',
    this.modelId = 'deepseek-chat',
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        title = title ?? '新对话',
        messages = messages ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  int get messageCount => messages.length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'providerId': providerId,
        'modelId': modelId,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'messages': messages.map((m) => m.toJson()).toList(),
      };

  factory Conversation.fromJson(Map<String, dynamic> json) {
    final messages = (json['messages'] as List<dynamic>?)
            ?.map((m) => Message.fromJson(m as Map<String, dynamic>))
            .toList() ??
        [];
    return Conversation(
      id: json['id'] as String?,
      title: json['title'] as String? ?? '新对话',
      providerId: json['providerId'] as String? ?? 'deepseek',
      modelId: json['modelId'] as String? ?? 'deepseek-chat',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
      messages: messages,
    );
  }

  Conversation copyWith({
    String? title,
    List<Message>? messages,
    String? providerId,
    String? modelId,
  }) =>
      Conversation(
        id: id,
        title: title ?? this.title,
        messages: messages ?? this.messages,
        providerId: providerId ?? this.providerId,
        modelId: modelId ?? this.modelId,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );
}
