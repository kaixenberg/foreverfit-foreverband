import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ai_chat/ai_chat_service.dart';
import '../screens/ai_chat_screen.dart';
import '../storage/ai_chat_settings_store.dart';

/// A WhatsApp-style persistent floating button, draggable within the
/// screen, that opens AiChatScreen. Mounted only inside DashboardScreen's
/// own build (per explicit user request — not a global overlay), so it's
/// only ever visible on the main screen: Navigator.push covers it with
/// whatever screen is pushed on top, same as any other widget below the
/// active route.
///
/// Only in-app — this is not a system-wide overlay (no
/// SYSTEM_ALERT_WINDOW), so it's only visible while ForeverFit itself is
/// in the foreground.
class AiChatBubble extends StatefulWidget {
  const AiChatBubble({super.key});

  @override
  State<AiChatBubble> createState() => _AiChatBubbleState();
}

class _AiChatBubbleState extends State<AiChatBubble> {
  static const _size = 56.0;
  Offset? _position;

  @override
  Widget build(BuildContext context) {
    final enabled = context.select<AiChatSettingsStore, bool>((s) => s.enabled);
    final ready = context.select<AiChatService, bool>(
        (c) => c.status == AiChatModelStatus.ready);
    final chatOpen = context.watch<AiChatService>().chatScreenOpen;

    if (!enabled || !ready) return const SizedBox.shrink();

    return ValueListenableBuilder<bool>(
      valueListenable: chatOpen,
      builder: (context, isOpen, _) {
        if (isOpen) return const SizedBox.shrink();

        final screenSize = MediaQuery.of(context).size;
        final padding = MediaQuery.of(context).padding;
        _position ??= Offset(
          screenSize.width - _size - 16,
          screenSize.height - padding.bottom - _size - 40,
        );
        final pos = _clamp(_position!, screenSize, padding);

        return Positioned(
          left: pos.dx,
          top: pos.dy,
          child: GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                _position = _clamp(
                  _position! + details.delta,
                  screenSize,
                  padding,
                );
              });
            },
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AiChatScreen()),
            ),
            child: Material(
              elevation: 6,
              shape: const CircleBorder(),
              color: Theme.of(context).colorScheme.primary,
              child: SizedBox(
                width: _size,
                height: _size,
                child: Icon(
                  Icons.smart_toy_outlined,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Offset _clamp(Offset offset, Size screenSize, EdgeInsets padding) {
    final maxX = screenSize.width - _size;
    final maxY = screenSize.height - _size;
    return Offset(
      offset.dx.clamp(0, maxX < 0 ? 0 : maxX),
      offset.dy.clamp(padding.top, maxY < padding.top ? padding.top : maxY),
    );
  }
}
