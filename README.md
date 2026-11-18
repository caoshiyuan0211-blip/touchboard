# Touchboard

用 Mac 触控板打字的虚拟键盘。 / A virtual keyboard you type on with your Mac's trackpad.

- **五指下滑** 打开键盘，再次五指下滑关闭
- **一根手指** 在触控板上滑动，键盘上的红点跟着移动
- **抬起手指** 输入当前高亮的键
- 🌐 键切换到上一个输入法（例如 ABC ⇄ 拼音）
- 键盘有毛玻璃效果，大小和透明度可以在 Touchboard 窗口里调整

```
1 2 3 4 5 6 7 8 9 0 ⌫
 q w e r t y u i o p
  a s d f g h j k l return
    z x c v b n m , . ↑
🌐  [    space    ] ← ↓ →
```

## 安装 / Install

1. 从 [Releases](../../releases) 下载最新的 `Touchboard-版本号.pkg`。
2. 这个安装包没有 Apple 开发者签名，第一次打开会被系统拦住：
   - **右键点击** `.pkg` → **打开** → 再点 **打开**；
   - 如果没有“打开”按钮：先双击一次，然后去 **系统设置 › 隐私与安全性**，在下方点 **仍要打开**。
3. 安装完成后，在“应用程序”里打开 **touchboard**。第一次打开 app 时也可能需要同样的步骤。
4. 按提示在 **系统设置 › 隐私与安全性 › 辅助功能** 里打开 **touchboard**。没有这个权限，按键无法输入到其他 app。

> **English:** Download the `.pkg` from Releases. It isn't signed with an Apple Developer ID, so right-click → Open it (or use **System Settings › Privacy & Security › Open Anyway**). After installing, open **touchboard** from Applications and allow it under **Privacy & Security › Accessibility**.

## 使用 / Usage

1. 先点击你想输入文字的输入框。
2. 五指在触控板上向下滑，键盘出现在屏幕底部。
3. 一根手指滑到想要的键上，抬起手指就输入。
4. 抬起前再放下第三根手指，可以取消这次输入。
5. 再次五指下滑关闭键盘。

键盘打开时，触控板不会移动鼠标、点击或滚动。

**提示：** 如果系统设置里打开了“四指/五指”手势（调度中心、App Exposé 等），可能会和五指下滑冲突，可以在 **系统设置 › 触控板 › 更多手势** 里关掉。

## 卸载 / Uninstall

退出 Touchboard（菜单栏键盘图标 › Quit），然后删除 `/Applications/touchboard.app`。

## 从源码构建 / Build from source

需要 Xcode 16 和 macOS 14 或更高版本。打开 `touchboard.xcodeproj`，点击 Run。

### 技术说明 / Notes

- 为了在其他 app 在前台时也能读到触控板上的手指，Touchboard 使用了 Apple 的私有框架 `MultitouchSupport`，因此不能上架 Mac App Store。
- App Sandbox 已关闭，因为沙盒内的 app 不能向其他 app 发送按键。
- 🌐 键通过按下系统快捷键“选择上一个输入法”（默认 ⌃空格）来切换输入法。
