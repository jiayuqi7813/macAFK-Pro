# MacAfk Pro - macOS Anti-Sleep Tool

![image](./assets/image.png)

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS-blue" alt="Platform">
  <img src="https://img.shields.io/badge/swift-5.0-orange" alt="Swift">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
</p>

<p align="center">
  <a href="README.md">English</a> | <a href="README_CN.md">中文</a>
</p>

> Most enterprise macOS computers are managed via MDM, which prevents users from modifying screen lock settings. Additionally, many people now delegate tasks to LLM Agents and then... take a break. However, screen lock can cause AI agent tasks to fail, which is why this tool was developed.

> You can safely run it, and it will prevent the system from entering sleep mode through subtle (imperceptible) mouse movements.

---

## ✨ Key Features

### 🖱️ Anti-Sleep Functionality
- **Automatic Mouse Jiggling** - Prevents system from entering sleep mode
- **Adjustable Intervals** - 6 levels from 10 seconds to 10 minutes
- **Imperceptible Operation** - 1-pixel movement, completely unobtrusive

### 🌙 Smart Brightness Control (Pro)
- **Built-in Display** - Real hardware brightness control via DisplayServices API
- **External Displays** - Brightness control via [BetterDisplay](https://github.com/waydabber/BetterDisplay) Integration API
- **Low Brightness Mode** - Automatically lowers brightness while jiggling is active
- **Error Feedback** - Surfaces mapping and control failures in the UI

### ⌨️ Powerful Shortcut System
- **Global Shortcuts** - Quick control even when running in background
- **Fully Customizable** - Visual editor with conflict detection
- **Auto Save** - Persistent configuration, retained after restart

### 🎨 Modern Interface
- **SwiftUI Built** - Native macOS experience
- **Menu Bar Integration** - Lightweight, doesn't occupy Dock space
- **Preferences Window** - Display, general, language, and update settings

---

## 🚀 Quick Start

### Download & Install

Download from GitHub Releases:

```bash
https://github.com/jiayuqi7813/macAFK-Pro/releases
```

### First Run

1. **Grant Accessibility Permission**
   - Open "System Settings" → "Privacy & Security" → "Accessibility"
   - Add MacAfk Pro and enable it

2. **Launch Application**
   - Click the menu bar icon
   - Or use shortcut `⌘ ⌃ S`

3. **Start Using**
   - Enable anti-sleep: Click button or press `⌘ ⌃ S`
   - Enable low brightness: Toggle switch or press `⌘ ⌃ B`

---

## ⌨️ Default Shortcuts

| Shortcut | Function |
|----------|----------|
| `⌘ ⌃ S` | Toggle anti-sleep |
| `⌘ ⌃ B` | Toggle low brightness mode |
| `⌘ ⌃ ↑` | Increase jiggle interval |
| `⌘ ⌃ ↓` | Decrease jiggle interval |

**Custom Shortcuts**: Click "Customize All Shortcuts" button in the main interface

---

## 🔧 Build from Source

### Requirements
- macOS 26.0+
- Xcode 15.0+
- Swift 5.0+

### Build Steps

```bash
cd MacAfk
xcodebuild -scheme MacAfk -configuration Debug build
xcodebuild -scheme MacAfk -configuration Release build
```

### Run Tests

```bash
xcodebuild -scheme MacAfk -destination 'platform=macOS' test
```

---

## 📖 Use Cases

### Case 1: AI Agent Auto-Suspend
```
Problem: Enterprise policy auto-locks after 5 minutes, AI agent tasks fail due to screen lock network issues
Solution: Press ⌘ ⌃ S to enable anti-sleep, set longer interval (5-10 minutes)
```

### Case 2: Download/Processing Tasks ⏬
```
Problem: Long-running tasks but don't want screen always on
Solution: ⌘ ⌃ S + ⌘ ⌃ B (Low brightness mode saves power)
```

### Case 3: Remote Work 💻
```
Problem: Need to maintain connection but temporarily away
Solution: ⌘ ⌃ S to keep active, avoid disconnection
```

---

## 🛠️ Technical Architecture

```
MacAfk
├── AppModel.swift              # Application state management
├── BrightnessControl.swift     # DisplayServices + BetterDisplay brightness
├── BetterDisplayManager.swift  # BetterDisplay Integration API client
├── Jiggler.swift               # Mouse jiggling engine
├── ShortcutManager.swift       # Shortcut management system
├── ShortcutEditorView.swift    # Shortcut editor
├── ContentView.swift           # Main interface
├── NewPreferencesView.swift    # Preferences interface
└── AppDelegate.swift           # Menu bar integration
```

---

## 🤝 Contributing

Contributions, issues, and feature requests are welcome!

### Development Workflow
1. Fork the repository
2. Create a feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

---

## ❓ FAQ

### Q: "File is damaged" error when installing from GitHub Release?
A: This is a macOS Gatekeeper security feature. Since the app is not notarized, remove the quarantine attribute:

```bash
xattr -cr /Applications/MacAfk\ Pro.app/
```

Then try opening the app again, or right-click and select "Open".

### Q: Shortcuts not working?
A: Grant MacAfk Pro permission in "System Settings" → "Privacy & Security" → "Accessibility".

### Q: Does it support external displays?
A: Yes. MacAfk Pro controls built-in displays natively and external displays via BetterDisplay.

**Technical Approach:**
- **Built-in Display**: DisplayServices API (native hardware control)
- **External Displays**: [BetterDisplay](https://github.com/waydabber/BetterDisplay) Integration API

**Prerequisites for external displays:**
1. Install [BetterDisplay](https://github.com/waydabber/BetterDisplay) (free version works)
2. Enable "Integration features" in BetterDisplay settings
3. Enable BetterDisplay integration in MacAfk Pro preferences

**Pro capability boundaries:**
- Requires macOS 26.0+
- No App Sandbox (needed for DisplayServices and global shortcuts)
- External display brightness depends on BetterDisplay being installed, running, and connected
- Launch at login uses `SMAppService` and reflects the actual system state

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details

---

## 🙏 Acknowledgments

- [MonitorControl](https://github.com/MonitorControl/MonitorControl) - Brightness control implementation reference
- [BetterDisplay](https://github.com/waydabber/BetterDisplay) - External display brightness integration
- SwiftUI Community - Technical support

---

<p align="center">
  <strong>⭐️ If this project helps you, please give it a Star!</strong>
</p>

<p align="center">
  Made with ❤️ by Sn1waR
</p>
