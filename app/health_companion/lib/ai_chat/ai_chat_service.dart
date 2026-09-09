import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';

import '../storage/ai_chat_history_store.dart';
import '../storage/ai_chat_settings_store.dart';
import 'ai_chat_message.dart';

enum AiChatModelStatus {
  /// Not downloaded yet (or the user hasn't opted in).
  notInstalled,
  downloading,
  ready,
  error,
}

/// Google's Gemma 4 E2B (via the LiteRT-LM engine) — the smaller,
/// lighter-weight of the two Gemma 4 sizes flutter_gemma offers.
/// Deliberately not E4B: this is a "wow" demo feature (offline on-device
/// chat), not a diagnostic tool, so the ~1GB-smaller download and lower
/// peak RAM matter more here than the modest quality gap. See
/// ARCHITECTURE.md for the full reasoning.
///
/// Apache-2.0, publicly downloadable — unlike Gemma3n/EmbeddingGemma, no
/// Hugging Face token is required.
const _modelUrl =
    'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm';
const _modelId = 'gemma-4-E2B-it.litertlm';

const _systemInstruction =
    'You are a friendly, general-purpose on-device assistant embedded in '
    'the ForeverFit health app. You run fully offline on the phone, with '
    'no internet connection. You are NOT a doctor: for any medical '
    "question, give general, non-diagnostic information and suggest the "
    "user use the app's real vitals/emergency features or consult a "
    'real clinician for anything specific to them. Keep answers short.';

/// Owns the on-device Gemma 4 E2B model + chat session lifecycle:
/// opt-in download (with progress), lazy model/session creation, sending
/// a message (text, and optionally images or PDF-extracted text) and
/// streaming the reply, persisting/resuming past sessions via
/// AiChatHistoryStore, and tearing everything down if the user turns the
/// feature off.
///
/// A "session" here is one saved conversation. `messages` always holds the
/// currently active one (in-memory); it's persisted to AiChatHistoryStore
/// after every completed turn, keyed by `_currentSessionId` (assigned on
/// the first message of a fresh chat). Switching to a different saved
/// session doesn't eagerly replay it into the live model context (that's
/// real prefill work) — replay happens lazily, right before the next
/// message is sent in that conversation, so just browsing history stays
/// cheap.
class AiChatService extends ChangeNotifier {
  AiChatService(this._settings, this._history);

  final AiChatSettingsStore _settings;
  final AiChatHistoryStore _history;

  static bool _engineInitialized = false;

  AiChatModelStatus status = AiChatModelStatus.notInstalled;
  int downloadProgress = 0;
  String? lastError;
  bool isGenerating = false;
  final List<AiChatMessage> messages = [];

  InferenceModel? _model;
  InferenceChat? _chat;

  String? _currentSessionId;
  List<AiChatMessage>? _pendingReplay;

  List<AiChatSessionSummary> get sessions => _history.sessions();

  /// Registers the LiteRT-LM engine and checks whether a model from a
  /// previous session is already on disk. Cheap and side-effect-free
  /// beyond that — does NOT download anything and does NOT require the
  /// user to have opted in, so it's safe to call unconditionally at app
  /// startup (mirrors every other *Store/*Service `init()` in this app).
  Future<void> init() async {
    if (!_engineInitialized) {
      await FlutterGemma.initialize(inferenceEngines: const [LiteRtLmEngine()]);
      _engineInitialized = true;
    }
    if (!_settings.enabled) return;
    final installed = await FlutterGemma.isModelInstalled(_modelId);
    status =
        installed ? AiChatModelStatus.ready : AiChatModelStatus.notInstalled;
    notifyListeners();
  }

  /// Downloads and installs the model. Checks the Wi-Fi-only preference
  /// itself (flutter_gemma has no such option) — throws a plain
  /// [StateError] with a user-facing message if it's on and the device
  /// isn't currently on Wi-Fi, before touching the network.
  Future<void> downloadModel() async {
    if (status == AiChatModelStatus.downloading) return;
    if (_settings.wifiOnlyDownload) {
      final results = await Connectivity().checkConnectivity();
      if (!results.contains(ConnectivityResult.wifi)) {
        throw StateError(
          'Wi-Fi-only download is on and this device isn\'t on Wi-Fi. '
          'Connect to Wi-Fi or turn off "Wi-Fi only" to continue.',
        );
      }
    }

    status = AiChatModelStatus.downloading;
    downloadProgress = 0;
    lastError = null;
    notifyListeners();

    try {
      await FlutterGemma.installModel(
        modelType: ModelType.gemma4,
        fileType: ModelFileType.litertlm,
      ).fromNetwork(_modelUrl, foreground: true).withProgress((progress) {
        downloadProgress = progress;
        notifyListeners();
      }).install();

      status = AiChatModelStatus.ready;
      notifyListeners();
    } catch (e) {
      status = AiChatModelStatus.error;
      lastError = '$e';
      notifyListeners();
      rethrow;
    }
  }

