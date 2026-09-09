import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../ai_chat/ai_chat_message.dart';
import '../ai_chat/ai_chat_service.dart';
import '../ai_chat/pdf_text_extractor.dart';
import '../services/tts_service.dart';

/// The chat UI opened by tapping the floating AI bubble
/// (widgets/ai_chat_bubble.dart). Streams tokens live from
/// AiChatService.send() — local state here is just the text field, scroll
/// controller, and whatever single image/PDF attachment is staged but not
/// sent yet.
class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _inputFocusNode = FocusNode();

  Uint8List? _pendingImage;
  String? _pendingPdfName;
  String? _pendingPdfText;

  /// Index of the user message currently being edited (see
  /// AiChatService.editAndResend), or null when composing a normal new
  /// message. Editing is text-only — starting one clears any pending
  /// attachment and, on send, discards the original message's own
  /// image/PDF attachment along with everything after it.
  int? _editingIndex;

  /// Index of the assistant message currently being read aloud (see
  /// _toggleSpeak), or null when nothing is playing.
  int? _speakingIndex;

  final _speech = SpeechToText();
  bool _isListening = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    if (_isListening) unawaited(_speech.stop());
    unawaited(context.read<TtsService>().stop());
    super.dispose();
  }

  void _startEditing(int index, String text) {
    setState(() {
      _editingIndex = index;
      _pendingImage = null;
      _pendingPdfName = null;
      _pendingPdfText = null;
      _controller.text = text;
    });
    _inputFocusNode.requestFocus();
  }

  void _cancelEditing() {
    setState(() {
      _editingIndex = null;
      _controller.clear();
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  void _clearPendingAttachment() {
    setState(() {
      _pendingImage = null;
      _pendingPdfName = null;
      _pendingPdfText = null;
    });
  }

  Future<void> _pickImage() async {
    final file = await ImagePicker().pickImage(
        source: ImageSource.gallery, maxWidth: 1280, imageQuality: 85);
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _pendingImage = bytes;
      _pendingPdfName = null;
      _pendingPdfText = null;
    });
  }

  Future<void> _pickPdf() async {
    final result = await FilePicker.pickFiles(
        type: FileType.custom, allowedExtensions: ['pdf']);
    if (result.isEmpty || !mounted) return;
    final picked = result.first;
    try {
      final bytes = await picked.readAsBytes();
      final text = extractPdfText(bytes);
      if (!mounted) return;
      setState(() {
        _pendingPdfName = picked.name;
        _pendingPdfText = text;
        _pendingImage = null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't read that PDF: $e")),
      );
    }
  }

  Future<void> _pickImageFromCamera() async {
    final file = await ImagePicker().pickImage(
        source: ImageSource.camera, maxWidth: 1280, imageQuality: 85);
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _pendingImage = bytes;
      _pendingPdfName = null;
      _pendingPdfText = null;
    });
  }

  void _showAttachmentOptions() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.of(context).pop();
                _pickImageFromCamera();
              },
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Photo from gallery'),
              onTap: () {
                Navigator.of(context).pop();
                _pickImage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('PDF document'),
              onTap: () {
                Navigator.of(context).pop();
                _pickPdf();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Dictation, not a live voice-conversation mode: tap to start listening,
  /// live partial results fill the text field, tap again (or the platform
  /// recognizer naturally finishing) to stop — the user still reviews and
  /// taps send themselves, same as anything typed.
  Future<void> _toggleListening() async {
    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
      return;
    }

    final available = await _speech.initialize(
      onStatus: (status) {
        if ((status == 'done' || status == 'notListening') && mounted) {
          setState(() => _isListening = false);
        }
      },
      onError: (error) {
        if (mounted) setState(() => _isListening = false);
      },
    );
    if (!available) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text("Speech recognition isn't available — check the microphone "
                  'permission in Settings.'),
        ),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _isListening = true);
    await _speech.listen(
      onResult: (result) {
        if (!mounted) return;
        setState(() {
          _controller.text = result.recognizedWords;
          _controller.selection =
              TextSelection.collapsed(offset: _controller.text.length);
        });
      },
    );
  }

  /// Toggles read-aloud for one assistant reply. Switching to a different
  /// message (or this screen closing — see dispose()) stops whatever was
  /// playing first, so only ever one message speaks at a time.
  Future<void> _toggleSpeak(int index, String text) async {
    final tts = context.read<TtsService>();
    if (_speakingIndex == index) {
      await tts.stop();
      if (mounted) setState(() => _speakingIndex = null);
      return;
    }
    if (_speakingIndex != null) await tts.stop();
    if (!mounted) return;
    setState(() => _speakingIndex = index);
    await tts.speak(text);
    if (mounted && _speakingIndex == index) {
      setState(() => _speakingIndex = null);
    }
  }

  Future<void> _copyMessage(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _send() {
    final typed = _controller.text.trim();
    final chat = context.read<AiChatService>();

    final editingIndex = _editingIndex;
    if (editingIndex != null) {
      if (typed.isEmpty) return;
      _controller.clear();
      setState(() => _editingIndex = null);
      chat.editAndResend(editingIndex, typed);
      _scrollToBottom();
      return;
    }

    final hasImage = _pendingImage != null;
    final hasPdf = _pendingPdfText != null;
    if (typed.isEmpty && !hasImage && !hasPdf) return;

    if (hasPdf) {
      final caption = typed.isEmpty ? 'Summarize this document.' : typed;
      chat.send(
        '$caption\n\n[Attached PDF: $_pendingPdfName]\n$_pendingPdfText',
        displayText: caption,
        attachmentLabel: _pendingPdfName,
      );
    } else if (hasImage) {
      final caption = typed.isEmpty ? "What's in this image?" : typed;
      chat.send(caption, images: [_pendingImage!]);
    } else {
      chat.send(typed);
    }

    _controller.clear();
    _clearPendingAttachment();
    _scrollToBottom();
  }

  void _openHistory() {
    final chat = context.read<AiChatService>();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final sessions = chat.sessions;
        return SafeArea(
          child: DraggableScrollableSheet(
            initialChildSize: 0.6,
            minChildSize: 0.3,
            maxChildSize: 0.9,
            expand: false,
            builder: (context, scrollController) => sessions.isEmpty
                ? const Center(child: Text('No past chats yet.'))
                : ListView.builder(
                    controller: scrollController,
                    itemCount: sessions.length,
                    itemBuilder: (context, i) {
                      final s = sessions[i];
                      return ListTile(
                        leading: const Icon(Icons.chat_bubble_outline),
                        title: Text(s.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                            DateFormat('MMM d, h:mm a').format(s.updatedAt)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Delete chat',
                          onPressed: () async {
                            await chat.deleteSession(s.id);
                            if (context.mounted) Navigator.of(context).pop();
                          },
                        ),
                        onTap: () {
                          _cancelEditing();
                          chat.loadSession(s.id);
                          Navigator.of(sheetContext).pop();
                        },
                      );
                    },
                  ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<AiChatService>();
    _scrollToBottom();

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Assistant'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Past chats',
            onPressed: _openHistory,
          ),
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: 'New chat',
            onPressed: chat.messages.isEmpty
                ? null
                : () {
                    _cancelEditing();
                    chat.newChat();
                  },
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.offline_bolt_outlined,
                    size: 16, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Fully offline — nothing you type here leaves this '
                    'phone.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: chat.messages.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Ask me anything — try turning on airplane mode '
                        'first. You can also attach a photo or PDF.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: chat.messages.length,
                    itemBuilder: (context, i) {
                      final message = chat.messages[i];
                      // Editing is text-only — a message with an image or
                      // PDF attachment can't be re-edited without also
                      // deciding what happens to that attachment, so the
                      // affordance is limited to plain text messages.
                      final canEdit = message.isUser &&
                          !chat.isGenerating &&
                          message.images.isEmpty &&
                          message.attachmentLabel == null;
                      final canSpeak = !message.isUser &&
                          !message.isError &&
                          message.shownText.isNotEmpty;
                      return _MessageBubble(
                        message: message,
                        onEdit: canEdit
                            ? () => _startEditing(i, message.shownText)
                            : null,
                        onSpeak: canSpeak
                            ? () => _toggleSpeak(i, message.shownText)
                            : null,
                        onCopy: message.shownText.isNotEmpty
                            ? () => _copyMessage(message.shownText)
                            : null,
                        isSpeaking: _speakingIndex == i,
                      );
                    },
                  ),
          ),
          if (_editingIndex != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Chip(
                  avatar: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Editing message'),
                  onDeleted: _cancelEditing,
                ),
              ),
            ),
          if (_editingIndex == null &&
              (_pendingImage != null || _pendingPdfName != null))
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Chip(
                  avatar: _pendingImage != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.memory(_pendingImage!,
                              width: 24, height: 24, fit: BoxFit.cover),
                        )
                      : const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: Text(_pendingImage != null
                      ? 'Photo attached'
                      : _pendingPdfName!),
                  onDeleted: _clearPendingAttachment,
                ),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.attach_file),
                    tooltip: 'Attach photo or PDF',
                    onPressed: chat.isGenerating || _editingIndex != null
                        ? null
                        : _showAttachmentOptions,
                  ),
                  IconButton(
                    icon: Icon(_isListening ? Icons.mic : Icons.mic_none),
                    color: _isListening
                        ? Theme.of(context).colorScheme.error
                        : null,
                    tooltip: _isListening ? 'Stop listening' : 'Voice input',
                    onPressed: chat.isGenerating ? null : _toggleListening,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _inputFocusNode,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: _isListening
                            ? 'Listening…'
                            : _editingIndex != null
                                ? 'Edit message'
                                : 'Message',
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    icon: chat.isGenerating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            _editingIndex != null ? Icons.check : Icons.send),
                    onPressed: chat.isGenerating ? null : _send,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    this.onEdit,
    this.onSpeak,
    this.onCopy,
    this.isSpeaking = false,
  });

  final AiChatMessage message;

  /// Null when this message can't be edited right now (not the user's
  /// own, has an image/PDF attachment, or a reply is already streaming).
  final VoidCallback? onEdit;

  /// Null when this message can't be read aloud (the user's own message,
  /// an error, or empty). Toggles play/stop — see [isSpeaking].
  final VoidCallback? onSpeak;

  /// Null when there's no text worth copying.
  final VoidCallback? onCopy;

  /// Whether this specific message is the one currently being read aloud.
  final bool isSpeaking;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = message.isUser;
    final bg = message.isError
        ? scheme.errorContainer
        : isUser
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest;
    final fg = message.isError
        ? scheme.onErrorContainer
        : isUser
            ? scheme.onPrimaryContainer
            : scheme.onSurface;

    final bubble = Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.7,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (message.images.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(message.images.first, fit: BoxFit.cover),
              ),
            ),
          if (message.attachmentLabel != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.picture_as_pdf_outlined, size: 14, color: fg),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      message.attachmentLabel!,
                      style: TextStyle(color: fg, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          Text(
            message.shownText.isEmpty ? '…' : message.shownText,
            style: TextStyle(color: fg),
          ),
        ],
      ),
    );

    final bubbleRow = Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: onEdit == null
          ? bubble
          : Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  tooltip: 'Edit message',
                  visualDensity: VisualDensity.compact,
                  onPressed: onEdit,
                ),
                Flexible(child: bubble),
              ],
            ),
    );

    if (onSpeak == null && onCopy == null) return bubbleRow;

    // Read-aloud/copy actions render below the bubble, not inside it —
    // same placement as Claude's own chat UI.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        bubbleRow,
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onSpeak != null)
                IconButton(
                  icon: Icon(
                      isSpeaking
                          ? Icons.stop_circle_outlined
                          : Icons.volume_up_outlined,
                      size: 18),
                  tooltip: isSpeaking ? 'Stop reading aloud' : 'Read aloud',
                  visualDensity: VisualDensity.compact,
                  onPressed: onSpeak,
                ),
              if (onCopy != null)
                IconButton(
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  tooltip: 'Copy',
                  visualDensity: VisualDensity.compact,
                  onPressed: onCopy,
                ),
            ],
          ),
        ),
      ],
    );
  }
}
