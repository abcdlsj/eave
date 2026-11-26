# Eave 设计文档

**Eave（屋檐）** 是一款原生 macOS 菜单栏管理与刘海（Notch）联动工具，最低支持 **macOS 15.0 (Sequoia)**，并针对 **macOS 26 (Tahoe)** 的 Liquid Glass 视觉语言与新菜单栏体系进行原生适配。

> 目标：在零第三方依赖、纯原生 Swift（AppKit + SwiftUI）的基础上，完整实现「菜单栏两区隐藏 + 悬停第二行悬浮栏（Second Row）+ 刘海通知探头与微光 + 快速检索 + 自研软件本地通知桥接」。

---

## 1. 产品定位与设计原则

1. **克制与专注**：不把刘海做成臃肿的万能桌面组件——刘海严格专注于「被隐藏应用的通知探头（Peek）与微光提醒（Ambient）」；隐藏图标交互归口给「点击原位展开 + 悬停第二行浮层 + 快捷键检索」。
2. **渐进式权限（零录屏权限）**：
   - **零权限即可用**：核心两区隐藏、点击/快捷键切换、自动收起、开机自启均不要求辅助功能或录屏权限。
   - **仅需单一辅助功能权限解锁高阶能力**：授予 Accessibility 解锁隐藏 App 自动发现、Dock 角标监听、纯菜单栏 AX 监听及菜单栏点击转发；全程使用原生高清 App 图标，彻底不申请屏幕录制权限。
3. **主屏优先，多屏悬停适配**：刘海通知默认锚定在内建物理刘海主屏（`safeAreaInsets.top > 0`），合盖外接屏时优雅降级为顶部悬浮胶囊；悬停第二行浮层支持全连接显示器跟随锚定。
4. **外观一致**：支持 System / Light / Dark 三态外观，设置页、第二行浮层与快捷搜索面板实时同步日夜间配色。
5. **全自研生态友好**：内置 `NotchBridge` 本地协议，方便其他自研脚本、CLI、桌面工具直接向刘海推送状态与通知。
6. **零隐私泄露**：绝不在日志中输出通知正文、剪贴板、窗口内容或敏感信息。

---

## 2. 视觉与图标规范

- **极简单图形语言**：以「屋檐 + 中央刘海凹口」抽象为单一连续几何剪影。
- **AppIcon**：深炭黑底色（`#111214`）叠加微妙顶缘高光，居中放置纯白单图形屋檐符号。
- **Menu Bar Icon**：纯单色 Template 图标，自动适配浅色/深色菜单栏与 macOS 26 透明菜单栏。
- 所有分辨率图标由 `scripts/generate-icons.swift` 通过 CoreGraphics 矢量路径直接生成，保持像素级锐利与可复现。

---

## 3. 系统架构与分层

遵循单向依赖原则：`App` -> `UI` / `Core` -> `Models`：

```text
Eave/
├── App/
│   ├── EaveApp.swift                  # SwiftUI App 入口 + LSUIElement 生命周期
│   └── AppCoordinator.swift           # 全局依赖装配、生命周期与跨模块状态协调
├── Models/
│   ├── MenuBarModels.swift            # 两区模型、鼠标按键模型、间距配置、快捷键模型
│   ├── NotchModels.swift              # 刘海几何、三态状态机、通知/微光信号模型
│   └── EaveSettings.swift             # UserDefaults 持久化的精简可观察配置中心
├── Core/
│   ├── MenuBar/
│   │   ├── MenuBarManager.swift       # 两区隐藏分隔符控制、瞬态转发扩张与自动收起
│   │   ├── MenuBarEventMonitor.swift  # 多屏 Eave 悬停监听与外部点击收起
│   │   ├── MenuBarItemScanner.swift   # WindowServer 代理窗口 + AX 双轨枚举菜单栏项
│   │   ├── MenuBarClickForwarder.swift# 常规 App 直接唤起 + 菜单栏工具左/右键转发
│   │   └── MenuBarSpacingManager.swift# 系统 NSStatusItemSpacing 调节
│   ├── Notch/
│   │   ├── NotchGeometryResolver.swift# 主屏物理刘海坐标计算与无刘海降级
│   │   ├── NotchStateMachine.swift    # 统一三态流转：idle / ambient / peek
│   │   └── NotchPanelController.swift # 非激活 NSPanel 管理、穿透控制与全屏避让
│   ├── Signals/
│   │   ├── DockBadgeMonitor.swift     # 监听隐藏/关注 App 的 Dock AXStatusLabel
│   │   ├── MenuBarAXWatcher.swift     # 监听纯菜单栏 App 的 AX 属性变更
│   │   ├── NotchBridge.swift          # DistributedNotification + URL Scheme 本地桥接
│   │   └── SignalHub.swift            # 信号去重、隐藏集合匹配、路由至刘海状态机
│   └── System/
│       ├── HotKeyManager.swift        # 原生 Carbon RegisterEventHotKey 全局快捷键
│       ├── LaunchAtLoginService.swift # 原生 SMAppService 开机自启
│       └── PermissionsManager.swift   # 辅助功能权限检测与系统设置直达
└── UI/
    ├── MenuBar/
    │   ├── SecondRowBarController.swift # 悬浮第二行面板生命周期、锚定与悬停桥接
    │   └── SecondRowBarView.swift       # 支持左/右键点击与 Dock 波浪放大的第二行视图
    ├── Notch/
    │   ├── NotchShape.swift             # 单一平滑形变刘海几何路径与 Liquid Glass 修饰器
    │   ├── NotchContainerView.swift     # 统一渲染 idle / ambient / peek 三态
    │   └── NotchPeekView.swift          # 刘海左右耳翼通知探头 + 悬停展开操作卡
    ├── Search/
    │   └── MenuBarSearchPanel.swift     # 快捷键呼出的菜单栏项模糊搜索浮窗
    ├── Shared/
    │   ├── EaveDesignSystem.swift       # 动效、触感、日夜间调色板与二级设置组件库
    │   └── AppIconService.swift         # 高清原生 App 图标解析与缓存
    └── Settings/
        ├── SettingsView.swift           # 精简三标签设置页（General / Notch / Shortcuts）
        └── HotKeyRecorderView.swift     # 原生 SwiftUI 快捷键录制控件
```

