import type { SiteContent } from '../content';

export const zhHant: SiteContent = {
  meta: {
    documentTitle: 'zisla · 動態工作空間',
    description:
      'zisla 是原生 macOS 動態工作空間，集中呈現 AI 任務與每日簡報，支援錄影剪輯、自訂寵物、截圖和集中權限管理。',
    ogTitle: 'zisla · 把正在發生的事放到你看得見的地方',
    ogDescription:
      '把 AI 任務和日常活動放到看得見的地方；在 Mac 上錄影剪輯、匯入寵物，並集中管理權限。',
  },
  tagline: '原生 macOS 動態工作空間',
  header: {
    navAriaLabel: '主要導覽',
    brandHomeAriaLabel: 'zisla 首頁',
    menuOpenLabel: '開啟導覽選單',
    menuCloseLabel: '關閉導覽',
    menuButtonTitle: '開啟導覽',
    navItems: {
      showcase: '功能',
      ai: 'AI 工作流程',
      download: '下載',
      changelog: '更新日誌',
      faq: 'FAQ',
      developers: '開發者',
    },
    downloadCta: '下載',
    downloadCtaAriaLabel: '跳至下載區塊',
    languageLabel: '介面語言',
    themeLabel: '外觀模式',
    themeModes: { auto: '自動（跟隨系統）', light: '日間模式', dark: '夜間模式' },
  },
  hero: {
    eyebrow: '原生 MACOS 工作空間',
    title:
      'zisla<br><em>把正在發生的事<br>放到你看得見的地方。</em>',
    lede: '把 AI 任務、媒體、檔案與行程收進螢幕頂端；複製後，獨立的快捷操作提示列會在螢幕上方預覽內容並給出下一步。需要時出現，完成後收起。',
    downloadCta: '下載',
    downloadCtaAriaLabel: '下載',
    sourceCta: '檢視原始碼',
    sourceCtaAriaLabel: '在 GitHub 上檢視 zisla 原始碼',
    hints: [
      '移到螢幕頂端即可展開，不必點擊',
      '複製後可用 Command+N 呼出智慧下一步',
      '自動收起，不干擾目前的工作',
    ],
  },
  proof: {
    ariaLabel: '產品概覽',
    items: {
      modules: { title: '{count} 個頂端模組', desc: '頂端工作流程隨需開啟' },
      os: { title: 'macOS 14+', desc: '原生桌面體驗' },
      displays: { title: '多螢幕', desc: '瀏海螢幕與外接螢幕都能使用' },
      local: { title: '本機優先', desc: 'AI 狀態不讀取對話內容' },
    },
  },
  showcase: {
    eyebrow: '同一入口 / 日常工作流程',
    title: '常用工作流程，<span>留在螢幕頂端。</span>',
    lede: '從 AI 任務到剪貼簿、行程與系統狀態，zisla 把分散的桌面工作流程收進同一個入口。',
    ariaLabel: 'zisla 功能目錄',
    summaryMono: '{modules} 個模組 / {groups} 類工作流程',
    summaryLede: '從頂端工作流程到本機工具，實際能完成的任務都在這裡逐項寫清楚。',
    summaryNote:
      '{modules} 個頂端模組 + {features} 項獨立能力，從視窗預覽、截圖與 AI 管理，到推薦應用程式。',
    groupNames: {
      island: '頂端工作流程',
      ai: 'AI 工作流程',
      daily: '日常資訊',
      tools: '實用工具',
    },
    groupCount: '{count} 個模組',
    pointsAriaLabel: '{name} 的功能重點',
    modules: {
      dashboard: {
        name: '首頁',
        caption: '只在有進行中的專注、AI 任務或下載時顯示動態卡片，沒有活動時不佔用額外空間。',
        points: ['隨需出現', '即時進度', '自動調整版面'],
      },
      shelf: {
        name: '中轉站',
        caption:
          '將檔案、影音或連結拖到螢幕頂端觸發帶，放入中轉站、在 Finder 中顯示，或呼出 macOS 系統分享選單。',
        points: ['拖到頂端即中轉', '在 Finder 中顯示', '系統分享選單'],
      },
      clipboard: {
        name: '剪貼簿',
        caption:
          '在靈動島內檢視剪貼簿歷史，依圖片、URL、路徑與檔案類型篩選，並顯示每筆記錄的複製時間；可將項目傳送到隨記、設為常用或刪除。',
        points: ['島內歷史記錄', '依類型篩選', '隨記與常用'],
      },
      aiMonitor: {
        name: 'AI 監控',
        caption:
          '自動辨識受支援的 AI CLI、桌面版與 IDE 活動，呈現任務、狀態、累計 Token 趨勢與貢獻熱度圖；只解析結構化事件，不讀取對話內容。新增 Cursor 任務偵測，以及 Cursor 和 Muse Code 數值用量與可取得的訂閱額度；Cursor 長時間工具執行期間仍保留任務狀態。',
        points: ['多工具任務彙總', 'Token 消耗趨勢', '不讀取提示詞與回覆'],
      },
      keyboardSound: {
        name: '鍵盤音效',
        caption:
          '為全域按鍵播放 20 種內建機械鍵盤音色，可調音量與自然音高變化，並為支援的音色播放回彈音；開啟本機輸入統計後，可在島內檢視今日概覽、輸入趨勢、歷史、應用程式時間軸，以及含 F1-F12 的逐鍵熱度圖。語音輸入總量、聽寫時間、速度和節省時間也集中在鍵盤資訊頁。新設定預設啟用音效與輸入統計，兩項可分別關閉。',
        points: ['20 種內建音色', '回彈音與音高變化', '輸入統計可單獨開關'],
      },
      download: {
        name: '下載器',
        caption:
          '貼上連結，或在開啟後從剪貼簿辨識連結；可選擇可用的影片或音訊格式，抖音下載需要時可使用已安裝瀏覽器的 Cookies。下載到預設或自選目錄時，顯示來源圖示、即時進度與完成狀態。',
        points: ['選擇可用的影片或音訊格式', '抖音瀏覽器 Cookies', '來源圖示與即時進度'],
      },
      agenda: {
        name: '行程與天氣',
        caption:
          '顯示目前位置與最多 6 個自選地點的天氣；檢視、新增與刪除行事曆事件及提醒事項，並可將提醒標示為完成。',
        points: ['多地天氣卡片', '行事曆與待辦管理', '提醒一鍵完成'],
      },
      mail: {
        name: '郵件',
        caption:
          '讀取已啟用的「郵件」帳號，在島內檢視收件匣、標示已讀、回覆、撰寫新郵件與移到垃圾桶；權限不足時提供明確的授權指引。撰寫郵件時可選擇檔案作為附件。',
        points: ['「郵件」帳號', '島內回覆與撰寫', '權限指引透明'],
      },
      quickNotes: {
        name: '隨記',
        caption:
          '以系統「備忘錄」為資料來源，支援檢視、編輯、新增與刪除筆記，以及 Markdown 即時預覽，並可用 Command+1 到 9 直接切換前九則筆記；草稿會自動寫回備忘錄。',
        points: ['資料來自備忘錄', 'Markdown 編輯器', '草稿自動寫回'],
      },
      volumeMixer: {
        name: '應用程式音量混音器',
        caption: '分別調整正在播放聲音的應用程式音量，或單獨靜音。需要 macOS 14.4 或以上版本，以及系統音訊錄製權限。',
        points: ['各應用程式獨立音量', '單獨靜音', 'macOS 14.4+'],
      },
      toolbox: {
        name: '小工具',
        caption:
          '將專注倒數、保持螢幕亮起、螢幕清潔、鍵盤清潔（清潔期間阻擋包含 F1-F12 的按鍵）、提詞機、鏡子與垃圾桶集中在同一頁。',
        points: ['專注倒數', '清潔時阻擋 F1-F12', '提詞機與鏡子'],
      },
      system: {
        name: '系統狀態',
        caption:
          '檢視 CPU、GPU、記憶體、磁碟、網路與風扇等狀態，在裝置支援時讀取 NVMe SMART 溫度，持續記錄分鐘級歷史，可依任意時間範圍繪製圖表並匯出 .xlsx。掃描應用程式快取、Apple 使用者快取、記錄檔與偏好設定殘留，複核後將所選項目移至垃圾桶，並查看處理結果。檢視本機電量、健康度、循環次數、溫度與容量等詳細指標，並彙總系統可讀取的附近裝置電量。公用 IPv4 與 IPv6 位址分開顯示。',
        points: ['晶片級監控', '歷史圖表與 .xlsx 匯出', '複核後移至垃圾桶'],
      },
    },
  },
  extensions: {
    eyebrow: '靈動島內外',
    title: '離開靈動島，<span>仍有桌面能力。</span>',
    lede: '截圖、語音、媒體、瀏覽器下載與 AI 管理，各自以最順手的方式出現。',
    ariaLabel: '獨立桌面能力',
    summaryMono: '靈動島之外',
    summaryLede: '常用能力，各在最順手的位置。',
    summaryNote: '視窗預覽、截圖與快捷操作各在最順手的位置，推薦應用程式幫你發現更多桌面工具。',
    features: {
      floatingIsland: {
        title: '浮島隨版面調整',
        description: '可使用攝影機位置，或在螢幕邊緣選擇自訂位置；切換模式後保留自訂位置。橫向與直向緊湊版面會按狀態圖示、AI 任務、下載和媒體調整長度，並可開啟更多資訊。',
        detail: '自訂位置 · 常駐狀態圖示 · 資訊自適應',
      },
      dailyBriefing: {
        title: '每日簡報',
        description: '從 8 種模板中選擇樣式，勾選使用時間、輸入、系統與 zisla 活動資料，並預覽版面。可手動或在設定時間匯出 PNG；開啟後按可用情況讀取系統螢幕使用時間歷史，不把缺失資料當作實測零值。',
        detail: '8 種模板 · 自選內容 · 預覽與定時 PNG 匯出',
      },
      userCare: {
        title: '工作中的關懷提醒',
        description: '設定休息、喝水、活動和護眼提醒間隔，提示會結合一天中的時段。自然休息、鎖定螢幕與睡眠後重設計時；專注完成和便箋操作也可在島內顯示簡短回饋。可在設定中開關。',
        detail: '自訂間隔 · 結合時段 · 尊重閒置與睡眠',
      },
      contextNotes: {
        title: '跟隨位置的便箋',
        description: '為網頁、應用程式視窗或桌面儲存可編輯便箋，回到對應位置時顯示。可附上應用程式視窗截圖，在中轉站管理，並設定每 1 小時至每 3 天的重複提醒，也可關閉提醒。',
        detail: '位置便箋 · 視窗截圖 · 重複提醒',
      },
      recording: {
        title: '錄影與剪輯工作室',
        description: '錄製顯示器、視窗或區域，可選系統音訊、麥克風和相機。在多軌時間軸上編輯影片、音訊、圖片與文字，加入動畫、縮放和字幕，查看清晰的即時預覽。畫幅支援原始、16:9、9:16、1:1 和 4:3；可匯出影片、GIF、Live Photo 和音訊，部分格式需要 FFmpeg。可選 AI 剪輯先預覽方案再套用。',
        detail: '多軌剪輯 · 畫幅與預覽 · 影片、GIF、Live Photo 與音訊',
      },
      permissions: {
        title: '集中管理系統權限',
        description: '在「設定 → 權限」查看授權狀態、發起支援的要求，或開啟對應系統設定頁。首次歡迎頁共用同一權限清單，並標明需要手動設定的權限。',
        detail: '授權狀態 · 要求與系統設定 · 歡迎頁共用',
      },
      pdf: {
        title: 'PDF 工具',
        description: '入口位於設定，不佔用靈動島模組輪播。在本機完成 PDF 合併、分割、旋轉、裁切、圖片/Office 轉換、轉為圖片、匯出文字、文字/圖片浮水印、頁碼、加密、移除密碼與中介資料編輯等 14 項操作。',
        detail: '14 種本機工具 · 依順序合併 · 全程不離開本機',
      },

      windowPreviews: {
        title: '視窗預覽，點按即切換',
        description:
          '從 Dock 或 Command-Tab 切換時預覽視窗，點擊卡片即可啟用對應視窗。新設定預設啟用，可在設定中調整功能與相關權限。',
        detail: 'Dock 與 Command-Tab · 點擊切換視窗 · 可在設定中調整',
      },
      capture: {
        title: '截圖、長截圖與釘圖',
        description:
          '使用可自訂的快捷鍵擷取、釘選或拼接長截圖。支援螢光標示、影像區域擷取、圓角和保留編輯中的標註；可辨識並複製文字、翻譯後複製結果，或辨識表格並匯出 .xlsx。截圖可暫存到中轉站，快捷鍵設定會檢查語音輸入和快捷操作衝突。',
        detail: '標示與擷取 · 辨識、翻譯並複製 · 圓角與 .xlsx',
      },
      voice: {
        title: '語音輸入與整理',
        description:
          '按鍵切換或按住說話，使用系統語音辨識，搭配領域詞庫和自訂熱詞。可選用 Ollama、LM Studio 等本機模型或遠端模型，在保留原意的基礎上修正錯誤，並依需要格式化明確列舉的事項。',
        detail: '兩種錄音方式 · 詞庫與自訂熱詞 · 可選模型整理',
      },
      media: {
        title: '媒體與系統背景聲',
        description:
          '在靈動島頂端控制正在播放的內容，也可選擇 macOS 系統背景聲；鎖定畫面、螢幕保護程式或螢幕睡眠時可自動關閉。可選擇音浪或封面光暈；緊湊與浮島版面也顯示播放進度。',
        detail: '播放控制 · 歌詞同步 · 自動停止背景聲',
      },
      browserDownloads: {
        title: '瀏覽器下載進度',
        description:
          '辨識 Safari、Chrome、Edge、Firefox、Brave、Vivaldi、Opera 與 Arc 的下載，在頂端顯示來源與即時進度。',
        detail: '8 種瀏覽器 · 來源辨識 · 完成提示',
      },
      copyAssistant: {
        title: '快捷操作與智慧下一步',
        description:
          '啟用後，複製文字、連結、檔案或圖片會在獨立的頂端提示列中預覽；可辨識連結、本機已安裝應用程式名稱和 Emoji 名稱，也可按即時匯率換算複製的金額，所有下一步均由你確認後執行。瀏覽器下載或 AirDrop 接收完成後，透過快捷操作開啟檔案所在的檔案夾。支援 Chrome 的預設與自選下載目錄，可獨立於下載進度顯示啟用。IP 位址提供獨立的查詢與開啟連結操作；貨幣換算支援本地最小貨幣單位，表情目錄更新至 Emoji 18.0。',
        detail: '本機辨識 · 即時匯率換算 · 預設 Command+N',
      },
      aiManagement: {
        title: 'AI CLI 與 Skills 管理',
        description:
          '在設定中偵測、安裝、更新與移除常用 AI CLI，並檢視和管理本機 Skills，減少在多個終端機與工具之間切換。',
        detail: '偵測與安裝 · 更新與移除 · 本機 Skills',
      },
      pet: {
        title: '靈動島寵物',
        description: '從擴充後的動物和角色目錄選擇寵物，或將系統支援的圖片、動畫圖片和影片匯入並命名。可放在島的任意一側，也可在設定中刪除自訂寵物。匯入動畫最長 30 秒，檔案最大 100 MB。',
        detail: '擴充寵物目錄 · 圖片與影片匯入 · 刪除自訂寵物',
      },
      lockScreen: {
        title: '鎖定畫面資訊',
        description:
          '隨需在 macOS 鎖定畫面顯示日期、狀態與正在播放的內容；它是獨立的鎖定畫面覆蓋層，不會出現在靈動島的模組列表或輪播中。',
        detail: '獨立鎖定畫面覆蓋層 · 隨需開啟 · 不搶焦點',
      },
      recommendedTools: {
        title: '推薦應用程式',
        description:
          '在推薦應用程式中發現 OpenScreen（螢幕錄製與影片編輯）和 DockDoor（Dock 視窗預覽與應用程式切換）等工具，皆為另行安裝的第三方應用程式。',
        detail: '探索桌面工具 · 第三方應用程式 · 另行安裝',
      },
    },
  },
  ai: {
    eyebrow: '沒有黑箱的 AI',
    title: '看見 AI 狀態，<span>不讀取對話。</span>',
    lede: '任務、狀態與 Token 趨勢留在本機；本頁只說明能力，不虛構執行中的任務畫面。',
    summaryMono: '本機狀態 / 明確邊界',
    summaryLede: '接上常用 AI 工具，同時保留目前工作需要的上下文邊界。',
    summaryNote: '本頁只說明偵測範圍、資料邊界與接入方式，不模擬正在執行的工作階段。',
    toolsHeading: '支援的 AI 工具',
    toolsLede: '自動辨識受支援的 CLI、桌面版與 IDE 活動，並彙總任務狀態。',
    toolsAriaLabel: '支援的 AI 工具',
    boundariesHeading: '只記錄狀態邊界',
    privacyPoints: [
      '只解析結構化事件中的事件類型、狀態、時間、模型與工作階段 ID',
      '不讀取提示詞或回覆內容',
      '協定與狀態都保存在本機',
    ],
    bridgeHeading: '接上你自己的任務',
    bridgeLede: '透過 zislactl 將外部任務的結構化狀態送進頂端狀態列。',
    zislactlTaskTitle: '打包發佈',
    copyZislactlAriaLabel: '複製 zislactl 指令',
  },
  flow: {
    eyebrow: '互動節奏',
    title: '移到頂端，<span>查看，然後收起。</span>',
    lede: '不搶焦點，看完自動收起。',
    ariaLabel: '頂端互動節奏',
    summaryMono: '頂端狀態列 / 3 步',
    summaryLede: '需要時展開，讀完後收回。',
    summaryNote: '由滑鼠位置觸發；沒有操作時不佔用視覺空間，也不會搶走目前應用程式的焦點。',
    steps: {
      trigger: {
        phase: '觸發',
        title: '移到螢幕頂端中央',
        desc: '瀏海螢幕與外接螢幕使用同樣的觸發方式；隱藏時不執行影格迴圈。',
      },
      review: {
        phase: '查看',
        title: '看一眼目前狀態',
        desc: '媒體、檔案、AI、行程與系統工具集中在同一個位置。',
      },
      dismiss: {
        phase: '收起',
        title: '繼續手上的工作',
        desc: '移開滑鼠後自動收起，展開時不會啟用或搶走目前應用程式的焦點。',
      },
    },
  },
  download: {
    eyebrow: '隨時可用',
    title: '下載 zisla',
    copy: '適用於 Apple 晶片 Mac；版本、其他架構與校驗資訊都在 Release 頁面。安裝後可依更新通道檢查新版本，Sparkle 會先驗證簽章，再依設定手動或自動下載、安裝並重新啟動，更新會保留已授予的權限；更新設定也提供直達 GitHub 問題回報的入口。若對某個版本不感興趣，可以跳過，zisla 不會再提醒。安裝更新前和重新啟動後均可查看更新說明。',
    primaryCta: '下載',
    primaryCtaAriaLabel: '下載',
    releaseCta: '查看 Release',
    releaseCtaAriaLabel: '在 GitHub 上查看發佈詳情',
    brewMono: 'HOMEBREW / 一行指令',
    brewNote: 'zisla 由 Sparkle 自行更新，因此 brew upgrade 只在已安裝的應用程式確實舊於 tap 中的版本時才替換它——Homebrew 5.1.6 起會讀取應用程式自身的版本號。明確指定 cask（brew upgrade --cask zisla）依據的是 Homebrew 自己的安裝記錄，在 Sparkle 更新過之後可能把應用程式退回 tap 的版本。tap 只提供正式版。該 tap 屬於第三方，應用程式也未經公證，首次打開需在「系統設定 → 隱私權與安全性」中選擇「仍要打開」。',
    copyBrewCommandAriaLabel: '複製 Homebrew 安裝指令',
    notes: {
      system: { term: '系統', value: 'macOS 14 或以上版本 · 目前受支援的組態為 Apple 晶片 Mac' },
      install: { term: '安裝', value: '掛載 DMG 後拖入「應用程式」' },
      package: { term: '檔案', value: 'Apple Silicon (arm64) · DMG' },
      architectures: { term: '其他架構', value: 'Release 頁面' },
      mirror: { term: '鏡像', value: 'Gitee Releases' },
    },
  },
  changelog: {
    releaseNotes: {
      'v0.1.20': [
        '每日簡報提供 8 種模板，可自選使用時間、輸入、系統與 zisla 活動內容，預覽並手動或定時匯出本機 PNG；系統螢幕使用時間歷史僅在開啟且可用時納入。',
        '上下文關懷支援自訂間隔、結合時段的提醒，以及專注和便箋操作回饋；閒置、鎖定螢幕與睡眠後重設計時。位置便箋可附應用程式視窗截圖，並設定每 1 小時至每 3 天的重複提醒。',
        '浮島支援記住自訂位置、橫向與直向緊湊版面自適應、常駐狀態圖示和更多資訊模式；媒體新增音浪與封面光暈樣式，各版面均可顯示播放進度。',
        '寵物目錄擴充動物和角色；支援匯入並命名圖片、動畫圖片和影片寵物，以及刪除自訂寵物。動畫最長 30 秒，來源檔案最大 100 MB。',
        '錄影工作室可錄製顯示器、視窗或區域，並選用系統音訊、麥克風和相機。多軌影片、音訊、圖片與文字編輯支援動畫、字幕、縮放、更清晰的預覽和 5 種畫幅，可匯出影片、GIF、Live Photo 與音訊；可選 AI 方案預覽後由你套用。',
        '截圖新增螢光標示、區域擷取和圓角；文字辨識可直接複製，或翻譯後複製，表格辨識可匯出 .xlsx。截圖與錄影可靠性得到修正，包括錄製音訊保留。',
        'AI 監控新增 Cursor 任務偵測，以及 Cursor 與 Muse Code 數值用量和可取得的訂閱額度；Cursor 長工具任務持續顯示。剪貼簿 IP 查詢與開啟連結分離，貨幣辨識支援最小單位，表情名稱更新至 Emoji 18.0。',
        '靈動島增加應用程式音量與靜音控制，PDF 工具移至設定，電池資訊併入系統狀態；權限集中至設定。新設定預設開啟鍵盤音效、輸入統計、視窗預覽與關懷，語音總量顯示在鍵盤資訊頁；郵件可選擇檔案作附件，更新安裝前和重新啟動後可查看說明。',
      ],
    },
    eyebrow: '更新日誌',
    title: '每個 zisla 版本的變化：新功能、改進與修正。',
    lede: '每個 zisla 版本的變化：新功能、改進與修正。',
    ariaLabel: 'zisla 發布記錄',
    releaseCountLabel: '個版本',
    latestLabel: '最新',
    shippedLabel: '已發布',
    latestBadge: '最新',
    noteLabel: '版本',
    pagerAriaLabel: '更新日誌分頁',
    pageLabel: '第 {page} 頁',
    prevPageLabel: '上一頁',
    nextPageLabel: '下一頁',
  },
  faq: {
    eyebrow: '幾個明確的答案',
    title: '常見問題。',
    lede: '權限、隱私與相容性說明。',
    items: {
      audience: {
        question: 'zisla 適合哪些使用者？',
        answer: '適合希望集中檢視 AI、媒體、檔案與行程的 Mac 使用者；沒有瀏海的螢幕也支援。',
      },
      aiPrivacy: {
        question: 'zisla 會讀取我的 AI 對話內容嗎？',
        answer: '不會。AI 狀態監控只讀取任務狀態，不讀取提示詞或回覆內容。',
      },
      copyAssistant: {
        question: '快捷操作會自動開啟或上傳我複製的內容嗎？',
        answer:
          '不會。啟用後，內容辨識與預覽都在本機完成；只有你點按動作或按下快速觸發後，zisla 才會執行對應的下一步。',
      },
      permissions: {
        question: 'zisla 需要哪些系統權限？',
        answer: '<p>「設定 → 權限」集中顯示系統權限狀態、授權要求和系統設定入口。部分權限需要手動設定；由你選擇發起哪些要求，首次歡迎頁也提供權限入口。</p><p>螢幕錄製、系統音訊錄製、麥克風和相機分別用於截圖、錄影、混音器、鏡像等對應功能；語音輸入還使用語音辨識。行事曆、提醒事項、定位、藍牙和自動化用於相關功能，手動新增天氣城市無需定位權限。</p><p>新設定預設啟用鍵盤音效和輸入統計，可分別關閉。全域鍵盤事件需要輸入監控；統計只儲存次數、鍵碼、時間和應用程式名稱，不儲存輸入正文。輔助使用用於文字插入、手勢、清潔與視窗控制。</p><p>讀取本機郵件索引和每日簡報使用的系統螢幕使用時間歷史可能需要完整磁碟存取權限。系統檔案選擇器授予的是所選資料夾的存取權限。可在 zisla 中關閉功能，或在「系統設定 → 隱私權與安全性」撤銷權限。</p>',
      },
      localVoice: {
        question: '如何用本機模型整理語音？',
        answer: `
      <p>支援 Ollama、LM Studio 及其他與 OpenAI 相容的本機服務。</p>
      <ol>
        <li>先在本機模型應用程式中下載或載入要使用的模型，並啟動服務。</li>
        <li>開啟「設定 → 語音 → 本機模型」，新增並啟用設定，選擇 Ollama 或 LM Studio，填入服務位址。其他與 OpenAI 相容的服務也選擇 LM Studio；未啟用驗證時，API Key 可留空。</li>
        <li>從自動偵測到的模型中選擇一個，再到「語音整理模型 → 使用模型」選擇該設定。</li>
      </ol>
      <p>zisla 會依晶片和整機記憶體提供 Gemma 4 QAT 建議；不會自動下載或載入建議的模型。</p>
    `.trim(),
      },
      network: {
        question: 'zisla 會連網嗎？',
        answer:
          '天氣、簽章更新檢查、主動下載與可選的遠端語音整理會依需要連網；剪貼簿連結偵測只在本機辨識，不會自行發起下載。本機模型負責轉寫後的文字整理；Apple 語音辨識仍可能連網，取決於語言和系統支援。',
      },
      multiDisplay: {
        question: 'zisla 支援多螢幕嗎？',
        answer: '支援多螢幕、Spaces 與一般全螢幕應用程式，展開時不搶焦點。',
      },
      intel: {
        question: 'Intel Mac 可以使用嗎？',
        answer:
          'Intel 機型可能有可用的發佈版本，但不保證相容性。目前受支援的組態為 Apple 晶片 Mac。',
      },
      storage: {
        question: 'zisla 的資料儲存在哪裡？',
        answer:
          '本機資料位於 ~/Library/Application Support/zisla/；鍵盤輸入統計單獨保存在 ~/Library/Application Support/zisla/typing-stats.sqlite3；隨記使用系統「備忘錄」。',
      },
    },
  },
  developers: {
    eyebrow: '預設開源',
    title: '開發者資源。',
    lede: 'PolyForm Noncommercial 1.0.0 授權，僅限非商業用途，可直接使用或從原始碼建置。',
    docs: {
      macos: { title: 'macOS 開發指南', description: '功能、建置、測試與系統限制' },
      architecture: { title: '架構與效能設計', description: '頂端觸發、視窗與效能設計' },
      cli: { title: 'CLI 接入設計', description: 'zislactl 指令與欄位' },
      releasing: { title: '簽章與發佈設計', description: '簽章、公證與發佈流程' },
      contributing: { title: '貢獻指南', description: '開發環境、分支、提交與 Pull Request 要求' },
    },
    quickStartMono: '快速開始 / 原始碼',
    quickStartHeading: '從原始碼執行，或接上你自己的任務。',
    copyRunCommandAriaLabel: '複製原始碼執行指令',
    githubRepoLabel: 'GitHub 儲存庫',
    giteeRepoLabel: 'Gitee 儲存庫',
    checksumLabel: 'SHA-256',
    performancePoints: [
      '支援多螢幕、Spaces 與一般全螢幕應用程式；展開時不會啟用或搶走目前應用程式的焦點',
      '隱藏時不建立常駐透明熱區視窗，也不執行影格迴圈；透過全域事件監聽與幾何判斷觸發展開',
      '使用單層系統材質；系統開啟「降低透明度」後會自動改用實體背景',
      'macOS 26+ 使用 Liquid Glass；macOS 14/15 自動回退為系統原生材質',
      '實體瀏海透過系統安全區域推斷；沒有瀏海的外接螢幕使用自有覆蓋層模擬狀態列',
    ],
  },
  footer: {
    brandHomeAriaLabel: '回到 zisla 首頁',
    previewChannelLabel: 'Preview 通道',
    tagline: '開源、原生，把控制權留在你手裡。',
  },
  common: {
    copyCommandTitle: '複製指令',
    copiedAriaLabel: '已複製',
  },
  toast: {
    runCommandCopied: '原始碼執行指令已複製',
    zislactlCopied: 'zislactl 指令已複製',
    brewCommandCopied: 'Homebrew 安裝指令已複製',
  },
};
