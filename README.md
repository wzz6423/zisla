# zisla

zisla 是面向桌面的跨平台动态工作空间。它把各平台实现放在独立目录中，让桌面宠物等后续能力可以共享产品方向，同时保留各平台原生交互与技术栈。

## 产品介绍

如果你的 Mac 有刘海屏，并且希望充分利用它；或者你会在后台运行多个 AI 工具，希望一眼掌握它们的进度，zisla 值得一试。没有刘海屏的 Mac 同样适用。

zisla 是一个使用 SwiftUI 和 AppKit 构建的原生 macOS 工作空间。它以事件驱动的方式感知刘海屏，在工作时保持克制，仅在有实用信息需要展示时展开，并遵循 macOS 在多显示器和 Spaces 下的交互习惯。

它集成了正在播放控制、文件中转与共享、安全的视频和音频下载、天气、日历、提醒事项、备忘录集成、可配置的桌面工具和系统实用功能。注重隐私的 AI 活动监视器能够识别受支持的本地 CLI 和桌面工具活动，展示任务进度与用量趋势，但不会读取提示词或回复内容；附带的 `zislactl` hook 也允许其他工具报告自身活动。

## 仓库结构

- `mac/`：当前的 macOS 实现，使用 Swift、AppKit 和 SwiftUI 构建。
- `windows/`：Windows 实现，使用 C++20、C++/WinRT、WinUI 3 和 Windows App SDK 构建。

## 系统兼容性

当前发布版本仅支持搭载 Apple 芯片且运行 macOS 14 或更高版本的 Mac。macOS 14 之前的系统和 Intel 芯片机型虽有对应的发布版本，但不保证可用性。

## macOS 开发

```bash
cd mac
swift run zisla
```

macOS Swift target、Bundle ID、本地数据目录和 `zislactl` 均使用 zisla 标识。升级时会自动迁移此前版本的本地数据和偏好设置。macOS 的功能、构建和测试说明见 [`mac/README.md`](mac/README.md)。

## Windows 开发

Windows 核心使用标准 CMake 构建：

```bash
cmake -S windows -B build/windows -DCMAKE_BUILD_TYPE=Debug
cmake --build build/windows --parallel
ctest --test-dir build/windows --output-on-failure
```
