// Claude Usage Widget — small always-on-top floating panel showing
// Claude Code usage limits (session / all models weekly / Fable weekly).
// Reads the Claude Code OAuth token from the macOS Keychain (or
// ~/.claude/.credentials.json) and polls the same usage endpoint that
// claude.ai/settings/usage renders.
//
// Build:  swiftc -O -o ClaudeUsageWidget ClaudeUsageWidget.swift
// Run:    ./ClaudeUsageWidget   (right-click the widget for Refresh / Quit)

import AppKit

// MARK: - Data

struct Metric {
    var pct: Double
    var resetsAt: Date?
}

struct Usage {
    var session: Metric?
    var weekly: Metric?
    var fable: Metric?
    var fableLabel: String?
}

enum FetchError: Error {
    case noToken
    case http(Int)
    case rateLimited(TimeInterval?) // 429, with the server's Retry-After if given
    case badResponse
}

// MARK: - Credentials

func readCredentialsString() -> String? {
    // 1) macOS Keychain (default storage on Mac)
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
    // 2) Plain-file fallback
    let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/.credentials.json")
    if let d = try? Data(contentsOf: url), let s = String(data: d, encoding: .utf8) {
        return s
    }
    return nil
}

func accessToken() -> String? {
    guard let raw = readCredentialsString(),
          let data = raw.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    if let oauth = obj["claudeAiOauth"] as? [String: Any],
       let tok = oauth["accessToken"] as? String { return tok }
    if let tok = obj["accessToken"] as? String { return tok }
    return nil
}

// MARK: - Fetch + parse

func parseDate(_ any: Any?) -> Date? {
    guard let s = any as? String else {
        if let t = any as? Double { return Date(timeIntervalSince1970: t) }
        return nil
    }
    let f1 = ISO8601DateFormatter()
    f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f1.date(from: s) { return d }
    let f2 = ISO8601DateFormatter()
    f2.formatOptions = [.withInternetDateTime]
    return f2.date(from: s)
}

/// `Retry-After` is either a number of seconds or an HTTP date.
func retryAfter(_ http: HTTPURLResponse) -> TimeInterval? {
    guard let raw = http.value(forHTTPHeaderField: "Retry-After")?
        .trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
    if let secs = Double(raw) { return max(secs, 0) }
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "GMT")
    f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    guard let date = f.date(from: raw) else { return nil }
    return max(date.timeIntervalSinceNow, 0)
}

func parseUsage(_ data: Data) -> Usage? {
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }

    func metric(_ any: Any?) -> Metric? {
        guard let d = any as? [String: Any] else { return nil }
        let raw = (d["utilization"] as? Double)
            ?? (d["utilization"] as? Int).map(Double.init)
            ?? (d["used_percent"] as? Double)
        guard let v = raw else { return nil }
        return Metric(pct: v, resetsAt: parseDate(d["resets_at"] ?? d["resetsAt"]))
    }

    var u = Usage()

    // Primary source: the `limits` array (session / weekly_all / weekly_scoped).
    if let limits = obj["limits"] as? [[String: Any]] {
        for l in limits {
            let raw = (l["percent"] as? Double) ?? (l["percent"] as? Int).map(Double.init)
            guard let p = raw else { continue }
            let m = Metric(pct: p, resetsAt: parseDate(l["resets_at"]))
            switch l["kind"] as? String {
            case "session": u.session = m
            case "weekly_all": u.weekly = m
            case "weekly_scoped":
                u.fable = m
                if let scope = l["scope"] as? [String: Any],
                   let model = scope["model"] as? [String: Any],
                   let name = model["display_name"] as? String {
                    u.fableLabel = name
                }
            default: break
            }
        }
    }

    // Fallback: legacy top-level buckets.
    if u.session == nil { u.session = metric(obj["five_hour"]) }
    if u.weekly == nil { u.weekly = metric(obj["seven_day"]) }
    if u.fable == nil {
        for key in ["seven_day_fable", "seven_day_opus", "seven_day_sonnet"] {
            if let m = metric(obj[key]) { u.fable = m; break }
        }
    }
    guard u.session != nil || u.weekly != nil || u.fable != nil else { return nil }

    // Normalize: if every value is a 0–1 fraction, scale to percent.
    let vals = [u.session?.pct, u.weekly?.pct, u.fable?.pct].compactMap { $0 }
    if let mx = vals.max(), mx <= 1.5 {
        u.session?.pct *= 100
        u.weekly?.pct *= 100
        u.fable?.pct *= 100
    }
    return u
}

