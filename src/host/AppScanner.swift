import Foundation

/// 扫描设备上已安装应用，并判断主二进制是否加密
struct AppScanner {

    /// 返回所有已安装应用（系统 /Applications 与用户 /var/containers/Bundle/Application）
    static func scan() -> [InstalledApp] {
        var result: [InstalledApp] = []
        let roots = ["/Applications", "/var/containers/Bundle/Application"]
        let fm = FileManager.default
        for root in roots {
            let url = URL(fileURLWithPath: root)
            guard let entries = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else { continue }
            for entry in entries {
                if entry.pathExtension == "app" {
                    if let a = parse(appURL: entry) { result.append(a) }
                } else if entry.hasDirectoryPath {
                    // UUID 容器中可能含 .app
                    if let subs = try? fm.contentsOfDirectory(at: entry, includingPropertiesForKeys: nil) {
                        for sub in subs where sub.pathExtension == "app" {
                            if let a = parse(appURL: sub) { result.append(a) }
                        }
                    }
                }
            }
        }
        return result.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    /// 读取 .app 内 Info.plist 的 CFBundleExecutable
    static func executable(in appPath: String) -> String? {
        let plist = URL(fileURLWithPath: appPath).appendingPathComponent("Info.plist")
        guard let dict = NSDictionary(contentsOf: plist) as? [String: Any] else { return nil }
        let name = (dict["CFBundleExecutable"] as? String)
            ?? appPath.components(separatedBy: "/").last?.replacingOccurrences(of: ".app", with: "")
        guard let n = name else { return nil }
        let p = URL(fileURLWithPath: appPath).appendingPathComponent(n).path
        return FileManager.default.fileExists(atPath: p) ? p : nil
    }

    static func parse(appURL: URL) -> InstalledApp? {
        guard let exec = executable(in: appURL.path) else { return nil }
        let plist = appURL.appendingPathComponent("Info.plist")
        let dict = (NSDictionary(contentsOf: plist) as? [String: Any]) ?? [:]
        let name = (dict["CFBundleDisplayName"] as? String)
            ?? (dict["CFBundleName"] as? String)
            ?? appURL.lastPathComponent
        let bid = (dict["CFBundleIdentifier"] as? String) ?? "unknown"
        return InstalledApp(
            bundleId: bid,
            displayName: name,
            appPath: appURL.path,
            executablePath: exec,
            isEncrypted: isEncrypted(path: exec)
        )
    }

    /// 快速判断 Mach-O 是否含 LC_ENCRYPTION_INFO(_64) 且 cryptid == 1
    static func isEncrypted(path: String) -> Bool {
        guard let fh = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? fh.close() }
        guard let data = try? fh.read(upToCount: 256 * 1024), data.count > 32 else { return false }

        let magic = data.subdata(in: 0..<4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        let is64 = (magic == 0xfeedfacf) // MH_MAGIC_64
        guard is64 else { return false }

        let headerSize = 32
        guard data.count > headerSize + 4 else { return false }
        let ncmds = data.subdata(in: 16..<20).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }

        var offset = headerSize
        for _ in 0..<ncmds {
            guard data.count >= offset + 8 else { break }
            let cmd = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
            let cmdsize = data.subdata(in: (offset + 4)..<(offset + 8)).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
            if cmd == 0x2c /* LC_ENCRYPTION_INFO_64 */ || cmd == 0x2b /* LC_ENCRYPTION_INFO */ {
                if data.count >= offset + 20 {
                    let cryptid = data.subdata(in: (offset + 16)..<(offset + 20)).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
                    if cryptid == 1 { return true }
                }
            }
            offset += Int(cmdsize)
        }
        return false
    }
}
