import Foundation

struct OpenAIProvider: AIProvider {
    var apiKey: String
    var model: String
    var session: URLSession = .shared

    func propose(command: String, context: AIContext) async throws -> (operation: AIEditOperation, replacement: String, summary: String) {
        guard !apiKey.isEmpty else { throw AIProviderError.notConfigured }
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "operation": ["type": "string", "enum": ["replaceSelection", "replaceParagraph", "replaceSection", "insertAtCursor"]],
                "replacement": ["type": "string"],
                "summary": ["type": "string"]
            ],
            "required": ["operation", "replacement", "summary"],
            "additionalProperties": false
        ]
        let system = """
        You are BOLD Writer's careful editing engine. Preserve the author's meaning and voice unless explicitly asked otherwise. Never invent an operation outside the supplied function schema. Return exactly one proposed edit. The app will preview it and validate the range before applying it.
        """
        let user = """
        COMMAND: \(command)
        SCOPE: \(context.scope.rawValue)
        LOCAL WRITING PREFERENCES: \(context.instructions)
        DOCUMENT OUTLINE: \(context.outline.prefix(80).joined(separator: " | "))
        TEXT TO WORK ON:
        \(context.text)
        """
        let body: [String: Any] = [
            "model": model,
            "input": [
                ["role": "system", "content": [["type": "input_text", "text": system]]],
                ["role": "user", "content": [["type": "input_text", "text": user]]]
            ],
            "tools": [[
                "type": "function",
                "name": "propose_document_edit",
                "description": "Propose one bounded, reversible edit to the provided text scope.",
                "parameters": schema,
                "strict": true
            ]],
            "tool_choice": ["type": "function", "name": "propose_document_edit"]
        ]
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIProviderError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let error = root?["error"] as? [String: Any]
            let message = error?["message"] as? String ?? "AI request failed (HTTP \(http.statusCode))."
            throw AIProviderError.service(message)
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let output = root["output"] as? [[String: Any]],
              let call = output.first(where: { $0["type"] as? String == "function_call" && $0["name"] as? String == "propose_document_edit" }),
              let rawArguments = call["arguments"] as? String,
              let argumentData = rawArguments.data(using: .utf8),
              let arguments = try JSONSerialization.jsonObject(with: argumentData) as? [String: Any],
              let rawOperation = arguments["operation"] as? String,
              let operation = AIEditOperation(rawValue: rawOperation),
              let replacement = arguments["replacement"] as? String,
              let summary = arguments["summary"] as? String else {
            throw AIProviderError.invalidResponse
        }
        return (operation, replacement, summary)
    }

    func testConnection() async throws {
        let context = AIContext(scope: .selection, range: NSRange(location: 0, length: 4), text: "Test", outline: [], instructions: "Return the text unchanged.", documentRevisionID: UUID())
        _ = try await propose(command: "Return this text unchanged.", context: context)
    }
}

extension OpenAIProvider: ManuscriptAnswerProvider {
    var displayName: String { "OpenAI" }
    var isLocal: Bool { false }

    func answer(question: String, evidence: [ManuscriptEvidence]) async throws -> ManuscriptAnswer {
        guard !apiKey.isEmpty else { throw ManuscriptAssistantError.providerUnavailable }
        let allowed = Set(evidence.map(\.id))
        let evidenceText = evidence.map { item in
            "SOURCE_ID: \(item.id)\nDOCUMENT: \(item.title)\nLOCATION: \(item.location)\nPASSAGE: \(item.excerpt)"
        }.joined(separator: "\n\n")
        let claimSchema: [String: Any] = [
            "type": "object",
            "properties": ["text": ["type": "string"], "source_ids": ["type": "array", "items": ["type": "string"]]],
            "required": ["text", "source_ids"], "additionalProperties": false
        ]
        let schema: [String: Any] = [
            "type": "object",
            "properties": ["claims": ["type": "array", "items": claimSchema], "uncertain_claims": ["type": "array", "items": ["type": "string"]]],
            "required": ["claims", "uncertain_claims"], "additionalProperties": false
        ]
        let system = "Answer only from supplied passages. Return each supported statement as a separate claim and attach at least one exact SOURCE_ID token that supports that claim. Separate what passages say from interpretation. Put unsupported or uncertain statements in uncertain_claims and do not present them as sourced claims. Never create IDs. Describe conflict as textual tension or interpretive difference rather than asserting truth."
        let user = "QUESTION: \(question)\n\nAUTHORIZED PASSAGES:\n\(evidenceText)"
        let body: [String: Any] = [
            "model": model,
            "input": [["role": "system", "content": [["type": "input_text", "text": system]]], ["role": "user", "content": [["type": "input_text", "text": user]]]],
            "tools": [["type": "function", "name": "grounded_answer", "description": "Answer from the given passages and select their exact IDs.", "parameters": schema, "strict": true]],
            "tool_choice": ["type": "function", "name": "grounded_answer"]
        ]
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIProviderError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw AIProviderError.service("OpenAI request failed (HTTP \(http.statusCode)).")
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let output = root["output"] as? [[String: Any]],
              let call = output.first(where: { $0["type"] as? String == "function_call" && $0["name"] as? String == "grounded_answer" }),
              let raw = call["arguments"] as? String,
              let bytes = raw.data(using: .utf8),
              let values = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let rawClaims = values["claims"] as? [[String: Any]], !rawClaims.isEmpty,
              let uncertain = values["uncertain_claims"] as? [String] else {
            throw ManuscriptAssistantError.invalidAnswer
        }
        let claims = rawClaims.compactMap { claim -> ManuscriptAnswer.Claim? in
            guard let text = claim["text"] as? String, !text.isEmpty,
                  let ids = claim["source_ids"] as? [String], !ids.isEmpty,
                  ids.allSatisfy(allowed.contains) else { return nil }
            return ManuscriptAnswer.Claim(text: text, sourceIDs: ids)
        }
        guard claims.count == rawClaims.count else { throw ManuscriptAssistantError.invalidAnswer }
        return ManuscriptAnswer(claims: claims, uncertainClaims: uncertain)
    }
}
