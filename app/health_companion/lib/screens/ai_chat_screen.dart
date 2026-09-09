import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../ai_chat/ai_chat_message.dart';
import '../ai_chat/ai_chat_service.dart';
import '../ai_chat/pdf_text_extractor.dart';

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

  Uint8List? _pendingImage;
  String? _pendingPdfName;
  String? _pendingPdfText;

  @override
  void initState() {
    super.initState();
    context.read<AiChatService>().chatScreenOpen.value = true;
  }

  @override
  void dispose() {
    context.read<AiChatService>().chatScreenOpen.value = false;
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
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

  void _showAttachmentOptions() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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

  void _send() {
    final typed = _controller.text.trim();
    final hasImage = _pendingImage != null;
    final hasPdf = _pendingPdfText != null;
    if (typed.isEmpty && !hasImage && !hasPdf) return;

    final chat = context.read<AiChatService>();
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
            onPressed: chat.messages.isEmpty ? null : () => chat.newChat(),
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
                    itemBuilder: (context, i) =>
                        _MessageBubble(message: chat.messages[i]),
                  ),
          ),
          if (_pendingImage != null || _pendingPdfName != null)
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
                    onPressed:
                        chat.isGenerating ? null : _showAttachmentOptions,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Message',
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                        : const Icon(Icons.send),
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
  const _MessageBubble({required this.message});

  final AiChatMessage message;

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

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
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
      ),
    );
  }
}
