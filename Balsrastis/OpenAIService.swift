import Foundation

/// OpenAI implementation of `AIProviderProtocol`, using the Chat Completions API.
///
/// Exists for one reason: **it lets the whole app run on a single API key.**
/// Transcription already goes to OpenAI, so choosing this provider for the
/// cleanup step means one account instead of two. That was raised by a reader
/// who had neither an Anthropic account nor a paid OpenAI one, and put it
/// plainly — two billed accounts will put people off. Halving the setup is
/// worth more than a small quality edge for anyone who would otherwise never
/// get past the first screen.
///
/// **Claude remains the default**, because it is the configuration that was
/// actually measured: the C1 round put `claude-opus-4-8` against a Haiku-tier
/// model on 60 phrases and the cheaper model failed on meaning, not speed
/// (see AGENTS.md). This provider has had no such round, so it is offered as a
/// deliberate choice and not quietly substituted.
///
/// The Keychain account is the shared `.openai` entry — the same key the
/// transcriber uses. Selecting this provider requires no new key at all.
final class OpenAIService: AIProviderProtocol {

    let providerID: AIProviderID = .openai
    var modelIdentifier: String { model }

    private let model: String
    private let maxTokens: Int
    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    private let session: URLSession

    /// `gpt-4o-mini` rather than the full `gpt-4o`: the cleanup task is short and
    /// this keeps the cost close to what the transcription already costs, which
    /// is the point of the single-key path. Switchable here if it proves weak.
    init(model: String = "gpt-4o-mini", maxTokens: Int = 8192) {
        self.model = model
        self.maxTokens = maxTokens

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    // MARK: – AIProviderProtocol

    func process(text: String, mode: ProcessingMode) async throws -> String {
        guard let apiKey = try KeychainManager.shared.apiKey(for: providerID), !apiKey.isEmpty else {
            throw AIError.missingAPIKey(providerID)
        }

        let request = try makeRequest(apiKey: apiKey, text: text, mode: mode)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw AIError.networkTimeout
        } catch let urlError as URLError {
            throw AIError.network(urlError.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }

        try Self.validate(status: http.statusCode, data: data, headers: http)
        return try Self.parseText(from: data)
    }

    // MARK: – Request building

    private func makeRequest(apiKey: String, text: String, mode: ProcessingMode) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        // The mode's system prompt is reused verbatim. It is the same instruction
        // Claude receives — including the injection guard telling the model that
        // dictated commands are text to correct, not tasks to perform — so both
        // providers are held to the same contract, and so is the rejection check
        // in `ProcessingMode.cleanupRejectionReason` that runs on the result.
        let body = ChatRequest(
            model: model,
            maxTokens: maxTokens,
            messages: [.init(role: "system", content: mode.systemPrompt),
                       .init(role: "user", content: text)]
        )
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    // MARK: – Response handling

    private static func validate(status: Int, data: Data, headers: HTTPURLResponse) throws {
        switch status {
        case 200:
            return
        case 401:
            throw AIError.invalidAPIKey
        case 429:
            let retryAfter = (headers.value(forHTTPHeaderField: "retry-after")).flatMap { Int($0) }
            throw AIError.rateLimited(retryAfter: retryAfter)
        case 400:
            throw AIError.badRequest(decodeErrorMessage(from: data) ?? "invalid request")
        case 500...599:
            throw AIError.serverError(status: status)
        default:
            throw AIError.badRequest(decodeErrorMessage(from: data) ?? "HTTP \(status)")
        }
    }

    private static func parseText(from data: Data) throws -> String {
        guard let decoded = try? JSONDecoder().decode(ChatResponse.self, from: data),
              let first = decoded.choices.first else {
            throw AIError.invalidResponse
        }

        // A refusal comes back as 200 with `content` null and a `refusal` string;
        // surfacing it as an error keeps the caller from pasting an empty result.
        if let refusal = first.message.refusal, !refusal.isEmpty {
            throw AIError.badRequest("The model declined this request.")
        }

        let text = (first.message.content ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else { throw AIError.invalidResponse }
        return text
    }

    private static func decodeErrorMessage(from data: Data) -> String? {
        (try? JSONDecoder().decode(ChatErrorResponse.self, from: data))?.error.message
    }
}

// MARK: – OpenAI Chat Completions schema

private struct ChatRequest: Encodable {
    let model: String
    let maxTokens: Int
    let messages: [Message]

    enum CodingKeys: String, CodingKey {
        case model, messages
        case maxTokens = "max_completion_tokens"
    }

    struct Message: Encodable {
        let role: String
        let content: String
    }
}

private struct ChatResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String?
        let refusal: String?
    }
}

private struct ChatErrorResponse: Decodable {
    let error: Detail

    struct Detail: Decodable {
        let message: String
    }
}
