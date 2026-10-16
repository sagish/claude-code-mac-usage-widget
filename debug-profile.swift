// Prints the raw JSON body of the OAuth profile endpoint (no secrets printed).
//
// The credential read below mirrors ClaudeUsageWidget.swift (// MARK: -
// Credentials) and must be kept in sync with it: same bounded wait on
// /usr/bin/security (an unanswered Keychain prompt must not hang the script),
// same hex decoding (`-w` prints hex when the value has any non-ASCII byte),
// same fallback to ~/.claude/.credentials.json.
import Foundation

let keychainTimeout: TimeInterval = 10

func runSecurity(_ args: [String]) -> Data? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    p.arguments = args
    let out = Pipe()
    p.standardOutput = out
    p.standardError = Pipe()
    let done = DispatchSemaphore(value: 0)
    p.terminationHandler = { _ in done.signal() }
    guard (try? p.run()) != nil else { return nil }
    if done.wait(timeout: .now() + keychainTimeout) == .timedOut {
        p.terminate()
        if done.wait(timeout: .now() + 2) == .timedOut {
            kill(p.processIdentifier, SIGKILL)
            _ = done.wait(timeout: .now() + 2)
        }
        return nil
    }
    guard p.terminationStatus == 0 else { return nil }
    return out.fileHandleForReading.readDataToEndOfFile()
}

func decodeHexIfNeeded(_ s: String) -> String {
    let hex = Array(s.utf8)
    guard !hex.isEmpty, hex.count % 2 == 0 else { return s }
    var out = [UInt8]()
    out.reserveCapacity(hex.count / 2)
    var i = 0
    while i < hex.count {
        guard let b = UInt8(String(decoding: hex[i..<i + 2], as: UTF8.self), radix: 16)
        else { return s }
        out.append(b)
        i += 2
    }
    return String(bytes: out, encoding: .utf8) ?? s
}

func readCredentialsString() -> String? {
    if let data = runSecurity(["find-generic-password", "-s", "Claude Code-credentials", "-w"]),
       let s = String(data: data, encoding: .utf8) {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return decodeHexIfNeeded(trimmed) }
    }
    let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/.credentials.json")
    if let d = try? Data(contentsOf: url) { return String(data: d, encoding: .utf8) }
    return nil
}

guard let raw = readCredentialsString(),
      let data = raw.data(using: .utf8),
      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let oauth = obj["claudeAiOauth"] as? [String: Any],
      let token = oauth["accessToken"] as? String else {
    print("NO_TOKEN")
    exit(1)
}

var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/profile")!)
req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

let sem = DispatchSemaphore(value: 0)
URLSession.shared.dataTask(with: req) { data, resp, err in
    if let err = err { print("ERROR: \(err.localizedDescription)") }
    if let http = resp as? HTTPURLResponse { print("STATUS: \(http.statusCode)") }
    if let data = data, let body = String(data: data, encoding: .utf8) {
        print(body)
    }
    sem.signal()
}.resume()
sem.wait()
