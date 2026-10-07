import Foundation

struct InstalledApp: Identifiable, Hashable {
    let id = UUID()
    let bundleId: String
    let displayName: String
    let appPath: String        // .app 目录路径
    let executablePath: String // 主可执行文件路径
    let isEncrypted: Bool
}
