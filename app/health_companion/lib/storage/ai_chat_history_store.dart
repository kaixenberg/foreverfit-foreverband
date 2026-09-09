import 'dart:convert';
import 'dart:typed_data';

import 'package:hive_flutter/hive_flutter.dart';

import '../ai_chat/ai_chat_message.dart';

/// Lightweight summary for a chat-history list — avoids loading every
/// session's full message list (images included) just to render titles.
class AiChatSessionSummary {
  const AiChatSessionSummary({
    required this.id,
    required this.title,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final DateTime updatedAt;
}

/// Persists the on-device AI assistant's chat sessions locally (Hive) so
/// past conversations survive an app restart — same offline-first,
/// local-only rule as the rest of this app's storage. One document per
/// session (key = session id), unlike the single-document-per-box pattern
/// used by AppSettingsStore/AiChatSettingsStore, since this is naturally a
/// growing collection of independent records, same shape as HistoryStore.
///
/// Excluded from data export/import (BackupService), same reasoning as
/// AiChatSettingsStore: this is chat scratch, not tracked health data.
/// Images are stored inline as base64 — chat sessions are short-lived and
/// few, so this stays simple rather than managing a separate file store.
class AiChatHistoryStore {
  static const _boxName = 'ai_chat_history';

  Box<Map>? _box;

  Future<void> init() async {
    _box = await Hive.openBox<Map>(_boxName);
  }

  List<AiChatSessionSummary> sessions() {
    final box = _box;
    if (box == null) return [];
    final list = box.keys.map((key) {
      final raw = Map<dynamic, dynamic>.from(box.get(key)!);
      return AiChatSessionSummary(
        id: key as String,
        title: raw['title'] as String? ?? 'Chat',
        updatedAt: DateTime.tryParse(raw['updatedAt'] as String? ?? '') ??
            DateTime.now(),
      );
    }).toList();
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  List<AiChatMessage>? loadMessages(String id) {
    final raw = _box?.get(id);
    if (raw == null) return null;
    final rawMessages = (raw['messages'] as List? ?? const [])
        .map((e) => Map<dynamic, dynamic>.from(e as Map));
    return rawMessages.map(_messageFromMap).toList();
  }

  Future<void> saveSession({
    required String id,
    required String title,
    required List<AiChatMessage> messages,
  }) async {
    await _box?.put(id, {
      'title': title,
      'updatedAt': DateTime.now().toIso8601String(),
      'messages': messages.map(_messageToMap).toList(),
    });
  }

  Future<void> deleteSession(String id) async {
    await _box?.delete(id);
  }

  Map<String, dynamic> _messageToMap(AiChatMessage m) => {
        'text': m.text,
        'isUser': m.isUser,
        'isError': m.isError,
        'displayText': m.displayText,
        'attachmentLabel': m.attachmentLabel,
        'images': m.images.map(base64Encode).toList(),
      };

  AiChatMessage _messageFromMap(Map raw) => AiChatMessage(
        text: raw['text'] as String? ?? '',
        isUser: raw['isUser'] as bool? ?? false,
        isError: raw['isError'] as bool? ?? false,
        displayText: raw['displayText'] as String?,
        attachmentLabel: raw['attachmentLabel'] as String?,
        images: (raw['images'] as List? ?? const [])
            .map<Uint8List>((e) => base64Decode(e as String))
            .toList(),
      );
}
