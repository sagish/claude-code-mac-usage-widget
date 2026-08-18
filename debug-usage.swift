// Prints the raw JSON body of the OAuth usage endpoint (no secrets printed).
import Foundation

func readCredentialsString() -> String? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    p.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = Pipe()
    if (try? p.run()) != nil {
        p.waitUntilExit()
        if p.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let s = String(data: data, encoding: .utf8), !s.isEmpty {
                return s.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
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

var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
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
