# Eave 设计文档

**Eave（屋檐）** 是一款原生 macOS 菜单栏管理与刘海（Notch）联动工具，最低支持 **macOS 15.0 (Sequoia)**，并针对 **macOS 26 (Tahoe)** 的 Liquid Glass 视觉语言与新菜单栏体系进行原生适配。

> 目标：在零第三方依赖、纯原生 Swift（AppKit + SwiftUI）的基础上，完整实现「菜单栏三区隐藏 + 刘海通知探头 + 刘海二级抽屉（Notch Bar）+ 快速检索 + 自研软件本地通知桥接」。

---

## 1. 产品定位与设计原则

1. **克制与专注**：不把刘海做成臃肿的万能桌面组件，所有刘海能力严格围绕「菜单栏延伸」与「被隐藏应用的状态触达」展开。
2. **渐进式权限**：
   - **零高危权限即可用（Phase 1）**：核心三区隐藏、点击/快捷键切换、自动收起、开机自启均不要求辅助功能或录屏权限。
   - **按需解锁高阶体验（Phase 2 & 3）**：授予辅助功能权限解锁 Dock 角标监听、滚动触发与 AX 点击转发；授予屏幕录制权限（可选）解锁 Notch Bar 中像素级实时菜单栏图标渲染（未授权时自动降级为应用图标，不阻塞使用）。
3. **主屏优先**：所有刘海交互默认锚定在内建物理刘海主屏（`safeAreaInsets.top > 0`），副屏保持绝对干净；合盖仅用外接屏时优雅降级为屏幕顶部居中悬浮胶囊（Floating Pill）。
4. **全自研生态友好**：内置 `NotchBridge` 本地协议，方便其他自研脚本、CLI、桌面工具直接向刘海推送状态与通知。
5. **零隐私泄露**：绝不在日志中输出通知正文、剪贴板、窗口内容或敏感信息。

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
│   ├── EaveApp.swift                  # SwiftUI App 入口 + Settings 场景
│   └── AppCoordinator.swift           # 全局依赖装配、生命周期与跨模块状态协调
├── Models/
│   ├── MenuBarModels.swift            # 分区、隐藏项、搜索项、间距配置模型
│   ├── NotchModels.swift              # 刘海几何、状态机、通知/微光信号模型
│   └── EaveSettings.swift             # UserDefaults 持久化的可观察配置中心
├── Core/
│   ├── MenuBar/
│   │   ├── MenuBarManager.swift       # Phase 1: 三段式分隔符控制与自动收起
│   │   ├── MenuBarEventMonitor.swift  # Phase 1: 菜单栏滚轮、悬停、外部点击监听
│   │   ├── MenuBarItemScanner.swift   # Phase 3: 窗口列表 + AX 双轨枚举菜单栏项
│   │   ├── MenuBarImageCapturer.swift # Phase 3: 按需 SCScreenshotManager 单帧采集
│   │   ├── MenuBarClickForwarder.swift# Phase 3: AXPress 优先 + CGEvent 兜底点击转发
│   │   └── MenuBarSpacingManager.swift# Phase 3: 系统 NSStatusItemSpacing 调节
│   ├── Notch/
│   │   ├── NotchGeometry.swift        # 主屏物理刘海坐标计算与无刘海降级
│   │   ├── NotchStateMachine.swift    # 统一四态流转：idle / ambient / peek / bar
│   │   └── NotchPanelController.swift # 非激活 NSPanel 管理、穿透控制与全屏避让
│   ├── Signals/
│   │   ├── DockBadgeMonitor.swift     # Phase 2: 监听隐藏/关注 App 的 Dock AXStatusLabel
│   │   ├── MenuBarAXWatcher.swift     # Phase 2: 监听纯菜单栏 App 的 AX 属性变更
│   │   ├── NotchBridge.swift          # Phase 2: DistributedNotification + URL Scheme 本地桥接
│   │   └── SignalHub.swift            # 信号去重、隐藏集合匹配、路由至刘海状态机
│   └── System/
│       ├── HotKeyManager.swift        # 原生 Carbon RegisterEventHotKey 全局快捷键
│       ├── LaunchAtLoginService.swift # 原生 SMAppService 开机自启
│       └── PermissionsManager.swift   # 辅助功能 / 录屏权限检测与系统设置直达
└── UI/
    ├── Notch/
    │   ├── NotchShape.swift           # 单一平滑形变刘海几何路径
    │   ├── NotchContainerView.swift   # 统一渲染 idle / ambient / peek / bar 四态
    │   ├── NotchPeekView.swift        # 刘海左右耳翼通知探头 + 悬停展开操作卡
    │   └── NotchBarView.swift         # Phase 3: 刘海下拉隐藏图标抽屉
    ├── Search/
    │   └── MenuBarSearchPanel.swift   # Phase 3: 快捷键呼出的菜单栏项模糊搜索浮窗
    └── Settings/
        ├── SettingsView.swift         # 标签式设置主界面（General / Notch / Shortcuts / Permissions / Bridge）
        └── HotKeyRecorderView.swift   # 原生 SwiftUI 快捷键录制控件
