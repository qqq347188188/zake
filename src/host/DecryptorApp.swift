import SwiftUI
import Darwin

@main
struct DecryptorApp: App {
    init() {
        // TrollStore 环境下以 root 身份运行以获得全权限（失败则忽略）
        _ = setuid(0)
        _ = setgid(0)
    }

    var body: some Scene {
        WindowGroup {
            AppListView()
        }
    }
}
