import SwiftUI
import Darwin

@main
struct DecryptorApp: App {
    init() {
        // 注意：TrollStore 应用以 mobile(uid 501) 运行，并非 root。
        // 切勿在启动期调用 setuid(0)/setgid(0)：一旦处于沙箱内，该调用会触发
        // seatbelt 直接 SIGKILL 进程且不产生任何 .ips，表现为“闪退无日志”。
        // 读取其它 App 的包只需 no-sandbox 权限，与 root 无关，故此处不做提权。
        Self.appendLaunchLog("init start (uid=\(getuid()))")
        Self.appendLaunchLog("init done")
    }

    var body: some Scene {
        WindowGroup {
            AppListView()
        }
    }

    /// 写启动日志到 App 沙盒 Documents/launch.log，便于在无 IPS 时定位崩因。
    /// 若文件不存在说明进程在 init 之前就被 AMFI/seatbelt 杀掉（签名/entitlement 问题）。
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
}
