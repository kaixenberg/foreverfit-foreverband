import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../ai_chat/ai_chat_service.dart';
import '../../storage/ai_chat_settings_store.dart';

/// Opt-in on-device AI assistant: a Settings toggle that walks through an
/// explicit download-size warning, then downloads Gemma 4 E2B (~2.6 GB,
/// Wi-Fi-only by default) via AiChatService. Once installed, a floating
/// chat bubble appears app-wide (see widgets/ai_chat_bubble.dart) — this
/// screen only owns opt-in/download/removal, not the chat itself (that's
/// AiChatScreen).
class AiAssistantScreen extends StatelessWidget {
  const AiAssistantScreen({super.key});

  Future<void> _confirmAndEnable(BuildContext context) async {
    final settings = context.read<AiChatSettingsStore>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Download on-device AI assistant?'),
        content: const Text(
          'This downloads Gemma 4 E2B, a ~2.6 GB AI model, to your phone '
          'so it can chat with you fully offline — no data ever leaves '
          'this device. The download can be large on mobile data; it '
          'defaults to Wi-Fi only (change that below first if needed). '
          'You can remove the model at any time to free up the space.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Download'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    await settings.setEnabled(true);
    if (!context.mounted) return;
    final chat = context.read<AiChatService>();
    try {
      await chat.downloadModel();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _confirmAndRemove(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove the AI assistant?'),
        content: const Text(
          'Deletes the downloaded model (~2.6 GB freed) and hides the '
          'floating chat button. You can download it again any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await context.read<AiChatService>().disableAndDeleteModel();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AiChatSettingsStore>();
    final chat = context.watch<AiChatService>();

    return Scaffold(
      appBar: AppBar(title: const Text('AI Assistant')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                "Marketing stunt, honestly — but a real one: this chatbot "
                'runs entirely on your phone. Turn on airplane mode and '
                "it still answers, because it never talks to a server.",
              ),
            ),
          ),
          const SizedBox(height: 16),
          switch (chat.status) {
            AiChatModelStatus.notInstalled => Card(
                child: ListTile(
                  leading: const Icon(Icons.smart_toy_outlined),
                  title: const Text('Enable AI assistant'),
                  subtitle: const Text('Downloads Gemma 4 E2B (~2.6 GB)'),
                  trailing: FilledButton(
                    onPressed: () => _confirmAndEnable(context),
                    child: const Text('Download'),
                  ),
                ),
              ),
            AiChatModelStatus.downloading => Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Downloading model…'),
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: chat.downloadProgress / 100,
                      ),
                      const SizedBox(height: 8),
                      Text('${chat.downloadProgress}%'),
                    ],
                  ),
                ),
              ),
            AiChatModelStatus.ready => Card(
                child: Column(
                  children: [
                    const ListTile(
                      leading: Icon(Icons.check_circle_outline),
                      title: Text('AI assistant is ready'),
                      subtitle: Text(
                        'Look for the floating chat button on the '
                        'Dashboard.',
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.delete_outline),
                      title: const Text('Remove model'),
                      subtitle: const Text('Frees ~2.6 GB of storage'),
                      onTap: () => _confirmAndRemove(context),
                    ),
                  ],
                ),
              ),
            AiChatModelStatus.error => Card(
                child: ListTile(
                  leading: Icon(Icons.error_outline,
                      color: Theme.of(context).colorScheme.error),
                  title: const Text('Download failed'),
                  subtitle: Text(chat.lastError ?? 'Unknown error'),
                  trailing: FilledButton(
                    onPressed: () => _confirmAndEnable(context),
                    child: const Text('Retry'),
                  ),
                ),
              ),
          },
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('Wi-Fi only'),
            subtitle: const Text('Only download the model over Wi-Fi'),
            value: settings.wifiOnlyDownload,
            onChanged: (v) => settings.setWifiOnlyDownload(v),
          ),
        ],
      ),
    );
  }
}
