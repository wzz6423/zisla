import type { SiteContent } from '../content';

export const ko: SiteContent = {
  meta: {
    documentTitle: 'zisla · 다이내믹 워크스페이스',
    description:
      'zisla는 macOS를 위한 네이티브 다이내믹 워크스페이스입니다. Zed Agent 같은 AI 작업과 미디어, 파일, 일정을 한곳에서 확인하고 키보드 사운드, 입력 통계, 스크린샷 주석, 복사 도우미를 사용할 수 있습니다.',
    ogTitle: 'zisla · 지금 일어나는 일을 보이는 곳에',
    ogDescription:
      'Zed Agent 같은 AI 작업과 미디어 재생부터 키보드 사운드, 입력 통계, 복사 도우미, 스크린샷 주석, 데스크탑 도구까지. 필요할 때만 나타나는 네이티브 macOS 워크스페이스.',
  },
  tagline: '네이티브 macOS 다이내믹 워크스페이스',
  header: {
    navAriaLabel: '주요 내비게이션',
    brandHomeAriaLabel: 'zisla 홈',
    menuOpenLabel: '내비게이션 메뉴 열기',
    menuCloseLabel: '내비게이션 닫기',
    menuButtonTitle: '내비게이션 열기',
    navItems: {
      showcase: '기능',
      ai: 'AI 워크플로',
      download: '다운로드',
      faq: 'FAQ',
      developers: '개발자',
    },
    downloadCta: '다운로드',
    downloadCtaAriaLabel: '다운로드 섹션으로 이동',
    languageLabel: '표시 언어',
  },
  hero: {
    eyebrow: '네이티브 MACOS 워크스페이스',
    title: 'zisla<br><em>지금 일어나는 일을<br>보이는 곳에.</em>',
    lede: 'AI 작업과 미디어, 파일, 일정을 화면 위쪽에 모아 둡니다. 무언가를 복사하면 별도의 도우미 바가 화면 위에서 내용을 미리 보여 주고 다음에 할 일을 제안합니다. 필요할 때 나타나고, 끝나면 물러납니다.',
    downloadCta: '다운로드',
    downloadCtaAriaLabel: '다운로드',
    sourceCta: '소스 보기',
    sourceCtaAriaLabel: 'GitHub에서 zisla 소스 코드 보기',
    hints: [
      '클릭 없이 화면 위쪽으로 옮기면 펼쳐집니다',
      '복사한 뒤 Command+N으로 다음 단계를 바로 실행',
      '알아서 접히므로 작업을 방해하지 않습니다',
    ],
    identityCaption: '화면 위쪽',
  },
  proof: {
    ariaLabel: '제품 개요',
    items: {
      modules: { title: '상단 모듈 {count}개', desc: '필요한 워크플로만 켜기' },
      os: { title: 'macOS 14+', desc: '네이티브 데스크탑 경험' },
      displays: { title: '다중 디스플레이', desc: '노치 화면과 외부 화면 모두 지원' },
      local: { title: '로컬 우선', desc: 'AI 상태는 대화 내용을 읽지 않습니다' },
    },
  },
  showcase: {
    eyebrow: '하나의 입구 / 일상 워크플로',
    title: '자주 쓰는 워크플로를 <span>화면 위쪽에 그대로.</span>',
    lede: 'AI 작업부터 클립보드, 일정, 시스템 상태까지. zisla는 흩어져 있던 데스크탑 워크플로를 하나의 입구로 모읍니다.',
    ariaLabel: 'zisla 기능 목록',
    summaryMono: '모듈 {modules}개 / 분류 {groups}개',
    summaryLede: '상단 워크플로부터 로컬 도구까지, 실제로 할 수 있는 일을 하나씩 적었습니다.',
    summaryNote:
      '상단 모듈 {modules}개와 독립 기능 {features}개. 스크린샷, 음성, 미디어, 다운로드, 복사 도우미, AI 관리, 펫, 잠금 화면을 포함합니다.',
    groupNames: {
      island: '상단 워크플로',
      ai: 'AI 워크플로',
      daily: '일상 정보',
      tools: '유용한 도구',
    },
    groupCount: '모듈 {count}개',
    pointsAriaLabel: '{name} 주요 특징',
    modules: {
      dashboard: {
        name: '홈',
        caption:
          '진행 중인 집중 타이머, AI 작업, 다운로드가 있을 때만 카드를 표시하므로 아무 일도 없을 때는 자리를 차지하지 않습니다.',
        points: ['필요할 때만 표시', '실시간 진행률', '레이아웃 자동 조정'],
      },
      shelf: {
        name: '보관함',
        caption:
          '파일, 오디오·비디오, 링크를 화면 위쪽 트리거 영역으로 끌어다 보관함에 담고, Finder에서 보거나 macOS 공유 메뉴를 열 수 있습니다.',
        points: ['위쪽으로 끌어 임시 보관', 'Finder에서 보기', '시스템 공유 메뉴'],
      },
      clipboard: {
        name: '클립보드',
        caption:
          '다이내믹 아일랜드 안에서 클립보드 기록을 보고 이미지, URL, 경로, 파일 종류로 걸러 볼 수 있습니다. 항목은 빠른 메모로 보내거나 자주 쓰는 항목으로 지정하거나 삭제할 수 있습니다.',
        points: ['아일랜드 안의 기록', '종류별 필터', '빠른 메모와 즐겨찾기'],
      },
      aiMonitor: {
        name: 'AI 모니터링',
        caption:
          '지원되는 AI CLI, 데스크탑 앱, IDE의 활동을 Zed Agent 스레드까지 포함해 자동으로 인식하고 작업, 상태, 누적 토큰 추이, 기여 히트맵을 보여 줍니다. 구조화된 이벤트만 해석하며 대화 내용은 읽지 않습니다.',
        points: ['여러 도구의 작업 통합', '토큰 사용 추이', '프롬프트와 응답은 읽지 않음'],
      },
      keyboardSound: {
        name: '키보드 사운드',
        caption:
          '전역 키 입력에 맞춰 내장 기계식 키보드 음색 20종을 재생합니다. 음량과 자연스러운 음높이 변화를 조절할 수 있고, 지원하는 음색에서는 릴리스 음도 들려줍니다. 로컬 입력 통계를 켜면 오늘 요약, 입력 추이, 기록, 앱별 타임라인, F1~F12를 포함한 키별 히트맵을 아일랜드 안에서 볼 수 있습니다.',
        points: ['내장 음색 20종', '릴리스 음과 음높이 변화', '입력 통계는 선택 사항'],
      },
      download: {
        name: '다운로더',
        caption:
          '링크를 붙여넣거나, 기능을 켠 뒤 클립보드에서 링크를 인식하게 할 수 있습니다. 비디오 또는 오디오를 선택해 기본 폴더나 원하는 폴더로 저장합니다. 주요 비디오 플랫폼과 그 밖에 지원되는 링크는 출처 아이콘, 실시간 진행률, 완료 상태를 함께 보여 줍니다.',
        points: ['비디오 / 오디오 모드', '기본 또는 지정 폴더', '출처 아이콘과 실시간 진행률'],
      },
      agenda: {
        name: '일정과 날씨',
        caption:
          '현재 위치와 직접 고른 최대 6개 지역의 날씨를 보여 줍니다. 캘린더 이벤트와 미리 알림을 보고 추가·삭제할 수 있으며, 미리 알림은 완료로 표시할 수 있습니다.',
        points: ['여러 지역 날씨 카드', '캘린더와 할 일 관리', '미리 알림 바로 완료'],
      },
      mail: {
        name: '메일',
        caption:
          '"메일"에서 활성화한 계정을 읽어 아일랜드 안에서 받은 편지함 확인, 읽음 표시, 답장, 새 메일 작성, 휴지통으로 이동을 처리합니다. 권한이 부족하면 필요한 설정을 분명히 안내합니다.',
        points: ['"메일" 계정', '아일랜드 안에서 답장과 작성', '투명한 권한 안내'],
      },
      quickNotes: {
        name: '빠른 메모',
        caption:
          '시스템 "메모"를 데이터 원본으로 사용해 메모 보기, 편집, 새로 만들기, 삭제와 Markdown 실시간 미리보기를 지원합니다. 초안은 "메모"에 자동으로 다시 저장됩니다.',
        points: ['데이터는 "메모"에', 'Markdown 편집기', '초안 자동 저장'],
      },
      pdf: {
        name: 'PDF 도구',
        caption:
          'PDF 병합, 분할, 회전, 자르기, 이미지·Office 변환, 이미지로 변환, 텍스트 내보내기, 텍스트·이미지 워터마크, 페이지 번호, 암호화, 암호 해제, 메타데이터 편집 등 14가지 작업을 모두 이 Mac에서 처리합니다.',
        points: ['로컬 도구 14종', '원하는 순서로 병합', 'Mac 밖으로 나가지 않음'],
      },
      toolbox: {
        name: '작은 도구',
        caption:
          '집중 타이머, 화면 켜 두기, 화면 청소, 키보드 청소(청소 중에는 F1~F12를 포함한 키 입력을 막습니다), 알람, 프롬프터, 거울, 휴지통을 한 페이지에 모았습니다.',
        points: ['집중 타이머', '청소 중 F1~F12 차단', '프롬프터와 거울'],
      },
      system: {
        name: '시스템 상태',
        caption:
          'CPU, GPU, 메모리, 디스크, 네트워크, 팬 등의 상태를 확인하고, 기기가 지원하면 NVMe SMART 온도를 읽고, 안전하게 지울 수 있는 캐시와 로그를 정리합니다.',
        points: ['칩 단위 모니터링', 'NVMe 온도(지원 기기)', '캐시 한 번에 정리'],
      },
      battery: {
        name: '배터리',
        caption:
          '이 Mac의 잔량, 상태, 사이클 수, 온도, 용량 같은 세부 지표를 확인하고 시스템이 읽을 수 있는 주변 기기 잔량도 함께 모아 보여 줍니다.',
        points: ['본체 상태 지표', '남은 시간', '주변 기기 잔량'],
      },
    },
  },
  extensions: {
    eyebrow: '아일랜드 안과 밖',
    title: '아일랜드를 벗어나도 <span>데스크탑에서 일합니다.</span>',
    lede: '스크린샷, 음성, 미디어, 브라우저 다운로드, AI 관리가 각각 가장 편한 자리에 나타납니다.',
    ariaLabel: '독립 데스크탑 기능',
    summaryMono: '아일랜드 바깥',
    summaryLede: '자주 쓰는 기능을 각자 가장 자연스러운 자리에.',
    summaryNote:
      '스크린샷, 녹음, 미디어, 브라우저 다운로드, 복사 도우미, AI 관리, 펫, 잠금 화면이 각각 독립적으로 동작합니다.',
    features: {
      capture: {
        title: '스크린샷, 스크롤 캡처, 화면 고정',
        description:
          '전역 단축키로 화면을 캡처하거나 고정한 뒤 주석을 달고, 스크롤 캡처를 이어 붙이고, 표를 인식하거나 내보낼 수 있습니다. 편집 중인 텍스트 주석도 내보낼 때 그대로 유지됩니다.',
        detail: '전역 단축키 · 주석과 실행 취소 · 편집 내용 그대로 내보내기',
      },
      voice: {
        title: '음성 입력과 정리',
        description:
          '키로 전환하거나 누른 채 말하는 방식을 골라 시스템 음성 인식을 사용합니다. 필요하면 분야별 사전, 사용자 핫워드, 구조화된 형식, 로컬 또는 원격 모델 정리를 켤 수 있습니다.',
        detail: '두 가지 녹음 방식 · 사전과 핫워드 · 모델 정리는 선택',
      },
      media: {
        title: '미디어와 시스템 배경 사운드',
        description:
          '아일랜드 위쪽에서 재생 중인 항목을 제어하고 macOS 시스템 배경 사운드를 고를 수 있습니다. 화면 잠금, 화면 보호기, 디스플레이 잠자기에 맞춰 자동으로 멈출 수 있습니다.',
        detail: '재생 제어 · 가사 동기화 · 배경 사운드 자동 정지',
      },
      browserDownloads: {
        title: '브라우저 다운로드 진행률',
        description:
          'Safari, Chrome, Edge, Firefox, Brave, Vivaldi, Opera, Arc의 다운로드를 인식해 출처와 실시간 진행률을 화면 위쪽에 표시합니다.',
        detail: '브라우저 8종 · 출처 인식 · 완료 알림',
      },
      copyAssistant: {
        title: '복사 도우미와 다음 단계 제안',
        description:
          '켜 두면 복사한 텍스트, 링크, 파일, 이미지가 별도의 상단 바에서 미리 보이고, 내용에 맞춰 열기, Finder에서 보기, 검색, 번역, 계산, 저장 같은 다음 단계를 제안합니다. 실행은 확인한 뒤에 이루어집니다.',
        detail: '선택 기능 · 로컬 인식 · 기본 Command+N',
      },
      aiManagement: {
        title: 'AI CLI와 Skills 관리',
        description:
          '설정에서 많이 쓰는 AI CLI를 감지, 설치, 업데이트, 삭제하고 로컬 Skills를 확인·관리할 수 있어 여러 터미널과 도구를 오갈 일이 줄어듭니다.',
        detail: '감지와 설치 · 업데이트와 삭제 · 로컬 Skills',
      },
      pet: {
        title: '아일랜드 펫',
        description:
          '내장된 펫을 골라 아일랜드의 왼쪽이나 오른쪽에 둘 수 있고, 필요 없으면 언제든 끌 수 있습니다.',
        detail: '내장 캐릭터 · 좌우 위치 · 원할 때만',
      },
      lockScreen: {
        title: '잠금 화면 정보',
        description:
          '필요할 때 macOS 잠금 화면에 날짜, 상태, 재생 중인 항목을 표시합니다. 독립된 잠금 화면 오버레이이므로 아일랜드의 모듈 목록이나 캐러셀에는 나타나지 않습니다.',
        detail: '독립 오버레이 · 선택해서 켜기 · 포커스를 가져가지 않음',
      },
    },
  },
  ai: {
    eyebrow: '블랙박스 없는 AI',
    title: 'AI 상태는 보여 주고, <span>대화는 읽지 않습니다.</span>',
    lede: '작업, 상태, 토큰 추이는 이 Mac에 남습니다. 이 페이지는 기능을 설명할 뿐이며 실행 중인 작업 화면을 꾸며 내지 않습니다.',
    summaryMono: '로컬 상태 / 분명한 경계',
    summaryLede: '자주 쓰는 AI 도구와 연결하면서도 지금 작업에 필요한 맥락의 경계는 지킵니다.',
    summaryNote:
      '이 페이지는 인식 범위, 데이터 경계, 연결 방법만 설명하며 실행 중인 세션을 재현하지 않습니다.',
    toolsHeading: '지원하는 AI 도구',
    toolsLede: '지원되는 CLI, 데스크탑 앱, IDE의 활동을 인식하고 작업 상태를 모아 줍니다.',
    toolsAriaLabel: '지원하는 AI 도구',
    doubaoName: '더우바오(Doubao)',
    boundariesHeading: '상태의 경계만 기록합니다',
    privacyPoints: [
      '구조화된 이벤트에서 이벤트 종류, 상태, 시간, 모델, 세션 ID만 해석',
      '프롬프트나 응답 본문은 읽지 않음',
      '프로토콜과 상태는 이 Mac에 저장',
    ],
    bridgeHeading: '내 작업 연결하기',
    bridgeLede: 'zislactl로 외부 작업의 구조화된 상태를 상단 상태 바로 보냅니다.',
    zislactlTaskTitle: '빌드와 배포',
    copyZislactlAriaLabel: 'zislactl 명령 복사',
  },
  flow: {
    eyebrow: '상호작용 리듬',
    title: '위로 옮기고, <span>확인하고, 접습니다.</span>',
    lede: '포커스를 가져가지 않고, 확인이 끝나면 알아서 접힙니다.',
    ariaLabel: '상단 상호작용 리듬',
    summaryMono: '상태 바 / 3단계',
    summaryLede: '필요할 때 펼쳐지고, 다 읽으면 돌아갑니다.',
    summaryNote:
      '포인터 위치로 열립니다. 보여 줄 것이 없으면 화면을 차지하지 않고, 쓰고 있는 앱에서 포커스를 가져가지도 않습니다.',
    steps: {
      trigger: {
        phase: '트리거',
        title: '화면 위쪽 가운데로 옮기기',
        desc: '노치 화면과 외부 화면 모두 같은 방식이며, 숨어 있는 동안에는 프레임 루프가 돌지 않습니다.',
      },
      review: {
        phase: '확인',
        title: '지금 상태를 한눈에 보기',
        desc: '미디어, 파일, AI, 일정, 시스템 도구가 모두 같은 자리에 있습니다.',
      },
      dismiss: {
        phase: '접기',
        title: '하던 일로 돌아가기',
        desc: '포인터를 옮기면 자동으로 접히고, 펼쳐질 때 앱을 활성화하거나 포커스를 가져가지 않습니다.',
      },
    },
  },
  download: {
    eyebrow: '언제든 사용',
    title: 'zisla 다운로드',
    copy: 'Apple 실리콘 Mac용입니다. 버전, 다른 아키텍처, 체크섬은 릴리스 페이지에 있습니다. 설치한 뒤에는 선택한 업데이트 채널에서 새 버전을 확인할 수 있으며, Sparkle이 서명을 먼저 검증한 다음 설정에 따라 수동 또는 자동으로 다운로드·설치하고 다시 시작합니다.',
    primaryCta: '다운로드',
    primaryCtaAriaLabel: '다운로드',
    releaseCta: '릴리스 보기',
    releaseCtaAriaLabel: 'GitHub에서 릴리스 상세 보기',
    brewMono: 'HOMEBREW / 명령 한 줄',
    brewNote: 'zisla는 Sparkle이 직접 업데이트하므로 일반 brew upgrade로는 앱이 교체되지 않습니다. Homebrew가 교체하도록 하려면 brew upgrade --cask zisla를 실행하세요. tap은 정식 버전만 제공합니다.',
    copyBrewCommandAriaLabel: 'Homebrew 설치 명령 복사',
    notes: {
      system: {
        term: '시스템',
        value: 'macOS 14 이상 · 현재 지원 구성은 Apple 실리콘 Mac',
      },
      install: { term: '설치', value: 'DMG를 마운트한 뒤 "응용 프로그램"으로 끌어다 놓기' },
      package: { term: '패키지', value: 'Apple Silicon (arm64) · DMG' },
      architectures: { term: '다른 아키텍처', value: '릴리스 페이지' },
      mirror: { term: '미러', value: 'Gitee Releases' },
    },
  },
  faq: {
    eyebrow: '분명한 답 몇 가지',
    title: '자주 묻는 질문.',
    lede: '권한, 개인정보, 호환성 안내.',
    items: {
      audience: {
        question: 'zisla는 어떤 사람에게 맞나요?',
        answer:
          'AI, 미디어, 파일, 일정을 한곳에서 보고 싶은 Mac 사용자에게 맞습니다. 노치가 없는 디스플레이도 지원합니다.',
      },
      aiPrivacy: {
        question: 'zisla가 제 AI 대화 내용을 읽나요?',
        answer:
          '읽지 않습니다. AI 상태 모니터링은 작업 상태만 읽고 프롬프트나 응답 본문은 읽지 않습니다.',
      },
      copyAssistant: {
        question: '복사 도우미가 복사한 내용을 자동으로 열거나 업로드하나요?',
        answer:
          '아닙니다. 켠 뒤에도 내용 인식과 미리보기는 모두 이 Mac에서 이루어지며, 동작을 클릭하거나 단축키를 누른 뒤에만 해당 다음 단계를 실행합니다.',
      },
      permissions: {
        question: 'zisla는 어떤 시스템 권한이 필요한가요?',
        answer: `
      <p>zisla는 처음 실행할 때 모든 권한을 한꺼번에 요구하지 않습니다. 아래 기능을 켜고 실제로 사용할 때 macOS가 해당 권한을 요청합니다.</p>
      <ul>
        <li><strong>캘린더와 미리 알림:</strong> 일정 모듈을 열 때 각각 요청하며, 캘린더 이벤트와 날짜가 있는 미리 알림을 읽고 만들고 관리하는 데 사용합니다.</li>
        <li><strong>위치 서비스:</strong> 날씨에서 "현재 위치 사용"을 고를 때 요청합니다. 현재 위치를 한 번만 가져오며 계속 추적하지 않습니다. 도시를 직접 추가할 때는 필요하지 않습니다.</li>
        <li><strong>마이크와 음성 인식:</strong> 음성 입력을 시작할 때 요청합니다. 녹음하는 동안에만 소리를 받아들이고, 그 녹음의 받아쓰기만 처리합니다.</li>
        <li><strong>손쉬운 사용:</strong> 받아쓴 텍스트를 지금 쓰는 앱에 자동으로 넣기, 마우스 제스처로 빠르게 복사하기, 키보드 청소, 일부 지원 플레이어 제어에 필요합니다. 암호가 아닌 입력란을 찾거나 필요한 시스템 키를 보내는 데 사용합니다.</li>
        <li><strong>입력 모니터링:</strong> 키보드 사운드, 선택 사항인 로컬 입력 통계, 조합 키 단독이나 마우스 측면 버튼 같은 전역 트리거를 사용할 때 필요합니다. 이 기능에 필요한 전역 이벤트만 감시하며, 일반 전역 단축키에는 필요하지 않습니다.</li>
        <li><strong>화면 기록과 시스템 오디오 녹음:</strong> 스크린샷, 스크린샷 편집, 시스템 재생 오디오의 파형 표시에 필요합니다. 스크린샷은 화면 이미지를 읽고, 파형은 현재 시스템 오디오의 세기만 분석하며 오디오 내용을 저장하거나 전송하지 않습니다.</li>
        <li><strong>카메라:</strong> 거울 창을 열어 둔 동안에만 사용합니다.</li>
        <li><strong>Bluetooth:</strong> 배터리 모듈을 열어 둔 동안에만 연결·페어링된 기기가 공개한 잔량 정보를 읽습니다.</li>
        <li><strong>자동화:</strong> 빠른 메모, 메일, 데스크탑 정리, 지원 플레이어 직접 제어를 처음 사용할 때 macOS가 zisla에 "메모", "메일", "Finder" 또는 해당 앱을 제어할 권한을 줄지 각각 묻습니다. 빠른 메모는 "메모"를 읽고 쓰며, 메일은 읽기, 작성, 답장, 표시, 삭제를 할 수 있습니다.</li>
        <li><strong>전체 디스크 접근 권한:</strong> "메일"이 실행되지 않은 상태에서도 계정, 보낸 사람, 제목, 요약, 시간, 읽음 상태를 표시하기 위해 로컬 메일 색인을 읽어야 할 때만 필요합니다.</li>
        <li><strong>알림:</strong> 포모도로 타이머나 알람을 켤 때 요청하며, 타이머가 끝나거나 알람이 울릴 때 로컬 알림을 표시하는 데만 사용합니다.</li>
      </ul>
      <p><strong>폴더 권한은 전체 디스크 접근 권한이 아닙니다:</strong> 시스템 파일 선택 창에서 지정한 보관, 가져오기·내보내기, 다운로드 폴더에 대해 zisla는 그 폴더에 대한 접근 권한만 얻고 디스크 전체를 읽을 권한은 얻지 않습니다.</p>
      <p><strong>키보드 사운드와 입력 통계:</strong> 둘 다 기본적으로 꺼져 있으며, 하나라도 켜야 전역 키보드 이벤트를 감시합니다. 키보드 사운드는 소리를 내기 위해서만 키 이벤트를 처리하고, 입력 통계는 문자 수, 물리 키 코드, 시간, 맨 앞 앱 같은 집계 데이터만 저장하며 입력한 내용은 저장하지 않습니다. 설정에서 각각 끌 수 있고 끄면 더 이상 기록하지 않습니다. 이미 저장된 집계 데이터는 로컬 데이터베이스 파일에 남으며 직접 삭제할 수 있습니다.</p>
      <p>앱 설정에서 해당 기능을 끄거나, "시스템 설정 → 개인정보 보호 및 보안"에서 언제든 권한을 해제할 수 있습니다. 하나를 해제하면 관련 기능만 멈추고 다른 모듈에는 영향을 주지 않습니다. 항목 이름은 macOS 버전에 따라 조금 다를 수 있습니다.</p>
    `.trim(),
      },
      network: {
        question: 'zisla가 네트워크에 연결하나요?',
        answer:
          '날씨, 서명된 업데이트 확인, 직접 시작한 다운로드, 선택 사항인 원격 음성 정리는 필요할 때 통신합니다. 클립보드 링크 인식은 이 Mac에서만 이루어지며 스스로 다운로드를 시작하지 않습니다.',
      },
      multiDisplay: {
        question: 'zisla는 다중 디스플레이를 지원하나요?',
        answer:
          '지원합니다. 여러 디스플레이, Spaces, 일반 전체 화면 앱에서 동작하며 펼쳐질 때 포커스를 가져가지 않습니다.',
      },
      intel: {
        question: 'Intel Mac에서도 쓸 수 있나요?',
        answer:
          'Intel 기기용 빌드가 있을 수 있지만 호환성은 보장하지 않습니다. 현재 지원 구성은 Apple 실리콘 Mac입니다.',
      },
      storage: {
        question: 'zisla의 데이터는 어디에 저장되나요?',
        answer:
          '로컬 데이터는 ~/Library/Application Support/zisla/에 있습니다. 키보드 입력 통계는 ~/Library/Application Support/SimuBoard/typing-stats.sqlite3에 따로 저장됩니다. 빠른 메모는 시스템 "메모"를 사용합니다.',
      },
    },
  },
  developers: {
    eyebrow: '기본이 오픈 소스',
    title: '개발자 리소스.',
    lede: 'PolyForm Noncommercial 1.0.0 라이선스. 비상업적 용도로만, 그대로 쓰거나 소스에서 빌드할 수 있습니다.',
    docs: {
      macos: { title: 'macOS 개발 가이드', description: '기능, 빌드, 테스트, 시스템 제약' },
      architecture: { title: '아키텍처와 성능 설계', description: '상단 트리거, 창, 성능 설계' },
      cli: { title: 'CLI 연동 설계', description: 'zislactl 명령과 필드' },
      releasing: { title: '서명과 배포 설계', description: '서명, 공증, 배포 절차' },
      contributing: {
        title: '기여 가이드',
        description: '개발 환경, 브랜치, 커밋, Pull Request 요건',
      },
    },
    quickStartMono: '빠른 시작 / 소스',
    quickStartHeading: '소스에서 실행하거나 내 작업을 연결하세요.',
    copyRunCommandAriaLabel: '소스 실행 명령 복사',
    githubRepoLabel: 'GitHub 저장소',
    giteeRepoLabel: 'Gitee 저장소',
    checksumLabel: 'SHA-256',
    performancePoints: [
      '여러 디스플레이, Spaces, 일반 전체 화면 앱을 지원하며 펼쳐질 때 앱을 활성화하거나 포커스를 가져가지 않습니다',
      '숨어 있는 동안에는 상주하는 투명 핫존 창을 만들지 않고 프레임 루프도 돌리지 않습니다. 전역 이벤트 감시와 좌표 판정으로 펼칩니다',
      '시스템 재질을 한 겹만 사용하고, "투명도 줄이기"가 켜져 있으면 자동으로 불투명 배경으로 바뀝니다',
      'macOS 26 이상에서는 Liquid Glass를 사용하고 macOS 14/15에서는 시스템 기본 재질로 자동 폴백합니다',
      '실제 노치는 시스템 안전 영역으로 추정하고, 노치가 없는 외부 디스플레이에서는 전용 오버레이로 상태 바를 재현합니다',
    ],
  },
  footer: {
    brandHomeAriaLabel: 'zisla 홈으로 돌아가기',
    previewChannelLabel: 'Preview 채널',
    tagline: '오픈 소스, 네이티브, 통제권은 사용자에게.',
  },
  common: {
    copyCommandTitle: '명령 복사',
    copiedAriaLabel: '복사됨',
  },
  toast: {
    runCommandCopied: '소스 실행 명령을 복사했습니다',
    zislactlCopied: 'zislactl 명령을 복사했습니다',
    brewCommandCopied: 'Homebrew 설치 명령이 복사되었습니다',
  },
};
