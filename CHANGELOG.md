# Changelog

所有重要的项目更改都将记录在此文件中。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/)，
版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [Unreleased]

## [1.0.3] - 2025-11-25

### Added
- 🖥️ **BetterDisplay 集成支持** - 外接显示器亮度控制
  - 基于 BetterDisplay Integration API 实现外接显示器控制
  - 内置显示器继续使用 DisplayServices API（原生硬件控制）
  - 多显示器环境下自动检测和映射
  - 新增 BetterDisplay 环境检测弹窗
  - 详细的安装、运行、连接状态检查
  - 智能引导用户解决配置问题
- 📝 **更新的 README** - 添加多显示器支持的详细说明
  - 技术方案说明（DisplayServices + BetterDisplay）
  - BetterDisplay 使用前提条件
  - Integration API 文档链接

### Changed
- 🎯 **重构亮度控制逻辑** - 简化流程，提升可靠性
  - 采用顺序执行：获取亮度 → 保存 → 设置目标亮度
  - 移除复杂的超时和错误处理机制
  - 所有 BetterDisplay API 调用改为异步回调模式
- 🖱️ **优化设置页面交互**
  - 左侧设置列表整行可点击（之前只能点图标）
  - 添加 `.contentShape(Rectangle())` 改善点击体验
  - 调整列表项间距，提升视觉舒适度

### Fixed
- 🐛 **修复多显示器亮度控制问题**
  - 解决外接显示器未被识别的问题
  - 增加详细的调试日志输出
  - 同步建立显示器 UUID 映射
  - 确保所有显示器都被正确处理

### Technical
- 新增 `BetterDisplayManager.cacheBrightnessByUUID` 方法
- 新增 `BetterDisplayManager.setBrightnessByUUID` 异步版本
- 新增 `BetterDisplayManager.restoreCachedBrightnessByUUID` 方法
- 新增 `updateDisplayMappingSync` 同步映射方法
- 优化显示器检测和日志输出

## [1.0.2] - 2024-11-XX

### Added
- 多架构构建支持（ARM64 和 x86_64）
- Universal Binary（通用二进制）版本
- GitHub Actions CI/CD 自动化工作流
- 多语言支持（中文/英文）
- 语言设置界面
- 抖动间隔持久化保存
- 优化的构建脚本

### Changed
- 窗口默认尺寸调整为 400x700
- 间隔显示格式（使用 "s" 和 "min"）

### Fixed
- 语言管理器缺少 Combine 导入问题
- 应用重启后抖动间隔重置问题

## [1.0.0] - 2024-11-XX

### Added
- 初始版本发布
- 鼠标抖动防休眠功能
- 低亮度模式
- 自定义快捷键支持
- Pro 版本（真实硬件亮度控制）
- Lite 版本（Gamma 软件调光，App Store 兼容）
- 状态栏菜单集成
- 可调节的抖动间隔（10秒 - 10分钟）

### Security
- 无网络请求
- 本地数据存储
- 开源代码可审计

---

## 版本说明

### 版本说明
- ✅ 真实硬件亮度控制（DisplayServices API）
- ✅ 更好的省电效果
- ✅ 无沙盒限制
- ✅ 直接从 GitHub 下载
- ✅ 开源透明

---

[Unreleased]: https://github.com/jiayuqi7813/macAFK/compare/v1.0.3...HEAD
[1.0.3]: https://github.com/jiayuqi7813/macAFK/releases/tag/v1.0.3
[1.0.2]: https://github.com/jiayuqi7813/macAFK/releases/tag/v1.0.2
[1.0.0]: https://github.com/jiayuqi7813/macAFK/releases/tag/v1.0.0

