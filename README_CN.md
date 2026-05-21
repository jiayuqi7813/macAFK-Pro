# MacAfk Pro - macOS 防休眠工具

![image](./assets/image.png)

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS-blue" alt="Platform">
  <img src="https://img.shields.io/badge/swift-5.0-orange" alt="Swift">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
</p>

<p align="center">
  <a href="README.md">English</a> | <a href="README_CN.md">中文</a>
</p>

>由于大多数企业电脑的 macOS 存在通过 MDM 管控禁止用户修改锁屏时间的情况，并且现在很多人都习惯将任务分配给 LLM Agent，然后自己去~~摸鱼~~。而此时电脑锁屏会影响大模型任务失败，所以开发了这款程序。

>你可以安心地打开它,它会通过鼠标细微（根本无法察觉）的抖动来防止系统进入休眠状态。

---

## ✨ 主要特性

### 🖱️ 防休眠功能
- **自动鼠标抖动** - 防止系统进入休眠状态
- **可调节间隔** - 10秒到10分钟，6个档位可选
- **无感操作** - 1像素移动，完全不影响工作

### 🌙 智能亮度控制（Pro）
- **内置屏** - 通过 DisplayServices API 进行真实硬件亮度控制
- **外接屏** - 通过 [BetterDisplay](https://github.com/waydabber/BetterDisplay) Integration API 控制亮度
- **低亮度模式** - 抖动运行期间自动降低屏幕亮度
- **错误提示** - 映射失败或控制失败时在界面中显示

### ⌨️ 强大的快捷键系统
- **全局快捷键** - 后台运行也能快速控制
- **完全自定义** - 可视化编辑器，支持冲突检测
- **自动保存** - 配置持久化，重启后保留

### 🎨 现代化界面
- **SwiftUI 构建** - 原生 macOS 体验
- **状态栏集成** - 轻量化，不占用 Dock 空间
- **偏好设置窗口** - 显示、常规、语言与更新设置

---

## 🚀 快速开始

### 下载安装

从 GitHub Releases 下载：

```bash
https://github.com/jiayuqi7813/macAFK-Pro/releases
```

### 首次运行

1. **授予辅助功能权限**
   - 打开「系统设置」→「隐私与安全性」→「辅助功能」
   - 添加 MacAfk Pro 并启用

2. **启动应用**
   - 点击状态栏图标
   - 或使用快捷键 `⌘ ⌃ S`

3. **开始使用**
   - 开启防休眠：点击按钮或按 `⌘ ⌃ S`
   - 启用低亮度：勾选开关或按 `⌘ ⌃ B`

---

## ⌨️ 默认快捷键

| 快捷键 | 功能 |
|--------|------|
| `⌘ ⌃ S` | 切换防休眠 |
| `⌘ ⌃ B` | 切换低亮度模式 |
| `⌘ ⌃ ↑` | 增加抖动间隔 |
| `⌘ ⌃ ↓` | 减少抖动间隔 |

**自定义快捷键**：点击主界面的「自定义所有快捷键」按钮

---

## 🔧 从源码构建

### 环境要求
- macOS 26.0+
- Xcode 15.0+
- Swift 5.0+

### 构建步骤

```bash
cd MacAfk
xcodebuild -scheme MacAfk -configuration Debug build
xcodebuild -scheme MacAfk -configuration Release build
```

### 运行测试

```bash
xcodebuild -scheme MacAfk -destination 'platform=macOS' test
```

---

## 📖 使用场景

### 场景1：AI Agent 自动挂起
```
问题：企业管控5分钟自动锁定，AI Agent 会被锁屏网络影响导致任务失败
解决：⌘ ⌃ S 启动防休眠，设置较长间隔（5-10分钟）
```

### 场景2：下载/处理任务 ⏬
```
问题：长时间任务但不想屏幕一直亮着
解决：⌘ ⌃ S + ⌘ ⌃ B（低亮度模式省电）
```

### 场景3：远程工作 💻
```
问题：需要保持连接但暂时离开
解决：⌘ ⌃ S 保持活跃状态，避免断开连接
```

---

## 🛠️ 技术架构

```
MacAfk
├── AppModel.swift              # 应用状态管理
├── BrightnessControl.swift     # DisplayServices + BetterDisplay 亮度控制
├── BetterDisplayManager.swift  # BetterDisplay Integration API 客户端
├── Jiggler.swift               # 鼠标抖动引擎
├── ShortcutManager.swift       # 快捷键管理系统
├── ShortcutEditorView.swift    # 快捷键编辑器
├── ContentView.swift           # 主界面
├── NewPreferencesView.swift    # 偏好设置界面
└── AppDelegate.swift           # 状态栏集成
```

---

## 🤝 贡献指南

欢迎贡献代码、报告问题或提出建议！

### 开发流程
1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 开启 Pull Request

---

## ❓ 常见问题

### Q: 从 GitHub Release 安装时提示「文件已损坏」？
A: 这是 macOS Gatekeeper 安全机制。由于应用未公证，需要移除隔离属性：

```bash
xattr -cr /Applications/MacAfk\ Pro.app/
```

然后重新打开，或右键选择「打开」。

### Q: 快捷键不生效？
A: 请在「系统设置」→「隐私与安全性」→「辅助功能」中授予 MacAfk Pro 权限。

### Q: 是否支持外接显示器？
A: 支持。MacAfk Pro 原生控制内置屏，外接屏通过 BetterDisplay 控制。

**技术方案：**
- **内置屏**：DisplayServices API（原生硬件控制）
- **外接屏**：[BetterDisplay](https://github.com/waydabber/BetterDisplay) Integration API

**外接屏前置条件：**
1. 安装 [BetterDisplay](https://github.com/waydabber/BetterDisplay)（免费版即可）
2. 在 BetterDisplay 中启用 Integration features
3. 在 MacAfk Pro 偏好设置中启用 BetterDisplay 集成

**Pro 版能力边界：**
- 需要 macOS 26.0+
- 未启用 App Sandbox（DisplayServices 与全局快捷键所需）
- 外接屏亮度依赖 BetterDisplay 安装、运行且 API 连通
- 开机自启动使用 `SMAppService`，UI 与系统实际状态同步

---

## 📄 许可证

本项目采用 MIT 许可证 - 详见 [LICENSE](LICENSE) 文件

---

## 🙏 致谢

- [MonitorControl](https://github.com/MonitorControl/MonitorControl) - 亮度控制实现参考
- [BetterDisplay](https://github.com/waydabber/BetterDisplay) - 外接屏亮度集成
- SwiftUI 社区 - 技术支持

---

<p align="center">
  <strong>⭐️ 如果这个项目对你有帮助，请给个 Star！</strong>
</p>

<p align="center">
  Made with ❤️ by Sn1waR
</p>
