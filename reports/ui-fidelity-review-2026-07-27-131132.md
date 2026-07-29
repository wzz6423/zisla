# 歌词延长模式 UI 核查

生成时间：2026-07-27 13:11:32

## 结论

无刘海屏的详细音乐延长条为 520pt。歌词区此前错误地占用右半区 260pt；现固定为右侧 160pt，剩余宽度保留为中部导航栏空白。歌词在状态条内垂直居中，字号为 13-14pt。

## 修改

- `mac/Sources/Zisla/SideNoticeView.swift`：限制歌曲信息和歌词两侧内容带最大宽度为 160pt，并将额外宽度留在中部。
- `mac/Sources/Zisla/SideNoticeView.swift`：歌词容器使用垂直居中对齐，歌词字体提升至 13-14pt。

## 验证

`swift test --package-path mac --filter SideNoticeLayoutTests`：22/22 通过。
