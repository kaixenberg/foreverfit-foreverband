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
    this.attachedText,
  });

  String text;
  final bool isUser;
  bool isError;
  final String? displayText;
  final String? attachmentLabel;
  final List<Uint8List> images;

  /// The raw extracted content behind a PDF attachment (kept separate
  /// from [text], which already has it merged in with the caption) —
  /// lets editing rebuild [text] from a new caption plus this same
  /// content, so "edit and rerun" can reuse the attachment instead of
  /// losing it. Null for messages with no PDF attachment.
  final String? attachedText;

  /// What the chat bubble should render.
  String get shownText => displayText ?? text;
}
