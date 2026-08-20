import Foundation

/// A fixed, privacy-safe label for why a dictation failed, for the usage log.
///
/// Exists because the week's log could not explain its own failures: four runs on
/// one machine (5.6% of that Mac's attempts) recorded a confirmed-speech
/// recording that produced no transcript, with no way to tell a network drop from
/// a rejected key from a rate limit. "Something failed 5.6% of the time" is not
/// an actionable number.
///
/// **The values are a closed set on purpose.** Logging `error.localizedDescription`
/// would be far easier and would defeat the log's central property: server
/// messages can quote request content, include URLs, or echo a key fragment, and
/// the whole point of this log is that it can be shared without review. Every case
/// here is a constant string chosen at compile time.
///
/// `unknown` is deliberately included. An unmapped error must still be visible as
/// *a failure that happened*, rather than vanishing into an empty column — but it
/// carries no detail beyond that.
enum FailureCategory: String {
    case networkTimeout       = "network_timeout"
    case network              = "network"
    case missingAPIKey        = "missing_api_key"
    case invalidAPIKey        = "invalid_api_key"
    case rateLimited          = "rate_limited"
    case badRequest           = "bad_request"
    case serverError          = "server_error"
    case invalidResponse      = "invalid_response"
    case emptyAudio           = "empty_audio"
    case notImplemented       = "not_implemented"
    case permission           = "local_or_system_permission"
    case cancelled            = "cancelled"
    case unknown              = "unknown"

    /// Maps a thrown error to its category. Nothing from the error's *text* is
    /// ever read — only its case — so no server-supplied string can reach the log.
    static func from(_ error: Error) -> FailureCategory {
        if let sttError = error as? CloudTranscriptionError {
            switch sttError {
            case .missingAPIKey:   return .missingAPIKey
            case .invalidAPIKey:   return .invalidAPIKey
            case .rateLimited:     return .rateLimited
            case .networkTimeout:  return .networkTimeout
            case .network:         return .network
            case .badRequest:      return .badRequest
            case .serverError:     return .serverError
            case .invalidResponse: return .invalidResponse
            case .emptyAudio:      return .emptyAudio
            }
        }

        if let aiError = error as? AIError {
            switch aiError {
            case .missingAPIKey:   return .missingAPIKey
            case .invalidAPIKey:   return .invalidAPIKey
            case .rateLimited:     return .rateLimited
            case .networkTimeout:  return .networkTimeout
            case .network:         return .network
            case .badRequest:      return .badRequest
            case .serverError:     return .serverError
            case .invalidResponse: return .invalidResponse
            case .notImplemented:  return .notImplemented
            }
        }

        if error is AudioEngineError { return .permission }
        if error is CancellationError { return .cancelled }

        // URLError can surface from the paste/injection path or anywhere that
        // does not wrap it, so it is worth distinguishing from a true unknown.
        if let urlError = error as? URLError {
            return urlError.code == .timedOut ? .networkTimeout : .network
        }

        return .unknown
    }
}
