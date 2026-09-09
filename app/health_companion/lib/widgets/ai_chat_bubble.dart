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

        // The Stack this widget lives in is the Scaffold's *body* area —
        // smaller than the full device screen (no AppBar, no status bar).
        // MediaQuery.of(context).size is the full device size, so using it
        // here computed a position below/outside the Stack's actual bounds
        // — Stack clips by default, so the button ended up barely visible
        // at the clipped bottom edge, and stayed there forever since
        // _position is cached once and re-clamped against that same wrong
        // size on every rebuild. LayoutBuilder's constraints are the
        // Stack's real, current size — ground truth, not a guess.
        return LayoutBuilder(
          builder: (context, constraints) {
            final areaSize = Size(constraints.maxWidth, constraints.maxHeight);
            final bottomInset = MediaQuery.of(context).padding.bottom;
            _position ??= Offset(
              areaSize.width - _size - 16,
              areaSize.height - bottomInset - _size - 16,
            );
            final pos = _clamp(_position!, areaSize, bottomInset);

            return Positioned(
              left: pos.dx,
              top: pos.dy,
              child: GestureDetector(
                onPanUpdate: (details) {
                  setState(() {
                    _position = _clamp(
                      _position! + details.delta,
                      areaSize,
                      bottomInset,
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
      },
    );
  }

  Offset _clamp(Offset offset, Size areaSize, double bottomInset) {
    final maxX = areaSize.width - _size;
    final maxY = areaSize.height - bottomInset - _size;
    return Offset(
      offset.dx.clamp(0, maxX < 0 ? 0 : maxX),
      offset.dy.clamp(0, maxY < 0 ? 0 : maxY),
    );
  }
}
