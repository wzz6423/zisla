# 歌词延长模式 UI 核查

生成时间：2026-07-27 12:57:52

## 结论

收起态音乐详细模式的歌词区域已固定到右上可视区；中部导航栏/刘海预留区不承载歌词。歌词字号随状态条高度保持在 11-12pt，常规高度下为 12pt。

## 修改

- `mac/Sources/Zisla/SideNoticeView.swift`：歌词容器由右对齐改为右上对齐。
- `mac/Sources/Zisla/SideNoticeView.swift`：歌词字体由 10pt 提升为随高度变化的 11-12pt。

## 验证

`swift test --package-path mac --filter SideNoticeLayoutTests`：22/22 通过。
