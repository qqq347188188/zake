import Foundation
import Darwin

/// 把解密后的 .app 目录打包为可用 IPA（TrollStore 安装时会重新签名）
struct IpaPackager {

    /// - Returns: 生成的 .ipa 路径；设备缺少 zip 时返回 nil（此时 .app 目录仍可用）
    static func zip(appDir: URL, bundleId: String) -> URL? {
        let parent = appDir.deletingLastPathComponent()
        let ipaURL = parent.appendingPathComponent("\(bundleId).ipa")
        try? FileManager.default.removeItem(at: ipaURL)

        let payload = parent.appendingPathComponent("Payload")
        try? FileManager.default.removeItem(at: payload)
        try? FileManager.default.createDirectory(at: payload, withIntermediateDirectories: true)
        let destApp = payload.appendingPathComponent(appDir.lastPathComponent)
        try? FileManager.default.copyItem(at: appDir, to: destApp)
        // 移除解密过程中产生的临时文件（.dump_done / .dump.log 等）
        removeDotFiles(at: destApp)
        defer { try? FileManager.default.removeItem(at: payload) }

        let candidates = ["/usr/bin/zip", "/bin/zip", "/usr/local/bin/zip"]
        for zip in candidates where FileManager.default.fileExists(atPath: zip) {
            FileManager.default.changeCurrentDirectoryPath(parent.path)
            var pid: pid_t = 0
            var argv: [UnsafeMutablePointer<CChar>?] = [
                strdup(zip), strdup("-r"), strdup("-q"),
                strdup(ipaURL.path), strdup("Payload"), nil
            ]
            let rc = posix_spawn(&pid, zip, nil, nil, &argv, nil)
            if rc == 0 {
                waitpid(pid, nil, 0)
                return FileManager.default.fileExists(atPath: ipaURL.path) ? ipaURL : nil
            }
        }
        return nil
    }

    /// 递归删除路径下所有以 "." 开头的临时文件/目录
    private static func removeDotFiles(at root: URL) {
        guard let children = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for child in children {
            if child.lastPathComponent.hasPrefix(".") {
                try? FileManager.default.removeItem(at: child)
            } else if child.hasDirectoryPath {
                removeDotFiles(at: child)
            }
        }
    }
}
