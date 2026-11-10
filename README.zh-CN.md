<div align="center">
  <img src="Assets/purge-iOS-Default-1024x1024@1x.png" width="112" alt="Purge 应用图标" />
  <h1>Purge Memory Preview</h1>
  <p>用于查看磁盘占用和管理内存的原生 macOS 应用。</p>
  <p><a href="README.md">English</a> · 简体中文</p>
  <p>
    <a href="https://github.com/Alex-dev-sys/purge-memory-preview/releases"><b>下载预览版</b></a>
    · <a href="#内存">内存</a>
    · <a href="#从源码构建">从源码构建</a>
  </p>
  <a href="https://github.com/Alex-dev-sys/purge-memory-preview/actions/workflows/memory-preview.yml"><img src="https://img.shields.io/github/actions/workflow/status/Alex-dev-sys/purge-memory-preview/memory-preview.yml?branch=main&label=preview" alt="预览版构建状态" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT 许可证" /></a>
</div>

这是 [Purge](https://github.com/jithin-sabu/purge-app) 的 Memory Preview 分支。在原有磁盘清理功能的基础上，它增加了内存页面、俄语和英语选择，以及通过 GitHub Actions 构建的预览版。

预览版使用与上游不同的应用标识符、设置、数据和辅助程序名称。预览版采用临时签名，未经 Apple 公证，也不使用上游的 Sparkle 更新源。请从本仓库的 [Releases](https://github.com/Alex-dev-sys/purge-memory-preview/releases) 页面安装更新。

## 安装

1. 打开 [Releases](https://github.com/Alex-dev-sys/purge-memory-preview/releases)，从已完成的预发布版本中下载 `Purge-Memory-Preview-…dmg`。每个 DMG 同时支持 Apple 芯片和 Intel Mac。
2. 打开 DMG，将 **Purge Memory Preview** 拖入 **应用程序**。
3. 打开应用。macOS 可能要求你批准打开 App Store 以外分发的应用。
4. 如果需要使用完整扫描功能，请授予 **完全磁盘访问权限**。没有该权限时，Purge 仍提供有限扫描，并说明哪些位置无法读取。

要核对下载文件，请把该版本的 `SHA256SUMS.txt` 和 DMG 放在同一个文件夹中，然后运行：

```bash
cd ~/Downloads
shasum -a 256 -c SHA256SUMS.txt
```

输出 `OK` 表示文件与该版本发布的校验和一致。上游的 Homebrew cask 安装的是上游 Purge，不是此预览版。

## 语言

在 **设置 → 常规 → 语言** 中选择 **English**、**Русский** 或 **系统语言**，然后点击 **重新启动 Purge**，让整个应用应用新的语言。清理或进程操作进行期间不能重新启动。

俄语翻译覆盖界面、安全说明、访达/Siri 操作以及数量的复数形式。选择系统语言时也支持简体中文。该设置只影响 Purge，不改变 macOS 的语言。

## 内存

按 **⌘6** 打开内存页面，查看内存状态、估算的 RAM 占用、近期历史图，以及按应用和辅助进程分组的进程列表。

### 清理内存

清理控件位于 **内存** 页面和 **设置 → 内存** 中。点击 **清理内存（Clean Memory）**，通过系统的 `purge` 命令请求 macOS 释放可回收的文件缓存页。正在运行的应用会保持打开。应用的工作内存和有线内存仍由应用与 macOS 管理，因此不能保证释放特定数量的 RAM，也不能保证将占用降到指定目标。磁盘上的文件会保留。应用继续工作时，缓存可能再次增长；重新读取尚未缓存的文件时，可能暂时变慢。

内存清理使用一个可选的专用系统服务。启用该服务时，需要在 macOS 原生管理员对话框中批准；Purge 不保存密码。服务只运行固定的内存清理命令，不接受应用传入的任意 shell 命令或命令行参数。

清理后，应用比较请求前后的空闲 RAM 读数。结果是 **观察到的空闲内存增量**，而不是 `purge` 准确释放了多少字节：同一期间其他应用也可能分配或释放内存。请求完成后，可能显示 **未测得增加**。无法取得有效的前后采样时，应用会说明无法测量空闲内存的变化，而不是显示某个释放量。结果记录在 **内存历史** 中。

### 自动清理

自动内存清理默认 **关闭**。初始定时间隔为 30 分钟，占用阈值为 85%。在内存设置中选择触发条件：

| 触发条件 | 可选值 | 运行时机 |
| --- | --- | --- |
| **定时器** | 每 5、15、30 或 60 分钟 | 达到所选间隔且 Purge 正在运行、可以清理时触发。 |
| **RAM 占用** | 70%、80%、85%、90% 或 95% | 估算的已用 RAM 连续 30 秒达到或超过所选比例时触发。 |

该比例是请求释放缓存的触发条件，不是要将 RAM 降到的目标。已用 RAM 估算包含应用、有线和压缩内存；释放文件缓存后，空闲 RAM 可能增加，而该占用比例仍然很高。

自动请求之间至少间隔五分钟。按占用比例触发后，占用需要先降到所选阈值以下五个百分点，才可再次触发。系统服务也会拒绝相隔不足 60 秒的请求，避免繁忙的 Mac 不断清理刚刚重建的缓存。

磁盘清理或进程操作进行期间，手动按钮会禁用，自动请求会延后。自动清理只在 Purge 运行期间生效，睡眠时暂停。要在关闭窗口后继续使用，请启用 **将 Purge 保留在菜单栏**。退出 Purge 后不再发送自动请求；计划不会自行启动应用或单独运行清理。

### 读数与进程操作

物理内存分类与进程占用是两种不同的估算，都不能精确表示某个应用占系统已用内存的比例。macOS 会自动管理 RAM；空闲内存少并不意味着系统不健康。如果 macOS 尚未发送内存状态事件，页面会隐藏状态标签，而不是将其标成“正常”。

**退出** 和 **强制退出** 是分别确认的进程操作，只适用于已识别的用户应用。这些操作保护系统进程、Purge 及其辅助程序、被排除的应用，以及未通过身份检查的目标。正常退出不会悄悄升级为强制退出。内存清理不会使用这两种进程操作。历史和排除项保存在本机。

在 **设置 → 内存** 中，可以选择每一秒或两秒更新总体读数，开启可选的菜单栏指示器，或请求持续处于“警告”“严重”级别时的通知。通知需要选定状态持续 60 秒，并需要 macOS 通知权限。这些可选监控功能默认关闭。内存页面可见时，进程详情每五秒更新一次；后台进程轮询不运行。

## 磁盘工具

| 页面 | 功能 |
| --- | --- |
| **概览** | 磁盘已用、空闲和总空间；各类别占用；只读的未分类空间地图。 |
| **应用缓存** | 已知应用缓存、日志、崩溃报告和支持的系统残留，每项都有说明和安全标签。 |
| **开发工具** | 全局开发缓存、项目构建/依赖文件夹、未使用的模拟器及其运行时；保护活跃项目和已注册的 Git 工作树。 |
| **大文件** | 搜索和筛选个人文件、本地 AI 模型、虚拟机；逐字节重复文件检测；快速查看和访达操作。 |
| **应用卸载** | 查看应用及其支持文件、已删除应用的残留和命令行工具，先检查再移除。 |

**清理安全项目** 会合并应用缓存和开发工具中符合条件的结果。标有 **先检查** 和 **不确定** 的项目需要自行检查。磁盘清理还可以选择按计划执行，其设置与内存功能分开。

大文件是个人文件，不是缓存，不属于自动安全清理。**仅保留在 iCloud 中** 会从这台 Mac 移除已经完整同步的本地下载副本，同时保留 iCloud 文件；这是单独确认的操作。

在受支持的 Mac 上，概览也提供 Time Machine 本地快照和 Apple Intelligence 模型管理。移除模型需要 macOS 27 和 Apple 芯片；重新下载会向 Apple 的服务请求此前由 Purge 移除的模型集。

### 哪些内容可以恢复

默认情况下，文件和文件夹会移到 **废纸篓**。Purge 不会清空废纸篓，因此在你自行清空之前，仍可恢复这些文件。

部分操作使用系统或其他应用的移除机制，不经过废纸篓：

- iOS 模拟器及其运行时通过 Xcode 的 `simctl` 移除。
- Time Machine 本地快照通过 `tmutil` 移除；保留最新快照以及上次备份的快照。
- Apple Intelligence 模型通过 Apple 的资源服务释放，之后可以重新下载。
- 如果在检查面板中选择交给包管理器处理，命令行工具和 Homebrew cask 应用会由包管理器删除。

确认面板会在操作前说明具体行为。Docker Desktop 数据文件夹会移到废纸篓；Purge 不会运行 `docker system prune`。

## 从源码构建

需要 macOS 13 或更新版本，以及 Xcode 26 或更新版本。项目使用 Xcode 26 提供的 Swift 6.2 功能。仓库检查需要 Node.js 和 Python 3；只有重新生成已提交的品牌图标时才需要安装 npm 依赖。

请用独立的工作副本构建预览版：配置脚本会修改该副本中的标识符、辅助程序文件名和 URL 协议，并关闭 Sparkle 更新。

```bash
git clone https://github.com/Alex-dev-sys/purge-memory-preview.git
cd purge-memory-preview
python3 scripts/configure-memory-preview.py

xcodebuild build \
  -project purge.xcodeproj \
  -scheme purge \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath build/local \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGNING_ALLOWED=YES \
  ENABLE_HARDENED_RUNTIME=NO \
  COMPILER_INDEX_STORE_ENABLE=NO

open build/local/Build/Products/Debug/Purge.app
```

首次构建时，Swift Package Manager 会下载 [Sparkle](https://github.com/sparkle-project/Sparkle)。预览版仍链接该框架，但不启动更新器。预览版关闭 Hardened Runtime，因为临时签名的应用身份不能匹配 Sparkle 的 Developer ID 签名；发布流程会实际启动构建后的应用，检查这一点。

### 检查与测试

运行源码检查：

```bash
node scripts/lint-design-tokens.mjs
python3 scripts/check-localization.py
```

使用临时签名运行主要测试：

```bash
xcodebuild test \
  -project purge.xcodeproj \
  -scheme purge \
  -destination 'platform=macOS' \
  -derivedDataPath build/tests \
  -parallel-testing-enabled NO \
  -skip-testing:PurgeTests/ProcessRunnerTests \
  -skip-testing:PurgeTests/FolderSizingConcurrencyTests \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGNING_ALLOWED=YES
```

两个压力测试套件单独运行，使用相同的项目、scheme、目标平台和 derived-data 路径，将命令改为 `test-without-building`，并分别传入 `-only-testing:PurgeTests/ProcessRunnerTests` 或 `-only-testing:PurgeTests/FolderSizingConcurrencyTests`。CI 采用这种拆分，避免它们对工作线程池施压时干扰其他异步测试。

可选的 Apple Intelligence 语言别名集成测试需要在装有对应资源的 Mac 上设置 `PURGE_SYSTEM_INTEGRATION_TESTS=1`。常规别名解析测试使用固定测试数据。

重新生成品牌图标：

```bash
npm ci
npm run generate:icons
```

### GitHub 发布

推送到 `main`，或手动在 `main` 上运行 **Memory preview** 工作流，会并行启动测试和通用 Release 打包。两个任务都成功后才会发布。流程会校验签名和两种架构，实际启动应用，生成 DMG，然后将它与 `SHA256SUMS.txt` 一起发布；相同文件也保存为 Actions 构件。

Xcode 构建产物、编译器模块和 Swift 包按 Xcode 版本缓存。只有内容哈希一致的源码文件才会恢复时间戳，使未更改的文件能够复用编译结果。压力测试复用已构建的测试包。同一分支的新推送会取消较旧的预览版工作流。

## 隐私与安全

扫描、内存采样、排除项、设置和历史均在本机处理。文件内容和内存采样不会发送到 AI 服务。重复文件检测也在 Mac 本机进行。预览版不会访问上游 Sparkle 更新源；明确选择的下载操作，例如重新获取 Apple Intelligence 模型，会使用对应服务。

磁盘移除受允许列表和受保护路径约束。“其他内容”的只读地图不会移除文件。内存操作另有进程身份检查和排除规则。基础项目的安全模型和报告方式见 [SECURITY.md](SECURITY.md)；其中针对上游正式版的签名和更新说明不适用于此临时签名预览版。

## 卸载

通过应用菜单或设置中的 **卸载 Purge…**，先检查并移除应用的后台组件，再将应用本体移到废纸篓。这会关闭自动内存清理，并移除其专用系统服务；出现 macOS 管理员对话框时，请批准移除。除非另外选择移除，设置和历史会保留。完全磁盘访问权限需要在 macOS 系统设置中单独移除。

如果准备直接在访达中移除应用，请先打开内存清理标题旁的信息按钮（ⓘ），再选择 **移除内存清理权限（Remove memory cleaning permission）**，并批准移除该服务。只把应用拖入废纸篓不会移除单独安装的系统服务。

## 项目与许可证

本分支基于 Jithin Sabu 创建的 [jithin-sabu/purge-app](https://github.com/jithin-sabu/purge-app)。应用及本分支均采用 [MIT 许可证](LICENSE)。仓库开发说明见 [CONTRIBUTING.md](CONTRIBUTING.md)。
