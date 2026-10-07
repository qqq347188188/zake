import SwiftUI

struct AppListView: View {
    @State private var apps: [InstalledApp] = []
    @State private var log: [String] = []
    @State private var busy = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(busy ? "砸壳中…" : "一键砸壳全部应用") { Task { await dumpAll() } }
                        .disabled(busy)
                } header: { Text("批量操作") }

                Section("已安装应用（\(apps.count)）") {
                    ForEach(apps) { app in
                        NavigationLink(app.displayName, value: app)
                    }
                }
            }
            .navigationTitle("iOS 砸壳工具")
            .navigationDestination(for: InstalledApp.self) { app in
                AppDetailView(app: app, log: $log, busy: $busy)
            }
            .task {
                // 扫描涉及大量文件 I/O，放到后台线程，避免主线程卡死被 watchdog 杀
                let result = await Task.detached(priority: .userInitiated) {
                    AppScanner.scan()
                }.value
                apps = result
            }
            .refreshable {
                let result = await Task.detached(priority: .userInitiated) {
                    AppScanner.scan()
                }.value
                apps = result
            }
        }
    }

    func dumpAll() async {
        busy = true; defer { busy = false }
        for app in apps {
            let _ = try? Dumper.decrypt(app: app) { line in
                DispatchQueue.main.async { log.append(line) }
            }
        }
    }
}
