import 'dart:typed_data';

/// One turn in the on-device AI assistant's chat transcript. Persisted by
/// AiChatHistoryStore so past conversations survive an app restart (see
/// AiChatService.send()).
///
/// [text] is what's actually sent to (and, on resume, replayed into) the
/// model — for a PDF attachment this includes the extracted document text.
/// [displayText], when set, is what the chat bubble shows instead (just the
/// user's caption) so the raw extracted text doesn't clutter the UI.
class AiChatMessage {
  AiChatMessage({
    required this.text,
    required this.isUser,
    this.isError = false,
    this.displayText,
    this.attachmentLabel,
    this.images = const [],
  });

  String text;
  final bool isUser;
  bool isError;
  final String? displayText;
  final String? attachmentLabel;
  final List<Uint8List> images;

  /// What the chat bubble should render.
  String get shownText => displayText ?? text;
}
