# GitHub Actions 工作流说明

## 📋 工作流概览

本项目包含两个 GitHub Actions 工作流：

### 1. `build.yml` - 持续集成 (CI)
**触发条件**：
- 推送到 `main` 或 `develop` 分支
- Pull Request 到 `main` 分支
- 手动触发

**功能**：
- 构建所有版本（Pro/Lite × ARM64/x86_64）
- 运行单元测试
- 上传构建产物（保留 7 天）
- CI 构建不使用 Apple Developer ID 签名

### 2. `release.yml` - 自动发布
**触发条件**：
- 推送版本标签（如 `v1.0.0`）
- 手动触发（可指定版本号）

**功能**：
- 构建 Pro 版本：
  - ARM64、x86_64、Universal
- 创建 DMG 安装包
- 如果配置了 Apple Developer ID secrets，使用 Developer ID 签名 `.app` 和 `.dmg`
- 如果同时配置 Apple 公证 secrets，提交 notarization 并 staple DMG
- 生成 SHA-256 校验和
- 自动创建 GitHub Release
- 上传所有构建产物

## 🚀 使用指南

### 自动构建和测试

每次推送代码到 `main` 或 `develop` 分支时，会自动运行构建和测试：

```bash
git add .
git commit -m "feat: 添加新功能"
git push origin main
```

### 发布新版本

#### 方法 1：使用 Git 标签（推荐）

```bash
# 1. 确保代码已提交
git add .
git commit -m "chore: 准备发布 v1.2.0"

# 2. 创建并推送标签
git tag -a v1.2.0 -m "Release v1.2.0"
git push origin v1.2.0
```

推送标签后，GitHub Actions 会自动：
1. 构建所有版本
2. 创建 Release
3. 上传 DMG 文件和校验和

#### 方法 2：手动触发

1. 访问 GitHub 仓库的 "Actions" 页面
2. 选择 "Release" 工作流
3. 点击 "Run workflow"
4. 输入版本号（如 `v1.2.0`）
5. 点击 "Run workflow"

### 查看构建状态

1. 访问仓库的 "Actions" 页面
2. 查看最新的工作流运行状态
3. 点击具体的运行查看详细日志

## 📦 构建产物

### CI 构建（build.yml）
- 保留时间：7 天
- 位置：Actions 页面 → 具体运行 → Artifacts
- `.app` artifact 不做 Apple Developer ID 正式签名

### Release 构建（release.yml）
- 保留时间：90 天
- 位置：
  - GitHub Release 页面（公开下载）
  - Actions Artifacts（备份）
- 只有 Release 工作流会尝试使用 Apple Developer ID secrets 签名和公证

## 🔐 安全说明

### 代码签名

当前只有 `release.yml` 会使用 Apple Developer ID secrets。`build.yml` 的普通 CI 构建会保持未正式签名，避免把非发布产物当成可分发版本。

Release 工作流支持两种模式：

1. 未配置 Apple Developer ID secrets 时：使用 ad-hoc 签名，保证 entitlements 尽量生效，但不会通过 Gatekeeper 正式校验。
2. 配置 Apple Developer ID secrets 后：导入证书到临时 keychain，使用 Developer ID 签名 `.app` 和 `.dmg`。如果同时配置 notary secrets，会提交 Apple 公证并 staple DMG。

需要配置的 GitHub Actions Secrets：

- `MACOS_CERTIFICATE_BASE64`：Developer ID Application `.p12` 证书的 base64 内容
- `MACOS_CERTIFICATE_PASSWORD`：导出 `.p12` 时设置的密码
- `MACOS_KEYCHAIN_PASSWORD`：CI 临时 keychain 密码，可自定义一个随机长密码
- `MACOS_SIGNING_IDENTITY`：证书身份，例如 `Developer ID Application: Your Name (TEAMID)`

可选公证 Secrets：

- `APPLE_NOTARY_APPLE_ID`：Apple Developer 账号邮箱
- `APPLE_NOTARY_PASSWORD`：App-specific password 或 notarytool 可用密码
- `APPLE_NOTARY_TEAM_ID`：Apple Developer Team ID

建议 Release 发布时同时配置签名和公证 secrets。只配置签名 secrets 时，Release 会带你的 Developer ID 签名，但没有 Apple 公证票据，用户下载后仍可能遇到 Gatekeeper 提示。

生成证书 secret 示例：

```bash
base64 -i DeveloperIDApplication.p12 | pbcopy
```

本地验证签名示例：

```bash
codesign -dvvv --entitlements :- /Applications/MacAfk\ Pro.app
spctl -a -vv /Applications/MacAfk\ Pro.app
```

### Secrets 配置

如需配置 Secrets：
1. 访问仓库 Settings → Secrets and variables → Actions
2. 添加需要的 Secrets
3. 在工作流中使用：`${{ secrets.SECRET_NAME }}`

## 🛠️ 本地构建

如果需要在本地运行构建脚本：

```bash
# 构建所有版本
./build.sh

# 指定版本号
VERSION=v1.2.0 ./build.sh
```

构建产物位置：
- `Build/` - 构建的 .app 文件
- `Archives/` - Xcode archives
- `Dist/` - 最终的 DMG 文件和校验和

## 📝 版本号规范

建议使用 [语义化版本](https://semver.org/lang/zh-CN/)：

- `v1.0.0` - 主版本.次版本.修订号
- `v1.0.0-beta.1` - 预发布版本
- `v1.0.0-rc.1` - 候选发布版本

## 🐛 故障排除

### 构建失败

1. 检查 Xcode 版本是否兼容
2. 确保所有依赖已正确配置
3. 查看详细的构建日志

### 发布失败

1. 确保标签格式正确（`v*.*.*`）
2. 检查 GitHub Token 权限
3. 验证 ExportOptions.plist 配置

### 权限问题

确保 GitHub Actions 有足够权限：
1. 仓库 Settings → Actions → General
2. 启用 "Read and write permissions"
3. 允许 "Allow GitHub Actions to create and approve pull requests"

## 📞 获取帮助

如遇到问题，请：
1. 查看 Actions 运行日志
2. 搜索类似的 GitHub Issues
3. 创建新 Issue 并附上错误信息
