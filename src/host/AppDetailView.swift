import SwiftUI

struct AppDetailView: View {
    let app: InstalledApp
    @Binding var log: [String]
    @Binding var busy: Bool
    @State private var outputPath: String = ""

    var body: some View {
        Form {
            Section("应用信息") {
                LabeledContent("名称", value: app.displayName)
                LabeledContent("BundleID", value: app.bundleId)
                LabeledContent("已加密", value: app.isEncrypted ? "是" : "否")
                Text(app.appPath).font(.caption).foregroundStyle(.secondary)
            }

            Section("操作") {
                Button(busy ? "处理中…" : "砸壳（含小组件与框架）") { Task { await dump() } }
                    .disabled(busy)
                if !outputPath.isEmpty {
                    Button("打包为 IPA") { package() }
                    Text(outputPath).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("日志") {
                if log.isEmpty {
                    Text("暂无").foregroundStyle(.secondary)
                } else {
                    ForEach(log, id: \.self) { line in
                        Text(line).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(app.displayName)
    }

    func dump() async {
        busy = true; defer { busy = false }
        do {
            let out = try Dumper.decrypt(app: app) { line in
                DispatchQueue.main.async { log.append(line) }
            }
            outputPath = out.path
        } catch {
            log.append("错误: \(error.localizedDescription)")
        }
    }

    func package() {
        if let url = IpaPackager.zip(appDir: URL(fileURLWithPath: outputPath), bundleId: app.bundleId) {
            log.append("已生成 IPA: \(url.path)")
        } else {
            log.append("IPA 打包失败（设备可能未安装 zip）。解密后的 .app 目录仍在: \(outputPath)")
        }
    }
}
