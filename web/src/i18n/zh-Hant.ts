import type { SiteContent } from '../content';

export const zhHant: SiteContent = {
  meta: {
    documentTitle: 'zisla · 動態工作空間',
    description:
      'zisla：專為 macOS 打造的原生動態工作空間。集中檢視 Zed Agent 等 AI 任務、媒體、檔案與行程，並使用鍵盤音效、輸入統計、截圖標註與複製助理。',
    ogTitle: 'zisla · 把正在發生的事放到你看得見的地方',
    ogDescription:
      '從 Zed Agent 等 AI 任務與媒體，到鍵盤音效、輸入統計、複製助理、截圖標註與桌面工具，一個隨需出現的原生 macOS 工作空間。',
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
      faq: 'FAQ',
      developers: '開發者',
    },
    downloadCta: '下載',
    downloadCtaAriaLabel: '跳至下載區塊',
    languageLabel: '介面語言',
  },
  hero: {
    eyebrow: '原生 MACOS 工作空間',
    title:
      'zisla<br><em>把正在發生的事<br>放到你看得<br class="hero-mobile-break">見的地方。</em>',
    lede: '把 AI 任務、媒體、檔案與行程收進螢幕頂端；複製後，獨立的助理提示列會在螢幕上方預覽內容並給出下一步。需要時出現，完成後收起。',
    downloadCta: '下載',
    downloadCtaAriaLabel: '下載',
    sourceCta: '檢視原始碼',
    sourceCtaAriaLabel: '在 GitHub 上檢視 zisla 原始碼',
    hints: [
      '移到螢幕頂端即可展開，不必點擊',
      '複製後可用 Command+N 呼出智慧下一步',
      '自動收起，不干擾目前的工作',
    ],
    identityCaption: '螢幕頂端',
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
      '{modules} 個頂端模組 + {features} 項獨立能力，涵蓋截圖、語音、媒體、下載、複製助理、AI 管理、寵物與鎖定畫面。',
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
          '在靈動島內檢視剪貼簿歷史，並依圖片、URL、路徑與檔案類型篩選；可將項目傳送到隨記、設為常用或刪除。',
        points: ['島內歷史記錄', '依類型篩選', '隨記與常用'],
      },
      aiMonitor: {
        name: 'AI 監控',
        caption:
          '自動辨識受支援的 AI CLI、桌面版與 IDE 活動，包含 Zed Agent 執行緒，呈現任務、狀態、累計 Token 趨勢與貢獻熱度圖；只解析結構化事件，不讀取對話內容。',
        points: ['多工具任務彙總', 'Token 消耗趨勢', '不讀取提示詞與回覆'],
      },
      keyboardSound: {
        name: '鍵盤音效',
        caption:
          '為全域按鍵播放 20 種內建機械鍵盤音色，可調音量與自然音高變化，並為支援的音色播放回彈音；開啟本機輸入統計後，可在島內檢視今日概覽、輸入趨勢、歷史、應用程式時間軸，以及含 F1-F12 的逐鍵熱度圖。',
        points: ['20 種內建音色', '回彈音與音高變化', '輸入統計可選開啟'],
      },
      download: {
        name: '下載器',
        caption:
          '貼上連結，或在開啟後從剪貼簿辨識連結；選擇影片或音訊下載到預設或自選目錄。支援常見影片平台與其他受支援連結，下載時顯示來源圖示、即時進度與完成狀態。',
        points: ['影片 / 音訊模式', '預設或自選目錄', '來源圖示與即時進度'],
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
          '讀取已啟用的「郵件」帳號，在島內檢視收件匣、標示已讀、回覆、撰寫新郵件與移到垃圾桶；權限不足時提供明確的授權指引。',
        points: ['「郵件」帳號', '島內回覆與撰寫', '權限指引透明'],
      },
      quickNotes: {
        name: '隨記',
        caption:
          '以系統「備忘錄」為資料來源，支援檢視、編輯、新增與刪除筆記，以及 Markdown 即時預覽；草稿會自動寫回備忘錄。',
        points: ['資料來自備忘錄', 'Markdown 編輯器', '草稿自動寫回'],
      },
      pdf: {
        name: 'PDF 工具',
        caption:
          '在本機完成 PDF 合併、分割、旋轉、裁切、圖片/Office 轉換、轉為圖片、匯出文字、文字/圖片浮水印、頁碼、加密、移除密碼與中介資料編輯等 14 項操作。',
        points: ['14 種本機工具', '依順序合併', '全程不離開本機'],
      },
      toolbox: {
        name: '小工具',
        caption:
          '將專注倒數、保持螢幕亮起、螢幕清潔、鍵盤清潔（清潔期間阻擋包含 F1-F12 的按鍵）、鬧鐘、提詞機、鏡子與垃圾桶集中在同一頁。',
        points: ['專注倒數', '清潔時阻擋 F1-F12', '提詞機與鏡子'],
      },
      system: {
        name: '系統狀態',
        caption:
          '檢視 CPU、GPU、記憶體、磁碟、網路與風扇等狀態，在裝置支援時讀取 NVMe SMART 溫度，並清理可安全刪除的快取與記錄檔。',
        points: ['晶片級監控', 'NVMe 溫度（裝置支援時）', '一鍵清理快取'],
      },
      battery: {
        name: '電池',
        caption:
          '檢視本機電量、健康度、循環次數、溫度與容量等詳細指標，並彙總系統可讀取的附近裝置電量。',
        points: ['本機健康指標', '剩餘時間', '附近裝置電量'],
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
    summaryNote: '截圖、錄音、媒體、瀏覽器下載、複製助理、AI 管理、寵物與鎖定畫面各自獨立呈現。',
    features: {
      capture: {
        title: '截圖、長截圖與釘圖',
        description:
          '用全域快速鍵擷取或釘住螢幕內容，接著標註、拼接長截圖，並辨識或匯出表格；匯出前會保留正在編輯的文字標註。',
        detail: '全域快速鍵 · 標註與復原 · 編輯內容隨匯出保存',
      },
      voice: {
        title: '語音輸入與整理',
        description:
          '按鍵切換或按住說話，使用系統語音辨識，再依需要啟用領域詞庫、自訂熱詞、結構化格式或本機 / 遠端模型整理。',
        detail: '兩種錄音方式 · 詞庫與自訂熱詞 · 可選模型整理',
      },
      media: {
        title: '媒體與系統背景聲',
        description:
          '在靈動島頂端控制正在播放的內容，也可選擇 macOS 系統背景聲；鎖定畫面、螢幕保護程式或螢幕睡眠時可自動關閉。',
        detail: '播放控制 · 歌詞同步 · 自動停止背景聲',
      },
      browserDownloads: {
        title: '瀏覽器下載進度',
        description:
          '辨識 Safari、Chrome、Edge、Firefox、Brave、Vivaldi、Opera 與 Arc 的下載，在頂端顯示來源與即時進度。',
        detail: '8 種瀏覽器 · 來源辨識 · 完成提示',
      },
      copyAssistant: {
        title: '複製助理與智慧下一步',
        description:
          '啟用後，複製文字、連結、檔案或圖片會在獨立的頂端提示列中預覽，並依內容給出開啟、在 Finder 中顯示、搜尋、翻譯、計算或儲存等下一步，由你確認後執行。',
        detail: '可選開關 · 本機辨識 · 預設 Command+N',
      },
      aiManagement: {
        title: 'AI CLI 與 Skills 管理',
        description:
          '在設定中偵測、安裝、更新與移除常用 AI CLI，並檢視和管理本機 Skills，減少在多個終端機與工具之間切換。',
        detail: '偵測與安裝 · 更新與移除 · 本機 Skills',
      },
      pet: {
        title: '靈動島寵物',
        description: '選擇內建的寵物形象，把它放在靈動島的左側或右側；不需要時可隨時關閉。',
        detail: '內建形象 · 左右位置 · 隨需開啟',
      },
      lockScreen: {
        title: '鎖定畫面資訊',
        description:
          '隨需在 macOS 鎖定畫面顯示日期、狀態與正在播放的內容；它是獨立的鎖定畫面覆蓋層，不會出現在靈動島的模組列表或輪播中。',
        detail: '獨立鎖定畫面覆蓋層 · 隨需開啟 · 不搶焦點',
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
    doubaoName: '豆包',
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
    copy: '適用於 Apple 晶片 Mac；版本、其他架構與校驗資訊都在 Release 頁面。安裝後可依更新通道檢查新版本，Sparkle 會先驗證簽章，再依設定手動或自動下載、安裝並重新啟動。',
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
        question: '複製助理會自動開啟或上傳我複製的內容嗎？',
        answer:
          '不會。啟用後，內容辨識與預覽都在本機完成；只有你點按動作或按下快速觸發後，zisla 才會執行對應的下一步。',
      },
      permissions: {
        question: 'zisla 需要哪些系統權限？',
        answer: `
      <p>zisla 不會在首次啟動時一次索取所有權限。只有你開啟並實際使用下列功能時，macOS 才會顯示對應授權：</p>
      <ul>
        <li><strong>行事曆與提醒事項：</strong>開啟行程模組時分別請求，用於讀取、建立與管理行事曆事件和帶日期的提醒事項。</li>
        <li><strong>定位服務：</strong>選擇「使用目前位置」的天氣時請求；只取得一次目前位置，不會持續追蹤。手動新增城市不需要定位權限。</li>
        <li><strong>麥克風與語音辨識：</strong>點按開始語音輸入時請求；只在主動錄音期間收音，只處理該次錄音的轉寫。</li>
        <li><strong>輔助使用：</strong>自動將語音轉寫填入目前應用程式、滑鼠手勢快速複製、鍵盤清潔，以及控制部分受支援播放器時需要；用於定位非密碼輸入欄位或送出必要的系統按鍵。</li>
        <li><strong>輸入監控：</strong>鍵盤音效、可選的本機輸入統計，以及使用單獨變更鍵或滑鼠側鍵等全域觸發方式時才會使用；僅監聽完成這些功能所需的全域事件，一般全域快速鍵不需要這項授權。</li>
        <li><strong>螢幕錄製與系統音訊錄製：</strong>截圖、截圖編輯與顯示系統播放音訊波形時需要。截圖會讀取螢幕影像；音訊波形只分析目前系統音訊能量，不會保存或上傳音訊內容。</li>
        <li><strong>相機：</strong>只在開啟鏡子視窗期間使用。</li>
        <li><strong>藍牙：</strong>只在開啟電池模組時讀取已連線或已配對裝置公開的電量資訊。</li>
        <li><strong>自動化：</strong>首次使用隨記、郵件、桌面整理或直接控制受支援播放器時，macOS 會分別詢問是否允許 zisla 控制「備忘錄」「郵件」「Finder」或相應的應用程式。隨記可讀寫備忘錄；郵件可讀取、撰寫、回覆、標示與刪除郵件。</li>
        <li><strong>完全取用磁碟：</strong>只在「郵件」未執行時仍要讀取本機郵件索引，以顯示帳號、寄件人、主旨、摘要、時間與已讀狀態時需要。</li>
        <li><strong>通知：</strong>啟用番茄鐘或鬧鐘提醒時請求，只用於在計時結束或鬧鐘觸發時顯示本機通知。</li>
      </ul>
      <p><strong>檔案與下載目錄不等於完全取用磁碟：</strong>你透過系統檔案選擇器選取的中轉、匯入匯出或下載目錄，zisla 只取得該目錄的存取權，不會取得整顆磁碟的讀取權限。</p>
      <p><strong>鍵盤音效與輸入統計：</strong>兩項功能都預設關閉，任一項開啟後才會監聽全域鍵盤事件；開啟鍵盤音效後只處理按鍵事件以播放聲音，開啟輸入統計後只保存字元數、實體鍵碼、時間與前景應用程式等彙總資料，不保存輸入內容。你可以在設定中分別關閉，關閉後不再記錄；已保存的彙總資料留在本機資料庫檔案中，可自行刪除。</p>
      <p>你可以在應用程式設定中關閉對應功能，或隨時在「系統設定 → 隱私權與安全性」中撤銷授權。撤銷其中一項只會停用相關功能，不會影響其他模組；不同 macOS 版本的項目名稱可能略有不同。</p>
    `.trim(),
      },
      network: {
        question: 'zisla 會連網嗎？',
        answer:
          '天氣、簽章更新檢查、主動下載與可選的遠端語音整理會依需要連網；剪貼簿連結偵測只在本機辨識，不會自行發起下載。',
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
          '本機資料位於 ~/Library/Application Support/zisla/；鍵盤輸入統計單獨保存在 ~/Library/Application Support/SimuBoard/typing-stats.sqlite3；隨記使用系統「備忘錄」。',
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
