import Foundation
import Darwin

/// 编排「注入 -> 内存解密 -> 产物落盘」，并对主程序与小组件分别处理
struct Dumper {

    /// 解密单个应用（含其内嵌 Framework 与所有小组件扩展）。
    /// - Returns: 解密后的 .app 目录 URL
    static func decrypt(app: InstalledApp,
                        progress: @escaping (String) -> Void) throws -> URL {
        guard let dylib = Bundle.main.path(forResource: "dumpdecrypted", ofType: "dylib") else {
            throw NSError(domain: "Dumper", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "找不到 dumpdecrypted.dylib"])
        }

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let outDir = docs.appendingPathComponent("Decrypted/\(app.bundleId).app")
        try? FileManager.default.removeItem(at: outDir)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        // 收集待解密二进制：主程序 + 每个 PlugIns/*.appex 的主二进制
        var binaries: [(path: String, root: String)] = [(app.executablePath, app.appPath)]
        let plugins = URL(fileURLWithPath: app.appPath).appendingPathComponent("PlugIns")
        if let subs = try? FileManager.default.contentsOfDirectory(at: plugins, includingPropertiesForKeys: nil) {
            for sub in subs where sub.pathExtension == "appex" {
                if let exec = AppScanner.executable(in: sub.path) {
                    binaries.append((exec, sub.path))
                }
            }
        }

        progress("共需解密 \(binaries.count) 个二进制（主程序 + 框架 + 小组件）")
        for bin in binaries {
            progress("砸壳: \(URL(fileURLWithPath: bin.path).lastPathComponent)")
            try spawnDump(binary: bin.path, root: bin.root, dylib: dylib, out: outDir.path)
        }
        progress("完成 -> \(outDir.path)")
        return outDir
    }

    /// 通过 posix_spawn + DYLD_INSERT_LIBRARIES 注入解密 dylib。
    /// 进程以 root 身份派生，DYLD 环境变量不会被剥离；iOS 16 需禁用 dyld4 closure。
    private static func spawnDump(binary: String, root: String, dylib: String, out: String) throws {
        setenv("DYLD_INSERT_LIBRARIES", dylib, 1)
        setenv("DYLD_USE_CLOSURES", "0", 1) // iOS 16 dyld4：关闭 closure 才会处理 DYLD_INSERT_LIBRARIES
        setenv("DUMP_OUTPUT_DIR", out, 1)
        setenv("DUMP_BUNDLE_ROOT", root, 1)

        var pid: pid_t = 0
        let binC = strdup(binary)
        var argv: [UnsafeMutablePointer<CChar>?] = [binC, strdup("-dump"), nil]
        let rc = posix_spawn(&pid, binary, nil, nil, &argv, nil)
        free(binC)
        if rc != 0 {
            throw NSError(domain: "Dumper", code: Int(rc),
                          userInfo: [NSLocalizedDescriptionKey: "posix_spawn 失败（码 \(rc)）"])
        }

        // 等待 dylib 写入完成标记；超时说明注入未生效，强制终止残留进程以防挂起
        let donePath = (out as NSString).appendingPathComponent(".dump_done")
        var waited = 0
        while waited < 15_000_000 {
            if FileManager.default.fileExists(atPath: donePath) { break }
            usleep(200_000)
            waited += 200_000
        }
        if !FileManager.default.fileExists(atPath: donePath) {
            kill(pid, SIGKILL)
        }
        var status: Int32 = 0
        waitpid(pid, &status, 0)
    }
}
