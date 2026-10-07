import SwiftUI
import Darwin

@main
struct DecryptorApp: App {
    init() {
        Self.installCrashLogging()
        Self.appendLaunchLog("init start (uid=\(getuid()))")
        Self.appendLaunchLog("init done")
    }

    var body: some Scene {
        WindowGroup {
            AppListView()
        }
    }

    // MARK: - 崩溃记录（写 Documents/crash.log，便于无 IPS 时定位）

    private static var crashLoggingInstalled = false

    private static func installCrashLogging() {
        guard !crashLoggingInstalled else { return }
        crashLoggingInstalled = true

        NSSetUncaughtExceptionHandler { exc in
            let trace = (exc.callStackSymbols as? [String])?.joined(separator: "\n") ?? "<no symbols>"
            appendCrashLog("NSException: \(exc.name.rawValue) reason=\(exc.reason ?? "")\n\(trace)")
        }

        let action: @convention(c) (Int32) -> Void = { sig in
            var addresses: [UnsafeMutableRawPointer?] = Array(repeating: nil, count: 64)
            let count = backtrace(&addresses, Int32(addresses.count))
            var out = "SIGNAL \(sig)\n"
            if let symbols = backtrace_symbols(&addresses, count) {
                for i in 0..<Int(count) {
                    if let s = symbols[i] {
                        out += String(cString: s) + "\n"
                    }
                }
                free(symbols)
            }
            appendCrashLog(out)
            // 恢复原处理并重新触发，便于系统也记录一份
            signal(sig, SIG_DFL)
            raise(sig)
        }
        signal(SIGABRT, action)
        signal(SIGSEGV, action)
        signal(SIGBUS, action)
        signal(SIGILL, action)
        signal(SIGTRAP, action)
    }

    private static func appendLaunchLog(_ s: String) {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let f = dir.appendingPathComponent("launch.log")
        let line = "\(Date()) \(s)\n"
        if let fh = try? FileHandle(forWritingTo: f) {
            fh.seekToEndOfFile()
            fh.write(line.data(using: .utf8) ?? Data())
            try? fh.close()
        } else {
            try? line.write(to: f, atomically: true, encoding: .utf8)
        }
    }

    private static func appendCrashLog(_ s: String) {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let f = dir.appendingPathComponent("crash.log")
        let line = "\(Date()) \(s)\n"
        if let fh = try? FileHandle(forWritingTo: f) {
            fh.seekToEndOfFile()
            fh.write(line.data(using: .utf8) ?? Data())
            try? fh.close()
        } else {
            try? line.write(to: f, atomically: true, encoding: .utf8)
        }
    }
}
