import Foundation

// MARK: - Recursive Untagged JSONValue

public enum JSONValue: Sendable, Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let boolVal = try? container.decode(Bool.self) {
            self = .bool(boolVal)
        } else if let numVal = try? container.decode(Double.self) {
            self = .number(numVal)
        } else if let strVal = try? container.decode(String.self) {
            self = .string(strVal)
        } else if let arrayVal = try? container.decode([JSONValue].self) {
            self = .array(arrayVal)
        } else if let objectVal = try? container.decode([String: JSONValue].self) {
            self = .object(objectVal)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unable to decode JSONValue into known representation"
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}

// MARK: - Tool Definitions & Calls (OpenAI Compatible)

public struct ToolCall: Sendable, Codable, Equatable {
    public let id: String
    public let type: String
    public let function: FunctionCall

    public init(id: String, type: String = "function", function: FunctionCall) {
        self.id = id
        self.type = type
        self.function = function
    }

    public struct FunctionCall: Sendable, Codable, Equatable {
        public let name: String
        public let arguments: String

        public init(name: String, arguments: String) {
            self.name = name
            self.arguments = arguments
        }
    }
}

public struct ToolDefinition: Sendable, Codable, Equatable {
    public let type: String
    public let function: FunctionDefinition

    public init(type: String = "function", function: FunctionDefinition) {
        self.type = type
        self.function = function
    }

    public struct FunctionDefinition: Sendable, Codable, Equatable {
        public let name: String
        public let description: String?
        public let parameters: JSONValue?

        public init(name: String, description: String? = nil, parameters: JSONValue? = nil) {
            self.name = name
            self.description = description
            self.parameters = parameters
        }

        enum CodingKeys: String, CodingKey {
            case name
            case description
            case parameters
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encodeIfPresent(description, forKey: .description)
            try container.encodeIfPresent(parameters, forKey: .parameters)
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.name = try container.decode(String.self, forKey: .name)
            self.description = try container.decodeIfPresent(String.self, forKey: .description)
            self.parameters = try container.decodeIfPresent(JSONValue.self, forKey: .parameters)
        }
    }
}

// MARK: - Chat Completion Messages (Transport Only)

public struct ChatCompletionMessage: Sendable, Codable, Equatable {
    public let role: MessageRole
    public let content: String?
    public let toolCalls: [ToolCall]?
    public let toolCallId: String?
    public let reasoningContent: String?

    public init(
        role: MessageRole,
        content: String? = nil,
        toolCalls: [ToolCall]? = nil,
        toolCallId: String? = nil,
        reasoningContent: String? = nil
    ) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
        self.reasoningContent = reasoningContent
    }

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case toolCalls = "tool_calls"
        case toolCallId = "tool_call_id"
        case reasoningContent = "reasoning_content"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role.rawValue, forKey: .role)
        try container.encodeIfPresent(content, forKey: .content)
        try container.encodeIfPresent(toolCalls, forKey: .toolCalls)
        try container.encodeIfPresent(toolCallId, forKey: .toolCallId)
        try container.encodeIfPresent(reasoningContent, forKey: .reasoningContent)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let roleString = try container.decode(String.self, forKey: .role)
        guard let role = MessageRole(rawValue: roleString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .role,
                in: container,
                debugDescription: "Invalid MessageRole: \(roleString)"
            )
        }
        self.role = role
        self.content = try container.decodeIfPresent(String.self, forKey: .content)
        self.toolCalls = try container.decodeIfPresent([ToolCall].self, forKey: .toolCalls)
        self.toolCallId = try container.decodeIfPresent(String.self, forKey: .toolCallId)
        self.reasoningContent = try container.decodeIfPresent(String.self, forKey: .reasoningContent)
    }
}