---

## 4. 核心功能规格

### 菜单栏两区隐藏与 Second Row 悬浮栏
- **两区模型**：
  - `Toggle Anchor`（`eave.control.toggle`）：常显在最右侧控制位，左键原位展开/收起隐藏区，右键弹出快捷菜单，悬停触发预览。
  - `Hidden Separator`（`eave.control.hidden`）：分隔「常显区」与「隐藏区」。收起时 `length = 10_000` 将左侧图标挤出可视区；展开时 `length = 10` 显示极简圆点分隔符，方便 `⌘ + 拖拽` 整理图标。
- **自动收起（三合一统一开关）**：开启后，原位展开的隐藏项在 8 秒无操作或切走聚焦应用时自动收起（指针停留在菜单栏或刘海区域时自动暂停计时）。
- **悬停第二行（Second Row）与智能点击分流**：
  - 支持在「原位展开」与「向下第二行浮层」间切换，并可调整悬停延迟、单行横滑/多行换行布局及每行图标数。
  - **常规带窗口 App（`activationPolicy == .regular`）**：在第二行左键点击时直接通过 `NSWorkspace.openApplication` 唤起/重建主窗口，**绝不撑开顶部菜单栏**；右键点击则转发右键至其菜单栏项。
  - **纯菜单栏工具（`activationPolicy == .accessory`，如 Tailscale / Clash 等）**：支持左键与右键完整透传；点击时短暂展开菜单栏使下拉菜单/Popover 正确锚定在右上角，优先执行 `AXPress` / `AXShowMenu` 并支持左/右键合成点击兜底，操作结束（点外部或切走应用）即刻收起。

### 刘海通知与桥接（Notch）
- **三态统一状态机（`NotchStateMachine`）**：
  1. `.idle`：完全收拢在物理刘海内，`ignoresMouseEvents = true`，零遮挡、零误触。
  2. `.ambient([AmbientIndicator])`：被隐藏的监控 App 存在未读或外部推送常驻状态时，刘海边缘透出极克制的微光圆点与数字。
  3. `.peek(NotchAlert, expanded: Bool)`：被隐藏 App 出现新通知或红点数值上升时，刘海左右两翼平滑探出；展示时长可调（默认 4.5s），悬停展开操作卡，点击直达目标 App 或 URL。
- **统一开关与三路信号源**：由单一「刘海通知」开关统一控制 Peek、微光与纯菜单栏 AX 监听；同时保留自动/手动监听白名单与折叠式 `NotchBridge` 本地协议（`eave://notify` / `eave://clear` 与 `com.abcdlsj.eave.notch.notify`）。

### 快捷搜索与间距控制
- **菜单栏快速搜索（`⌥⌘K`）**：全局模糊检索所有常显/隐藏菜单栏项，方向键选择、回车直接触发智能分流打开。
- **菜单栏间距调节**：收敛于 General 页折叠卡片中，封装 `NSStatusItemSpacing` 与 `NSStatusItemSelectionPadding` 写入与一键恢复默认。

---

## 5. 关键边界与技术约束

1. **沙盒配置**：关闭 App Sandbox（`com.apple.security.app-sandbox = false`），以支持辅助功能（`AXUIElement`）、菜单栏事件监听、全局偏好间距写入与跨应用交互。
2. **全屏空间处理**：当主屏菜单栏被全屏应用隐藏时避免意外遮挡；主动触发快捷键仍可在全屏上方以 `.fullScreenAuxiliary` 展示。
3. **测试策略**：对纯逻辑与状态机（`NotchGeometry`、`NotchStateMachine`、`DockBadgeDiffEngine`、`BridgePayload`、`MenuBarSearchEngine`、`MenuBarClickForwarder.resolveStrategy`、`SecondRowLayoutMetrics`、`EaveSettings` 持久化与外观映射）编写完整单元测试，并通过 `xcodebuild test` 验证。
