import Foundation

public enum AiChatRole: String, Codable {
    case user
    case assistant
    case system
}

public struct AiChatMessage: Identifiable, Codable, Equatable {
    public var id: UUID
    public let role: AiChatRole
    public var content: String
    public let timestamp: Date
    public var isStreaming: Bool
    public var attachedContext: String?

    public init(
        id: UUID = UUID(),
        role: AiChatRole,
        content: String,
        timestamp: Date = Date(),
        isStreaming: Bool = false,
        attachedContext: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isStreaming = isStreaming
        self.attachedContext = attachedContext
    }
}

public struct AiChatSessionSummary: Identifiable, Codable {
    public let id: String
    public let title: String
    public let lastMessageAt: Date
    public let messageCount: Int

    public init(id: String, title: String, lastMessageAt: Date, messageCount: Int) {
        self.id = id
        self.title = title
        self.lastMessageAt = lastMessageAt
        self.messageCount = messageCount
    }
}