  Future<InferenceChat> _ensureChat() async {
    final existing = _chat;
    if (existing != null) return existing;
    // CPU, not GPU: the GPU/OpenCL accelerator path (libLiteRtClGlAccelerator)
    // segfaults on engine creation on at least one real test device (Adreno,
    // Snapdragon 8s Gen 4) — a native SIGSEGV, not a catchable Dart
    // exception, so there's no graceful fallback possible once it's hit.
    // CPU is the well-supported path with no vendor GPU-driver dependency;
    // E2B (2B params) is small enough that CPU-only inference is still
    // reasonably fast for this "wow" demo feature. Revisit if flutter_gemma
    // ships a safer GPU path later.
    // supportImage has to be requested here, at the MODEL level, not just
    // on createChat below — this is what actually loads the native vision
    // executor. Passing it only to createChat looked plausible (its own
    // supportImage flag exists too, and analyze/tests couldn't catch this
    // since it's a runtime engine-state check) but fails on the first real
    // image with "Vision executor should not be null, please
    // TryLoadingVisionExecutor() first." — the createChat flag only
    // controls whether the Dart-side chat object routes image messages
    // through, it doesn't load anything itself.
    final model = _model ??= await FlutterGemma.getActiveModel(
      maxTokens: 4096,
      preferredBackend: PreferredBackend.cpu,
      supportImage: true,
    );
    final chat = await model.createChat(
      modelType: ModelType.gemma4,
      systemInstruction: _systemInstruction,
      supportImage: true,
    );
    _chat = chat;

    final replay = _pendingReplay;
    if (replay != null) {
      _pendingReplay = null;
      for (final m in replay) {
        if (m.isError) continue;
        await chat.addQueryChunk(
          m.images.isEmpty
              ? Message.text(text: m.text, isUser: m.isUser)
              : Message.withImages(
                  text: m.text, imageBytes: m.images, isUser: m.isUser),
        );
      }
    }
    return chat;
  }

  /// Sends [text] and streams the reply token-by-token into `messages`,
  /// notifying listeners on every token so the chat screen can render it
  /// live rather than waiting for the full response.
  ///
  /// [displayText], when given, is shown in the chat bubble instead of
  /// [text] — used for a PDF attachment, where [text] carries the
  /// extracted document text (sent to the model) but the bubble should
  /// only show the user's short caption/question. [images] are shown as
  /// thumbnails and sent to the model alongside [text]. [attachmentLabel]
  /// renders as a small chip on the message (e.g. a filename).
  Future<void> send(
    String text, {
    String? displayText,
    String? attachmentLabel,
    List<Uint8List> images = const [],
  }) async {
    if ((text.trim().isEmpty && images.isEmpty) || isGenerating) return;
    _currentSessionId ??= DateTime.now().microsecondsSinceEpoch.toString();

    messages.add(AiChatMessage(
      text: text,
      isUser: true,
      displayText: displayText,
      attachmentLabel: attachmentLabel,
      images: images,
    ));
    final reply = AiChatMessage(text: '', isUser: false);
    messages.add(reply);
    isGenerating = true;
    notifyListeners();

    try {
      final chat = await _ensureChat();
      final message = images.isEmpty
          ? Message.text(text: text, isUser: true)
          : Message.withImages(text: text, imageBytes: images, isUser: true);
      await chat.addQueryChunk(message);
      await for (final response in chat.generateChatResponseAsync()) {
        if (response is TextResponse) {
          reply.text += response.token;
          notifyListeners();
        }
      }
    } catch (e) {
      reply
        ..text = "Sorry, I couldn't respond: $e"
        ..isError = true;
      notifyListeners();
    } finally {
      isGenerating = false;
      notifyListeners();
      unawaited(_persist());
    }
  }

  Future<void> _persist() async {
    final id = _currentSessionId;
    if (id == null || messages.isEmpty) return;
    final firstUser = messages.firstWhere(
      (m) => m.isUser,
      orElse: () => messages.first,
    );
    final title = firstUser.shownText.trim().isNotEmpty
        ? (firstUser.shownText.trim().length > 40
            ? '${firstUser.shownText.trim().substring(0, 40)}…'
            : firstUser.shownText.trim())
        : (firstUser.attachmentLabel ?? 'New chat');
    await _history.saveSession(id: id, title: title, messages: messages);
  }

  /// Starts a fresh conversation — the current one stays saved (already
  /// persisted after its last turn) and reappears in [sessions].
  Future<void> newChat() async {
    await _chat?.close();
    _chat = null;
    _pendingReplay = null;
    _currentSessionId = null;
    messages.clear();
    notifyListeners();
  }

  /// Loads a previously saved conversation back into `messages`. Does not
  /// touch the live model session — that's recreated (and this history
  /// replayed into it) lazily on the next [send].
  Future<void> loadSession(String id) async {
    final loaded = _history.loadMessages(id);
    if (loaded == null) return;
    await _chat?.close();
    _chat = null;
    _currentSessionId = id;
    _pendingReplay = loaded;
    messages
      ..clear()
      ..addAll(loaded);
    notifyListeners();
  }

  Future<void> deleteSession(String id) async {
    await _history.deleteSession(id);
    if (_currentSessionId == id) {
      await newChat();
    } else {
      notifyListeners();
    }
  }

  /// Clears the in-memory transcript without touching the model/download —
  /// equivalent to [newChat], kept as a distinct name for the UI's "clear"
  /// action.
  void clearTranscript() {
    unawaited(newChat());
  }

  /// Turns the feature off and frees the multi-GB model from disk. Used
  /// by the Settings toggle when the user opts back out.
  Future<void> disableAndDeleteModel() async {
    await _chat?.close();
    _chat = null;
    await _model?.close();
    _model = null;
    messages.clear();
    _currentSessionId = null;
    _pendingReplay = null;
    if (await FlutterGemma.isModelInstalled(_modelId)) {
      await FlutterGemma.uninstallModel(_modelId);
    }
    status = AiChatModelStatus.notInstalled;
    downloadProgress = 0;
    await _settings.setEnabled(false);
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_chat?.close());
    unawaited(_model?.close());
    super.dispose();
  }
}
