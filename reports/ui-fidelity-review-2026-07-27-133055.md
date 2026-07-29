# 歌词与首页 UI 核查

生成时间：2026-07-27 13:30:55

## 结论

超长歌词不再落入尾部省略号分支：在宽度测量完成前直接裁剪，确认超长后从左向右连续循环。首页无活动信息时恢复标准岛高度，下缘不会被面板裁剪。

## 修改

- `mac/Sources/Zisla/MarqueeText.swift`：增加可选的向右循环方向与静态溢出裁剪。
- `mac/Sources/Zisla/SideNoticeView.swift`：歌词使用向右循环和无省略号裁剪。
- `mac/Sources/Zisla/AppModel.swift`：为空首页恢复标准岛高度下限。

## 验证

`swift test --package-path mac --filter SideNoticeLayoutTests`：22/22 通过。