```

---

## 4. 三阶段功能规格

### Phase 1：基础菜单栏隐藏引擎
- **三区模型**：
  - `Toggle Anchor`（`eave.control.toggle`）：常显在最右侧控制位，左键展开/收起隐藏区，`⌥ + 左键` 展开/收起永久隐藏区，右键弹出快捷菜单。
  - `Hidden Separator`（`eave.control.hidden`）：分隔「常显区」与「隐藏区」。收起时 `length = 10_000` 将左侧图标挤出可视区；展开时 `length = 18` 显示极简竖点分隔符，方便 `⌘ + 拖拽` 整理图标。
  - `Always-Hidden Separator`（`eave.control.alwaysHidden`）：可选启用的二级分隔符，位于 Hidden Separator 左侧，日常展开隐藏区时仍保持收起。
- **触发与自动收起**：
  - 点击图标、菜单栏区域滚轮滚动、全局快捷键（默认 `⌥⌘H`）、可选悬停触发。
  - 支持倒计时自动收起（默认 8 秒，光标停留在菜单栏或刘海区域时自动暂停计时）与切走聚焦应用时自动收起。
- **系统集成**：原生 `SMAppService` 开机自启、持久化配置、纯菜单栏后台运行（`LSUIElement = true`）。

### Phase 2：刘海联动与隐藏 App 信号系统
- **四态统一状态机（`NotchStateMachine`）**：
  1. `.idle`：完全收拢在物理刘海内，窗口设置 `ignoresMouseEvents = true`，零遮挡、零误触。
  2. `.ambient([AmbientIndicator])`：当被隐藏的监控 App 处于活跃状态（存在未读或外部推送的常驻状态）时，刘海边缘透出极克制的微光圆点。
  3. `.peek(NotchAlert, isExpanded: Bool)`：被隐藏 App 出现新通知或红点数值上升时，刘海左右两翼平滑探出（左翼 App 图标/符号，右翼未读数/徽章）；默认展示 4.5 秒后缩回；鼠标悬停时平滑向下展开为操作卡片，点击直接激活目标 App 或执行跳转 URL。
  4. `.bar`：Phase 3 的刘海二级图标抽屉。
- **三路信号源（`SignalHub`）**：
  - **Dock 角标监听（`DockBadgeMonitor`）**：周期性通过 `AXUIElement` 扫描 `com.apple.dock` 的 `AXStatusLabel`，仅针对「当前被 Eave 隐藏的 App」或「用户手动加入监听白名单的 App」做增量 diff，角标首次出现或数值增加时触发 `.peek`，角标清除后同步移除 `.ambient` 微光。
  - **纯菜单栏 AX 监听（`MenuBarAXWatcher`）**：对后台运行但无 Dock 图标的隐藏菜单栏 App 检查 `AXExtrasMenuBar` 的 `AXTitle` / `AXDescription` / `AXValue` 变动，捕获 VPN、代理、定时器等状态变化。
  - **自研软件桥接（`NotchBridge`）**：
    - `DistributedNotificationCenter` 通知名：`com.abcdlsj.eave.notch.notify`
    - 自定义 URL Scheme：`eave://notify?...` 与 `eave://clear?id=...`
    - 支持参数：`id`, `title`, `subtitle`, `badge`, `symbol`, `accent`（十六进制颜色）, `bundleID`, `url`, `duration`, `mode`（`peek` / `ambient` / `clear`）。
    - 提供终端脚本 `scripts/eave-notify` 便于立即集成。

### Phase 3：Notch Bar 抽屉、快捷搜索与间距控制
- **双轨菜单栏项发现（`MenuBarItemScanner`）**：
  - 结合 `CGWindowListCopyWindowInfo`（Layer 25 窗口几何，按与分隔符 `x` 坐标的相对位置精确判定 `.visible` / `.hidden` / `.alwaysHidden`）与 `AXExtrasMenuBar` 遍历（兼容 macOS 26 统一场景下部分无法单独枚举的项）。
  - 自动将实时发现的隐藏区 `bundleIdentifier` 集合同步给 `SignalHub`，实现真正的“自动感知哪些 App 被隐藏”。
- **按需单帧图标采集（`MenuBarImageCapturer`）**：
  - 仅在展开 Notch Bar 时按需调用 `SCScreenshotManager.captureImage` 截取目标菜单栏项位图，绝不开启常驻 `SCStream`，避免右上角长期出现录屏指示点。
  - 未授予屏幕录制权限或系统禁止单窗口截图时，优雅回退为 `NSRunningApplication.icon` + 应用简称，保证可用性与观感。
- **点击事件转发（`MenuBarClickForwarder`）**：
  - 用户点击 Notch Bar 或快捷搜索中的某一项时：自动记录当前状态 → 若需展开则临时展开目标分区 → 优先尝试 `AXPress` 直接触发该菜单栏项 → 不支持时回退为精确 `CGEvent` 鼠标点击并瞬时复位光标。
- **菜单栏快速搜索（`MenuBarSearchPanel`）**：
  - 全局快捷键（默认 `⌥⌘K`）呼出居中的浮窗（macOS 26 使用 Liquid Glass，macOS 15 使用 `.ultraThinMaterial`），支持对所有常显/隐藏菜单栏项模糊检索，方向键选择、回车直接触发点击。
- **菜单栏图标间距调节（`MenuBarSpacingManager`）**：
  - 封装 `NSStatusItemSpacing` 与 `NSStatusItemSelectionPadding` 全局偏好写入与一键恢复默认。

---

## 5. 关键边界与技术约束

1. **沙盒配置**：关闭 App Sandbox（`com.apple.security.app-sandbox = false`），以支持辅助功能（`AXUIElement`）、菜单栏事件监听、全局偏好间距写入与跨应用交互。
2. **全屏空间处理**：当主屏菜单栏被全屏应用隐藏时，暂停 `.ambient` 微光并禁止意外弹出；主动触发快捷键仍可在全屏上方以 `.fullScreenAuxiliary` 展示。
3. **测试策略**：对纯逻辑与状态机（`NotchGeometry` 计算、`NotchStateMachine` 状态流转与超时、`SignalHub` 角标增量 diff、`NotchBridge` URL/Payload 解析、`MenuBarSearch` 模糊匹配与排序）编写完整单元测试，并通过 `xcodebuild test` 验证。