func fetchUsage(completion: @escaping (Result<Usage, Error>) -> Void) {
    DispatchQueue.global(qos: .utility).async {
        guard let token = accessToken() else {
            DispatchQueue.main.async { completion(.failure(FetchError.noToken)) }
            return
        }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.timeoutInterval = 15
        URLSession.shared.dataTask(with: req) { data, resp, err in
            DispatchQueue.main.async {
                if let err = err { completion(.failure(err)); return }
                guard let http = resp as? HTTPURLResponse else {
                    completion(.failure(FetchError.badResponse)); return
                }
                guard http.statusCode == 200 else {
                    if http.statusCode == 429 {
                        completion(.failure(FetchError.rateLimited(retryAfter(http))))
                    } else {
                        completion(.failure(FetchError.http(http.statusCode)))
                    }
                    return
                }
                if let data = data, let usage = parseUsage(data) {
                    completion(.success(usage))
                } else {
                    completion(.failure(FetchError.badResponse))
                }
            }
        }.resume()
    }
}

func fetchProfile(completion: @escaping (String?) -> Void) {
    DispatchQueue.global(qos: .utility).async {
        guard let token = accessToken() else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/profile")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.timeoutInterval = 15
        URLSession.shared.dataTask(with: req) { data, _, _ in
            var result: String?
            if let data = data,
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let account = obj["account"] as? [String: Any]
                let name = (account?["full_name"] as? String)
                    ?? (account?["display_name"] as? String)
                    ?? (account?["email"] as? String)
                let org = (obj["organization"] as? [String: Any])?["name"] as? String
                switch (name, org) {
                case let (n?, o?): result = "\(n) · \(o)"
                case let (n?, nil): result = n
                case let (nil, o?): result = o
                default: result = nil
                }
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }
}

// MARK: - Views

final class PulsingDot: NSView {
    private let dot = CALayer()
    var color: NSColor = .tertiaryLabelColor { didSet { dot.backgroundColor = color.cgColor } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        dot.frame = bounds
        dot.cornerRadius = bounds.height / 2
        dot.backgroundColor = color.cgColor
        layer?.addSublayer(dot)
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = 1.0
        anim.toValue = 0.2
        anim.duration = 0.9
        anim.autoreverses = true
        anim.repeatCount = .infinity
        dot.add(anim, forKey: "pulse")
        toolTip = "Waiting for data…"
    }

    required init?(coder: NSCoder) { fatalError("unused") }
}

final class BarView: NSView {
    var value: Double = 0 { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds
        let radius = r.height / 2
        NSColor.labelColor.withAlphaComponent(0.13).setFill()
        NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill()

        let v = min(max(value, 0), 100)
        guard v > 0.5 else { return }
        let w = max(r.height, r.width * CGFloat(v) / 100.0)
        let fillRect = NSRect(x: 0, y: 0, width: w, height: r.height)
        barColor(v).setFill()
        NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius).fill()
    }

    private func barColor(_ v: Double) -> NSColor {
        if v >= 90 { return .systemRed }
        if v >= 70 { return .systemOrange }
        return NSColor(srgbRed: 0.31, green: 0.47, blue: 0.90, alpha: 1) // claude.ai blue
    }
}

final class Row {
    let name = NSTextField(labelWithString: "")
    let bar = BarView()
    let pct = NSTextField(labelWithString: "–")

    init(title: String) {
        name.stringValue = title
        name.font = .systemFont(ofSize: 11)
        name.textColor = .secondaryLabelColor
        pct.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        pct.alignment = .right
    }

    func update(_ m: Metric?, resetPrefix: String) {
        guard let m = m else {
            pct.stringValue = "–"
            bar.value = 0
            bar.toolTip = nil
            return
        }
        pct.stringValue = "\(Int(m.pct.rounded()))%"
        bar.value = m.pct
        if let d = m.resetsAt {
            let f = DateFormatter()
            f.dateFormat = "EEE h:mm a"
            bar.toolTip = "\(resetPrefix) \(f.string(from: d))"
            name.toolTip = bar.toolTip
        }
    }
}

// MARK: - Start at login (LaunchAgent)

let agentPlistURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/LaunchAgents/com.empathy.claude-usage-widget.plist")

func executablePath() -> String {
    let raw = CommandLine.arguments[0]
    if raw.hasPrefix("/") { return raw }
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(raw).standardizedFileURL.path
}

