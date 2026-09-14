import Foundation
import Combine

@MainActor
public final class AiChatService: ObservableObject {
    @Published public var messages: [AiChatMessage] = []
    @Published public var isGenerating: Bool = false
    @Published public var currentSessionId: String = UUID().uuidString

    public let modelManager = GemmaModelManager.shared
    private let engine = LocalLLMEngine()

    public init() {
        seedInitialGreeting()
    }

    public func seedInitialGreeting() {
        if messages.isEmpty {
            messages.append(AiChatMessage(
                role: .assistant,
                content: "Hello! I am your **ForeverFit On-Device Health Companion** powered by Gemma 4 E2B.\n\nI monitor your live heart rate, SpO2, and ambient conditions from the **ForeverBand**, and cross-reference your health log. How can I help you today?"
            ))
        }
    }

    public func sendMessage(text: String, healthContext: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // User message
        let userMsg = AiChatMessage(role: .user, content: text, attachedContext: healthContext)
        messages.append(userMsg)

        // Assistant placeholder
        let assistantMsgId = UUID()
        messages.append(AiChatMessage(id: assistantMsgId, role: .assistant, content: "", isStreaming: true))
        isGenerating = true

        Task {
            // Check if model is ready or in mock/download mode
            if !modelManager.status.isReady {
                // Inform user about model download requirement matching Android app
                let warning = "⚠️ **On-device Gemma 4 E2B model is not installed yet.**\n\nTo run fully offline on your iPhone, please download the model (~2.6 GB) from **Settings > AI Assistant**."
                if let idx = self.messages.firstIndex(where: { $0.id == assistantMsgId }) {
                    self.messages[idx].content = warning
                    self.messages[idx].isStreaming = false
                }
                self.isGenerating = false
                return
            }

            // Stream reply using on-device Gemma engine
            await engine.streamReply(prompt: text, context: healthContext) { [weak self] token in
                guard let self = self else { return }
                if let idx = self.messages.firstIndex(where: { $0.id == assistantMsgId }) {
                    self.messages[idx].content += token
                }
            }

            if let idx = self.messages.firstIndex(where: { $0.id == assistantMsgId }) {
                self.messages[idx].isStreaming = false
            }
            self.isGenerating = false
        }
    }

    public func clearConversation() {
        messages.removeAll()
        currentSessionId = UUID().uuidString
        seedInitialGreeting()
    }
}
