import Foundation
import Translation

@available(macOS 26.0, *)
@MainActor
final class LocalTranslation {
    static let shared = LocalTranslation()

    private struct Request: Hashable {
        let text: String
        let target: String
    }

    private var sessions: [String: TranslationSession] = [:]
    private var recent: [Request: String] = [:]

    enum Failure: LocalizedError {
        case languagesMissing
        case unavailable

        var errorDescription: String? {
            switch self {
            case .languagesMissing: return "시스템 설정 → 일반 → 언어 및 지역 → 번역 언어에서 한국어와 English (US)를 내려받으세요."
            case .unavailable: return "Mac 번역을 완료하지 못했어요. 다시 눌러 주세요."
            }
        }
    }

    func translate(_ text: String, to target: String) async throws -> String {
        let request = Request(text: text, target: target)
        if let cached = recent[request] { return cached }

        let session: TranslationSession
        if let existing = sessions[target] {
            session = existing
        } else {
            let korean = Locale.Language(identifier: "ko-KR")
            let english = Locale.Language(identifier: "en-US")
            let source = target == "en" ? korean : english
            let destination = target == "en" ? english : korean
            session = TranslationSession(installedSource: source, target: destination)
            guard await session.isReady else { throw Failure.languagesMissing }
            sessions[target] = session
        }

        do {
            let result = try await session.translate(text).targetText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !result.isEmpty else { throw Failure.unavailable }
            if recent.count >= 128, let first = recent.keys.first { recent.removeValue(forKey: first) }
            recent[request] = result
            return result
        } catch {
            sessions.removeValue(forKey: target)
            throw Failure.unavailable
        }
    }
}
