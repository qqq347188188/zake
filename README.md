# Decryptor —— iOS 16.6 全权限砸壳工具（TrollStore）

在越狱（已装 TrollStore）的 iOS 16.6 设备上，对**所有已安装应用**进行内存级全权限砸壳，
输出解密后的可用应用包；自带的小组件（WidgetKit / 旧式 Today 扩展）在砸壳后仍能正常加载运行。
构建与发布通过 **GitHub Actions 云端 macOS runner** 完成，无需本地 Mac。

---

## 工作原理

App Store 应用经 FairPlay 加密，磁盘上的 `__TEXT` 等段为密文；但 `dyld` 加载到内存后会解密。
本项目采用业界成熟的**动态注入内存写回**方案：

1. 主机 App（本工具）以 root 身份运行，借助 `posix_spawn` 派生目标 App 的可执行文件，
   并通过环境变量 `DYLD_INSERT_LIBRARIES` 注入 `dumpdecrypted.dylib`。
2. `dumpdecrypted.dylib` 在目标进程内执行构造函数：
   - 遍历 `_dyld_image_count()` 中所有已加载镜像；
   - 仅处理 `cryptid == 1` 且路径位于目标 Bundle 下的镜像（主程序 + 内嵌 Framework + 扩展）；
   - 把内存中的明文逐段（`LC_SEGMENT_64`）`pwrite` 写回文件，并将 `cryptid` 置 0。
3. 解密完成后 `_exit(0)`，目标 App 不会真正启动。
4. 主机收集产物并可选打包为 `.ipa`（TrollStore 安装时会重新签名）。

### 小组件为何可用

- 小组件是独立的 `.appex` 扩展进程，自带加密二进制。
- 工具对每个 `PlugIns/*.appex` 单独注入解密，因此其 `Info.plist` 中的 `NSExtension` 配置、
  资源、以及解密后的二进制都被原样保留。
- 解密只改写二进制内容、不动任何元数据，故 `pkd`（插件守护进程）仍能正确识别并加载组件。

---

## 关键实现文件

| 文件 | 作用 |
|------|------|
| `src/dumpdecrypted/dumpdecrypted.c` | 注入式解密核心，遍历所有加密镜像并写回 |
| `src/dumpdecrypted/dylib_entitlements.plist` | 允许目标 App 加载未签名 dylib 的权限 |
| `src/host/Dumper.swift` | 编排注入、遍历主程序+框架+组件 |
| `src/host/AppScanner.swift` | 扫描已装应用、判断加密状态 |
| `src/host/IpaPackager.swift` | 将解密 `.app` 打包为 IPA |
| `src/host/entitlements.plist` | 主机 App 的越狱权限（去沙箱、签名绕过等） |
| `project.yml` | xcodegen 工程定义 |
| `.github/workflows/release.yml` | 云端构建并发布 IPA |

---

## iOS 16.6 注入要点（重要）

- **dyld4 关闭 closure**：iOS 16 默认使用 dyld4，会忽略 `DYLD_INSERT_LIBRARIES`。
  必须同时设置 `DYLD_USE_CLOSURES=0`（`Dumper.spawnDump` 已设置）。
- **未签名 dylib 加载**：目标 App 需要 `com.apple.private.skip-library-validation`
  才能加载本工具的 dylib，已写入 `dylib_entitlements.plist` 并随构建签名。
- **root 派生避免 DYLD 被剥离**：App 在 `DecryptorApp.init()` 调用 `setuid(0)`，
  以 root 派生目标进程，使 `DYLD_*` 环境变量不会被系统 sanitize 掉。
- **全权限**：主机 App 持有 `no-sandbox` / `skip-library-validation` / `get-task-allow` 等权限，
  可读取任意 App 目录、派生任意进程。

> 说明：少数带有强反调试 / `amfi` 强校验的 App 可能需要额外绕过（如 `task_for_pid` 注入或
> 关闭 `com.apple.security.cs` 相关校验）。本工具覆盖绝大多数 App Store 应用；
> 如遇个别应用失败，可结合 TrollStore / Ellekit 注入能力进一步适配。

---

## 使用流程

1. Fork 本仓库，推送一个 `v*` 标签（如 `v1.0.0`），或手动触发 `workflow_dispatch`。
2. GitHub Actions 自动构建出 `Decryptor.ipa` 并发布到 Release（也提供 Artifact 下载）。
3. 用 TrollStore 安装 `Decryptor.ipa`。
4. 打开「砸壳工具」：
   - 点「一键砸壳全部应用」批量处理；或进入单个应用点「砸壳（含小组件与框架）」。
   - 解密后的 `.app` 位于 App 沙盒 `Documents/Decrypted/<bundleId>.app`。
   - 点「打包为 IPA」生成可迁移的 `*.ipa`（设备需装有 `zip`，否则直接用 `.app` 目录）。
5. 通过 Filza / TrollStore 安装解密产物；小组件会在系统重新扫描后正常显示。

---

## 本地构建（可选，需 macOS）

```bash
brew install xcodegen
bash scripts/build.sh      # 产出 Decryptor.ipa
```

---

## 免责声明

本工具仅用于对自己拥有合法授权的设备与应用进行安全研究、备份与学习。
请遵守所在地区法律法规，勿对他人应用进行未经授权的分发或商用。
