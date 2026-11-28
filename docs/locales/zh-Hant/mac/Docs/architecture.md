# 架構與性能設計

[English](../../../../../mac/Docs/architecture.md) | [简体中文](../../../../../mac/Docs/architecture.zh-CN.md) | **繁體中文** | [其他語言](../../../README.md)

## 頂部觸發

隱藏態沒有透明視窗。`PointerEdgeMonitor` 安裝一組全局和本地 `NSEvent` monitor，只處理 `mouseMoved` 與拖拽事件；`ScreenLayoutEngine` 用純幾何判斷指針是否進入每塊螢幕頂部中央 6 px 區域。

每塊螢幕通過 `NSScreenNumber` 對應的 `CGDirectDisplayID` 建立穩定身份。佈局始終以 `screen.frame.maxY` 為頂部錨點，支援負坐標、上下排列和無劉海外接屏。

連接多個顯示器時，在「設定 → 通用 → 顯示器模式」分別選擇靈動島模式（攝影機或自訂位置）、劉海模式，或在此螢幕不顯示。單螢幕時隱藏此設定，使用原有全域樣式；重新連接後恢復各螢幕的設定。啟用靈動島的螢幕會同時顯示收合的靈動島。在一個螢幕上展開靈動島、開啟快速操作、錄音或顯示暫時提示時，其他螢幕的靈動島仍然可見。選擇通知顯示器只決定哪個螢幕顯示通知。

## 視窗

主島只保留一個 `.borderless + .nonactivatingPanel`：

- `.statusBar` 層級，不覆蓋系統鎖屏和系統菜單。
- `.canJoinAllSpaces + .fullScreenAuxiliary` 支援 Space 與普通全屏。
- hover 展開不呼叫 `NSApp.activate`，不會搶走當前應用焦點。
- 隱藏使用 `orderOut`，菜單欄區域不被透明視窗吞掉。

左右通知面板按需創建，隊列為空立即隱藏。

## 狀態與併發

- AppKit、SwiftUI 狀態和視窗控制限制在 `MainActor`。
- Zisla 使用 `NSStatusItem` 控制自己的圖像。對於其他 App，Zisla 會讀取 `AXExtrasMenuBar`，並在儲存選擇前檢查選單列佈局。
- 下載、天氣和 GitHub 請求使用 actor。
- hook 寫入的 AI 狀態使用目錄檔案系統事件監聽；各 AI 會話源定期比較最近本地會話或活動檔案的 mtime/size，未變化時復用解析緩存。
- 自動檢測只讀取判斷任務狀態所需的結構化事件、固定狀態 marker 或活動元資料，不讀取 prompt/answer 正文；任一 Provider 解析失敗不會阻斷其他 Provider。
- AI 帳號額度來自供應商獨立取樣。Antigravity 的 Gemini 與 Claude/GPT 額度保留各自的重設視窗和低額度提醒。Gemini App 一般對話額度使用同一 Google 帳號儲存的網站 Cookie 查詢；Gemini CLI 保留本機 OAuth 來源。缺失額度不得估算。
- 折疊延遲使用可取消 `Task` 和 generation token，舊任務不能隱藏重新展開的島。
- 隱藏態沒有 `TimelineView`、60 Hz Timer 或持續動畫提交。

## 媒體檢測

MediaRemote 提供曲名、封面、進度和控制；Core Audio 14.4+ 的程序對象屬性負責確認應用是否存在活動輸出流，並在元資料缺失時提供來源應用兜底。程序列表和輸出狀態使用屬性監聽器並配合定期覆核，不採集音訊內容，也不請求螢幕錄制或輔助功能權限。暫停、停止和靜音來源不會保留在媒體區域。

## 螢幕錄影與應用混音

螢幕錄影和應用混音與媒體元資料檢測是獨立路徑。螢幕錄影請求螢幕錄制以及啓用的麥克風/相機權限，在本機儲存所選媒體，並在螢幕錄影目錄管理工程。應用混音在 macOS 14.4+ 使用 Core Audio tap，需要系統音訊錄制權限。

## 材質

macOS 26 使用單層 SwiftUI `glassEffect`；macOS 14/15 使用單層 `NSVisualEffectView`。系統開啓“降低透明度”後改用實體背景。島面不會疊加多層 blur/material。

## 下載安全邊界

Swift 使用 `Process.executableURL` 和參數數組啓動 `yt-dlp`，URL 永遠位於 `--` 後的獨立 argv。運行時禁用配置、插件和 exec，併發排空輸出管道，通過 JSON sentinel 解析進度。

只有退出碼為 0、完成路徑存在、解析符號連結後仍位於授權目錄內時任務才成功。每個任務只清理自己的 UUID 臨時目錄。

## 檢查和下載更新

當前選擇的更新通道會在本次運行中解析一次公網出口國家碼，再由 Sparkle 讀取該安裝包對應的已簽名 appcast，經 HTTPS 下載其中引用的 ZIP，並在解壓前驗證 EdDSA 歸檔與 feed 簽名，隨後替換並重啓應用。`CN` 先讀取 Gitee（Release 為 `update-release`，Preview 為 `preview`），再回退一次對應 GitHub feed；其他國家碼先讀取 GitHub，再回退一次 Gitee。無法獲取國家碼時保留 Gitee 優先；兩份 appcast 分別只引用本站已簽名的 ZIP。每次發佈在共享的 `appcast.xml` 旁再發佈每個架構各自的 appcast，單架構安裝只請求自己 slice 對應的那份（Rosetta 下的 x86_64 slice 按 `arm64` 請求），因此不會被 Universal 包替換；Universal 安裝按自身可執行檔案里的 slice 數判定，繼續請求 `appcast.xml`，這一份同時服務於按架構更新之前發佈的版本。切換設定同時影響自動和手動檢查，並重置 Sparkle 的下一次檢查週期。內置公鑰不含賬戶信息；私鑰僅儲存在維護者的 macOS 鑰匙串或受保護的私鑰檔案中。
