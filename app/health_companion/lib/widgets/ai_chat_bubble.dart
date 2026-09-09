import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ai_chat/ai_chat_service.dart';
import '../screens/ai_chat_screen.dart';
import '../storage/ai_chat_settings_store.dart';

/// A WhatsApp-style persistent floating button, draggable within the
/// screen, that opens AiChatScreen. Mounted only inside DashboardScreen's
/// own build (per explicit user request — not a global overlay). Because
/// it lives *below* the Navigator now (unlike the original global-overlay
/// placement), it needs no explicit "hide while the chat screen is open"
/// flag: Flutter simply doesn't paint a route's content while another
/// route (AiChatScreen, Settings, anything) is pushed on top of it, so
/// it's automatically covered/uncovered along with the rest of
/// DashboardScreen — same as any other widget below the active route.
/// (An earlier version tracked this manually via a ValueNotifier the two
/// screens toggled — redundant with what Navigator already does for
/// free, and the actual cause of a real bug: opening the chat screen
/// once left the flag stuck `true` forever, hiding the button
/// permanently even back on the Dashboard.)
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

    if (!enabled || !ready) return const SizedBox.shrink();

    // Positioned only has any effect as a DIRECT child of a Stack.
    // Positioned.fill is that direct child (correctly recognized),
    // filling the whole body area and handing that exact size to
    // LayoutBuilder as tight constraints. The actual button is then
    // placed with a second, INNER Stack + Positioned, which is free to
    // use any local offset since it's the direct child of *that* Stack,
    // not the outer one.
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final areaSize = constraints.biggest;
          final bottomInset = MediaQuery.of(context).padding.bottom;
          _position ??= Offset(
            areaSize.width - _size - 16,
            areaSize.height - bottomInset - _size - 16,
          );
          final pos = _clamp(_position!, areaSize, bottomInset);

          return Stack(
            children: [
              Positioned(
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
              ),
            ],
          );
        },
      ),
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
