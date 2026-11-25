import Foundation

/// This object is responsible for one signal an AI coding tool leaves in DeskPet's inbox folder through its own hook:
/// what happened (working, done, waiting for the user, limit reached), which tool sent it and the tool's process.
/// It carries no message, path or conversation text; anything else in the file is ignored.
struct AgentSignal: Equatable {
    enum Kind: String, CaseIterable {
        /// 사용자가 일을 맡김
        case working
        /// 맡은 일을 끝냄
        case done
        /// 사용자 확인(권한 요청 등)을 기다림
        case waiting
        /// 사용 한도에 닿음
        case limit
    }

    let kind: Kind
    /// 보낸 도구 이름 (claude, codex …)
    let source: String
    /// 보낸 도구의 프로세스 ID. 이 프로세스를 품은 앱의 아이콘을 찾음
    let processID: Int32?

    /// 신호 파일 최대 크기 (이보다 크면 읽지 않음)
    static let maxBytes = 1024
    /// 이보다 오래된 신호 파일은 버림 (앱이 꺼져 있던 동안 쌓인 것)
    static let maxAge: TimeInterval = 120

    /// 같은 세션의 신호를 묶는 이름 (기다림 말풍선을 다음 신호로 거두기 위함)
    var sessionTopic: String { "agent:\(source):\(processID ?? 0)" }

    /// {"kind": "done", "source": "claude", "pid": 1234}. kind가 모르는 값이면 nil
    static func parse(_ data: Data) -> AgentSignal? {
        guard data.count <= maxBytes,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = json["kind"] as? String, let kind = Kind(rawValue: raw.lowercased()) else { return nil }
        let pid = JSONNumber.double(json["pid"]).flatMap { $0 >= 1 && $0 <= Double(Int32.max) ? Int32($0) : nil }
        return AgentSignal(kind: kind, source: sourceName(json["source"]), processID: pid)
    }

    /// 영문 소문자·숫자·`-_.`만 남긴 32자 이내 이름. 비면 "agent"
    private static func sourceName(_ value: Any?) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-_.")
        let name = String(((value as? String) ?? "").lowercased().filter { allowed.contains($0) }.prefix(32))
        return name.isEmpty ? "agent" : name
    }
}

/// 신호를 보낸 세션이 사는 앱 (창이 있는 앱)
struct AgentHost: Equatable {
    /// 그 앱의 프로세스 ID (사용자가 그 앱으로 돌아갔는지 보기 위함)
    let processID: Int32
    /// 말풍선에 붙일 앱 아이콘
    let badge: SpeechBadge?
    /// 그 앱의 Dock(작업 표시줄) 아이콘 자리 (전역 좌표). 모르거나 끈 경우 nil
    var dockIcon: CGRect? = nil
}