func setStartAtLogin(_ enabled: Bool) {
    if enabled {
        let plist: [String: Any] = [
            "Label": "com.empathy.claude-usage-widget",
            "ProgramArguments": [executablePath()],
            "RunAtLoad": true,
        ]
        try? FileManager.default.createDirectory(
            at: agentPlistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0) {
            try? data.write(to: agentPlistURL)
        }
        // Not loaded via launchctl here — that would spawn a second instance.
        // RunAtLoad picks it up at next login.
    } else {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["unload", agentPlistURL.path]
        try? p.run()
        p.waitUntilExit()
        try? FileManager.default.removeItem(at: agentPlistURL)
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: NSPanel!
    let sessionRow = Row(title: "Session")
    let weeklyRow = Row(title: "All models")
    let fableRow = Row(title: "Fable")
    let footer = NSTextField(labelWithString: "loading…")
    let userLabel = NSTextField(labelWithString: " ")
    let liveDot = PulsingDot(frame: NSRect(x: 0, y: 0, width: 7, height: 7))
    var timer: Timer?
    var sessionResetsAt: Date?
    var lastSuccess: Date?
    var sawFailure = false

    // Polling / rate-limit state. The endpoint answers 429 if it is hit too
    // often, so polling is deliberately slow — the numbers move over hours and
    // days — and the timer is rescheduled after every attempt instead of firing
    // on a fixed beat: successes go back to `basePoll`, failures double the
    // delay up to `maxPoll`, and a 429 honours Retry-After.
    let basePoll: TimeInterval = 5 * 60
    let maxPoll: TimeInterval = 30 * 60
    let minFetchGap: TimeInterval = 30 // debounces the ↻ button
    var pollInterval: TimeInterval = 5 * 60
    var nextFetchAllowed = Date.distantPast
    var rateLimitedUntil: Date?
    var lastFetchStarted: Date?
    var isFetching = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildPanel()
        refresh()
        fetchProfile { [weak self] label in
            self?.userLabel.stringValue = label ?? ""
        }
        // Tick the "resets in Xh Ym" footer (and any cool-off countdown)
        // between fetches
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.updateFooter()
        }
    }

    func buildPanel() {
        let width: CGFloat = 260, height: CGFloat = 184
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true

        let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        effect.material = .hudWindow
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        panel.contentView = effect

        let pad: CGFloat = 12
        let title = NSTextField(labelWithString: "Claude usage")
        title.font = .systemFont(ofSize: 11, weight: .semibold)
        title.frame = NSRect(x: pad, y: height - 26, width: 150, height: 14)
        effect.addSubview(title)

        liveDot.frame = NSRect(x: width - pad - 34, y: height - 21.5, width: 7, height: 7)
        effect.addSubview(liveDot)

        let refreshBtn = NSButton(title: "↻", target: self, action: #selector(refreshClicked))
        refreshBtn.isBordered = false
        refreshBtn.font = .systemFont(ofSize: 12)
        refreshBtn.frame = NSRect(x: width - pad - 18, y: height - 28, width: 18, height: 18)
        effect.addSubview(refreshBtn)

        userLabel.font = .systemFont(ofSize: 9)
        userLabel.textColor = .secondaryLabelColor
        userLabel.frame = NSRect(x: pad, y: height - 40, width: width - pad * 2, height: 12)
        userLabel.lineBreakMode = .byTruncatingTail
        effect.addSubview(userLabel)

        func place(_ row: Row, y: CGFloat) {
            row.name.frame = NSRect(x: pad, y: y, width: 66, height: 14)
            row.bar.frame = NSRect(x: pad + 70, y: y + 3.5, width: width - pad * 2 - 70 - 38, height: 7)
            row.pct.frame = NSRect(x: width - pad - 34, y: y, width: 34, height: 14)
            effect.addSubview(row.name)
            effect.addSubview(row.bar)
            effect.addSubview(row.pct)
        }

        place(sessionRow, y: height - 64)

        let weeklyHeader = NSTextField(labelWithString: "WEEKLY")
        weeklyHeader.font = .systemFont(ofSize: 8.5, weight: .semibold)
        weeklyHeader.textColor = .tertiaryLabelColor
        weeklyHeader.frame = NSRect(x: pad, y: height - 86, width: 100, height: 11)
        effect.addSubview(weeklyHeader)

        place(weeklyRow, y: height - 104)
        place(fableRow, y: height - 124)

        footer.font = .systemFont(ofSize: 9)
        footer.textColor = .tertiaryLabelColor
        footer.frame = NSRect(x: pad, y: 22, width: width - pad * 2, height: 12)
        footer.lineBreakMode = .byTruncatingTail
        effect.addSubview(footer)

        let loginToggle = NSButton(checkboxWithTitle: "Start at login",
                                   target: self, action: #selector(loginToggled(_:)))
        loginToggle.controlSize = .mini
        loginToggle.font = .systemFont(ofSize: 9)
        loginToggle.frame = NSRect(x: pad - 2, y: 4, width: 120, height: 16)
        loginToggle.state = FileManager.default.fileExists(atPath: agentPlistURL.path) ? .on : .off
        loginToggle.toolTip = "Launch the widget automatically when you log in"
        effect.addSubview(loginToggle)

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Refresh now", action: #selector(refreshClicked), keyEquivalent: "r"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Claude Usage Widget", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        effect.menu = menu

        // Restore last position, default to top-right corner
        panel.setFrameAutosaveName("ClaudeUsageWidget")
        if panel.frame.origin == .zero, let screen = NSScreen.main {
            let vf = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: vf.maxX - width - 16, y: vf.maxY - height - 16))
        }
        panel.orderFrontRegardless()
    }

    @objc func refreshClicked() { refresh(manual: true) }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func loginToggled(_ sender: NSButton) { setStartAtLogin(sender.state == .on) }

    func scheduleNextPoll(after delay: TimeInterval) {
        timer?.invalidate()
        // Only ever later than asked, so a cool-off is never cut short, and two
        // instances (or restarts) don't line up on the same second.
        let jittered = max(delay, 1) * Double.random(in: 1.0...1.15)
        timer = Timer.scheduledTimer(withTimeInterval: jittered, repeats: false) {
            [weak self] _ in self?.refresh()
        }
    }

    /// Problems are shown as a dot color + tooltip only; the panel keeps the
    /// last numbers it managed to fetch.
    func setStatus(_ color: NSColor, _ tip: String) {
        liveDot.color = color
        guard let last = lastSuccess else { liveDot.toolTip = tip; return }
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        liveDot.toolTip = "\(tip) · updated \(f.string(from: last))"
    }

    /// Sends at most one request at a time, never before `nextFetchAllowed`,
    /// and never at all while the server's 429 cool-off is still running.
    func refresh(manual: Bool = false) {
        if isFetching { return }
        if let started = lastFetchStarted, -started.timeIntervalSinceNow < minFetchGap {
            scheduleNextPoll(after: minFetchGap)
            return
        }
        if let until = rateLimitedUntil, until.timeIntervalSinceNow > 0 {
            // A 429 is a hard stop: not even a manual refresh may hit the API.
            scheduleNextPoll(after: until.timeIntervalSinceNow)
            return
        }
        let wait = nextFetchAllowed.timeIntervalSinceNow
        if wait > 0 && !manual {
            scheduleNextPoll(after: wait)
            return
        }

        isFetching = true
        lastFetchStarted = Date()
        fetchUsage { [weak self] result in
            guard let self = self else { return }
            self.isFetching = false
            switch result {
            case .success(let usage):
                self.sessionRow.update(usage.session, resetPrefix: "Resets")
                self.weeklyRow.update(usage.weekly, resetPrefix: "Resets")
                self.fableRow.update(usage.fable, resetPrefix: "Resets")
                if let label = usage.fableLabel { self.fableRow.name.stringValue = label }
                self.sessionResetsAt = usage.session?.resetsAt
                self.lastSuccess = Date()
                self.pollInterval = self.basePoll
                self.rateLimitedUntil = nil
                self.setStatus(.systemGreen, "Live")
                self.updateFooter()
            case .failure(let err):
                // Nothing is written into the panel on failure: the rows and
                // footer keep the last known values and only the dot changes.
                self.sawFailure = true
                // Every failure at least doubles the delay; a 429 prefers the
                // server's Retry-After when it sends one.
                var retry = min(self.pollInterval * 2, self.maxPoll)
                switch err {
                case FetchError.noToken:
                    self.setStatus(.systemRed, "Not signed in — run `claude` to sign in")
                case FetchError.http(let code) where code == 401 || code == 403:
                    self.setStatus(.systemRed, "Sign-in expired — open Claude Code")
                case FetchError.rateLimited(let after):
                    retry = min(max(after ?? retry, self.basePoll), self.maxPoll)
                    self.rateLimitedUntil = Date().addingTimeInterval(retry)
                    self.setStatus(.systemYellow, "Paused — Claude asked to slow down")
                default:
                    self.setStatus(.systemYellow, "Can't reach Claude — retrying")
                }
                self.pollInterval = retry
                self.updateFooter()
            }
            self.nextFetchAllowed = Date().addingTimeInterval(self.pollInterval)
            self.scheduleNextPoll(after: self.pollInterval)
        }
    }

    /// The footer only ever describes data, never an error. "updated" is the
    /// time of the last successful fetch, so stale numbers are never passed off
    /// as fresh ones.
    func updateFooter() {
        guard let last = lastSuccess else {
            if sawFailure { footer.stringValue = "no data yet" }
            return
        }
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        let stamp = "updated \(f.string(from: last))"
        guard let d = sessionResetsAt else { footer.stringValue = stamp; return }
        let secs = Int(d.timeIntervalSinceNow)
        if secs > 0 {
            let h = secs / 3600, m = (secs % 3600) / 60
            let rel = h > 0 ? "\(h) hr \(m) min" : "\(m) min"
            footer.stringValue = "Session resets in \(rel) · \(stamp)"
        } else {
            footer.stringValue = "Session reset · \(stamp)"
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
