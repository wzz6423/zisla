import { createCatalog } from './createCatalog';

export const vi = createCatalog({
  meta: {
    documentTitle: 'zisla · Không gian làm việc động',
    description:
      'zisla là không gian làm việc động nguyên bản cho macOS. Gom tác vụ AI, phương tiện, tệp và lịch vào một nơi, cùng âm thanh bàn phím, thống kê gõ, chú thích ảnh chụp và trợ lý sao chép.',
    ogTitle: 'zisla · Đưa mọi thứ đang diễn ra đến nơi bạn có thể thấy',
    ogDescription:
      'Từ tác vụ AI và phương tiện đến âm thanh bàn phím, thống kê gõ, trợ lý sao chép, chú thích ảnh chụp và công cụ desktop — không gian macOS nguyên bản chỉ xuất hiện khi bạn cần.',
  },
  tagline: 'Không gian làm việc động nguyên bản cho macOS',
  header: {
    navAriaLabel: 'Điều hướng chính',
    brandHomeAriaLabel: 'Trang chủ zisla',
    menuOpenLabel: 'Mở menu điều hướng',
    menuCloseLabel: 'Đóng điều hướng',
    menuButtonTitle: 'Mở điều hướng',
    navItems: {
      showcase: 'Tính năng',
      ai: 'Quy trình AI',
      download: 'Tải xuống',
      faq: 'Câu hỏi thường gặp',
      developers: 'Nhà phát triển',
    },
    downloadCta: 'Tải xuống',
    downloadCtaAriaLabel: 'Đến phần tải xuống',
    languageLabel: 'Ngôn ngữ giao diện',
  },
  hero: {
    eyebrow: 'KHÔNG GIAN LÀM VIỆC MACOS NGUYÊN BẢN',
    title: 'zisla<br><em>Điều đang diễn ra,<br>ngay nơi<br class="hero-mobile-break"> bạn có thể thấy.</em>',
    lede:
      'Gom tác vụ AI, phương tiện, tệp và lịch ở đầu màn hình. Sau khi bạn sao chép, một thanh trợ lý riêng hiển thị bản xem trước và gợi ý bước tiếp theo. Thanh xuất hiện khi cần rồi thu lại khi xong.',
    downloadCta: 'Tải xuống',
    downloadCtaAriaLabel: 'Tải xuống',
    sourceCta: 'Xem mã nguồn',
    sourceCtaAriaLabel: 'Xem mã nguồn zisla trên GitHub',
    hints: [
      'Di chuyển con trỏ lên đầu màn hình để mở rộng, không cần nhấp',
      'Sau khi sao chép, nhấn Command+N cho bước thông minh tiếp theo',
      'Tự thu lại mà không làm gián đoạn công việc',
    ],
    identityCaption: 'Đầu màn hình',
  },
  proof: {
    ariaLabel: 'Tổng quan sản phẩm',
    items: {
      modules: { title: '{count} mô-đun trên cùng', desc: 'Bật các quy trình bạn cần' },
      os: { title: 'macOS 14+', desc: 'Trải nghiệm desktop nguyên bản' },
      displays: { title: 'Nhiều màn hình', desc: 'Hoạt động với màn hình có notch và màn hình ngoài' },
      local: { title: 'Ưu tiên cục bộ', desc: 'Trạng thái AI không bao giờ đọc cuộc trò chuyện' },
    },
  },
  showcase: {
    eyebrow: 'MỘT ĐIỂM TRUY CẬP / QUY TRÌNH HẰNG NGÀY',
    title: 'Quy trình hằng ngày, <span>ở đầu màn hình.</span>',
    lede:
      'Từ tác vụ AI đến clipboard, lịch và trạng thái hệ thống, zisla gom các quy trình desktop rời rạc vào một điểm truy cập.',
    ariaLabel: 'Danh mục tính năng zisla',
    summaryMono: '{modules} MÔ-ĐUN / {groups} QUY TRÌNH',
    summaryLede: 'Từ quy trình trên cùng đến công cụ cục bộ, mọi tác vụ có thể hoàn thành đều được mô tả ở đây.',
    summaryNote: '{modules} mô-đun trên cùng và {features} khả năng độc lập cho ảnh chụp, giọng nói, phương tiện, tải xuống, trợ lý sao chép, quản lý AI, thú cưng và màn hình khóa.',
    groupNames: {
      island: 'Quy trình trên cùng',
      ai: 'Quy trình AI',
      daily: 'Thông tin hằng ngày',
      tools: 'Tiện ích',
    },
    groupCount: '{count} mô-đun',
    pointsAriaLabel: 'Điểm nổi bật của {name}',
    modules: {
      dashboard: { name: 'Trang chính', caption: 'Thẻ động chỉ xuất hiện khi có phiên tập trung, tác vụ AI hoặc lượt tải đang chạy; khi không có gì xảy ra, chúng không chiếm chỗ.', points: ['Xuất hiện khi cần', 'Tiến trình trực tiếp', 'Bố cục tự điều chỉnh'] },
      shelf: { name: 'Kệ', caption: 'Kéo tệp, âm thanh, video hoặc liên kết vào dải trên cùng để lưu vào kệ, mở trong Finder hoặc gọi menu Chia sẻ của macOS.', points: ['Kéo lên trên để lưu', 'Mở trong Finder', 'Menu Chia sẻ hệ thống'] },
      clipboard: { name: 'Clipboard', caption: 'Xem lịch sử clipboard trong đảo và lọc theo ảnh, URL, đường dẫn hoặc loại tệp. Gửi mục vào Ghi chú nhanh, ghim làm yêu thích hoặc xóa.', points: ['Lịch sử trong đảo', 'Lọc theo loại', 'Ghi chú nhanh và yêu thích'] },
      aiMonitor: { name: 'Trình theo dõi AI', caption: 'Tự động phát hiện hoạt động từ CLI, ứng dụng desktop và IDE được hỗ trợ, gồm cả luồng Zed Agent, rồi hiển thị tác vụ, trạng thái, xu hướng token và bản đồ đóng góp. Chỉ phân tích sự kiện có cấu trúc, không đọc nội dung trò chuyện.', points: ['Gộp tác vụ từ nhiều công cụ', 'Xu hướng tiêu thụ token', 'Không đọc prompt hay câu trả lời'] },
      keyboardSound: { name: 'Âm thanh bàn phím', caption: 'Phát 20 âm thanh bàn phím cơ tích hợp cho phím bấm toàn hệ thống, có âm lượng và biến thiên cao độ tự nhiên. Bật thống kê gõ cục bộ để xem tổng quan, xu hướng, lịch sử, dòng thời gian ứng dụng và bản đồ phím F1-F12.', points: ['20 âm thanh tích hợp', 'Âm thanh nhả phím và biến thiên cao độ', 'Thống kê tùy chọn'] },
      download: { name: 'Trình tải xuống', caption: 'Dán liên kết hoặc để zisla nhận liên kết từ clipboard khi bật. Chọn video hoặc âm thanh và tải vào thư mục mặc định hay thư mục bạn chọn. Liên kết được hỗ trợ hiển thị nguồn, tiến trình trực tiếp và trạng thái hoàn tất.', points: ['Chế độ video / âm thanh', 'Thư mục mặc định hoặc tùy chỉnh', 'Nguồn và tiến trình trực tiếp'] },
      agenda: { name: 'Lịch và thời tiết', caption: 'Hiển thị thời tiết tại vị trí hiện tại và tối đa sáu địa điểm bạn chọn. Xem, thêm, xóa sự kiện và lời nhắc, rồi đánh dấu lời nhắc đã xong.', points: ['Thẻ thời tiết nhiều nơi', 'Lịch và việc cần làm', 'Hoàn tất lời nhắc bằng một chạm'] },
      mail: { name: 'Mail', caption: 'Đọc các tài khoản Mail đã bật, hiển thị hộp thư đến và cho phép đánh dấu, trả lời, soạn hoặc chuyển thư vào Thùng rác trong đảo, kèm hướng dẫn rõ ràng khi thiếu quyền.', points: ['Tài khoản Mail', 'Trả lời và soạn trong đảo', 'Hướng dẫn quyền minh bạch'] },
      quickNotes: { name: 'Ghi chú nhanh', caption: 'Dùng ứng dụng Ghi chú của hệ thống để xem, sửa, tạo và xóa ghi chú với bản xem trước Markdown trực tiếp. Bản nháp tự động được ghi lại.', points: ['Dữ liệu nằm trong Ghi chú', 'Trình soạn Markdown', 'Tự động lưu bản nháp'] },
      pdf: { name: 'Công cụ PDF', caption: 'Mười bốn thao tác ngay trên máy: hợp nhất, tách, xoay, cắt, chuyển đổi ảnh và tệp Office, kết xuất ảnh, trích xuất văn bản, thêm watermark và số trang, mã hóa, xóa mật khẩu và sửa metadata.', points: ['14 công cụ trên máy', 'Hợp nhất theo thứ tự bạn muốn', 'Không có dữ liệu rời khỏi Mac'] },
      toolbox: { name: 'Tiện ích', caption: 'Đếm giờ tập trung, giữ màn hình sáng, dọn màn hình và bàn phím (chặn cả F1-F12), báo thức, teleprompter, gương và Thùng rác trong một trang.', points: ['Đếm giờ tập trung', 'Chặn F1-F12 khi dọn dẹp', 'Teleprompter và gương'] },
      system: { name: 'Trạng thái hệ thống', caption: 'Kiểm tra CPU, GPU, bộ nhớ, ổ đĩa, mạng và quạt; đọc nhiệt độ NVMe SMART khi phần cứng hỗ trợ và dọn cache cùng nhật ký an toàn để xóa.', points: ['Theo dõi cấp chip', 'Nhiệt độ NVMe khi được hỗ trợ', 'Dọn cache bằng một chạm'] },
      battery: { name: 'Pin', caption: 'Xem mức sạc, tình trạng, số chu kỳ, nhiệt độ và dung lượng của Mac này, cùng mức pin của các thiết bị lân cận mà hệ thống cung cấp.', points: ['Chỉ số sức khỏe Mac', 'Thời gian còn lại', 'Pin thiết bị lân cận'] },
    },
  },
  extensions: {
    eyebrow: 'TRONG VÀ NGOÀI ĐẢO',
    title: 'Rời khỏi đảo, <span>vẫn là công cụ desktop.</span>',
    lede: 'Ảnh chụp, giọng nói, phương tiện, tải xuống trình duyệt và quản lý AI xuất hiện ở nơi dễ truy cập nhất.',
    ariaLabel: 'Khả năng desktop độc lập',
    summaryMono: 'VƯỢT RA NGOÀI ĐẢO',
    summaryLede: 'Các khả năng dùng thường xuyên, mỗi khả năng ở đúng vị trí tự nhiên.',
    summaryNote: 'Ảnh chụp, ghi âm, phương tiện, tải xuống trình duyệt, trợ lý sao chép, quản lý AI, thú cưng và màn hình khóa được trình bày riêng.',
    features: {
      capture: { title: 'Ảnh chụp, ảnh cuộn và ghim', description: 'Chụp hoặc ghim một phần màn hình bằng phím tắt toàn cục, thêm chú thích, ghép ảnh cuộn và nhận dạng hoặc xuất bảng. Chú thích đang sửa vẫn được giữ khi xuất.', detail: 'Phím tắt toàn cục · Chú thích và hoàn tác · Giữ chỉnh sửa khi xuất' },
      voice: { title: 'Nhập giọng nói và làm sạch', description: 'Bật bằng phím hoặc giữ để nói, dùng nhận dạng giọng nói hệ thống. Thêm từ vựng, từ nóng tùy chỉnh, định dạng có cấu trúc hoặc làm sạch bằng mô hình cục bộ hay từ xa.', detail: 'Hai chế độ ghi âm · Từ vựng và từ nóng · Làm sạch tùy chọn' },
      media: { title: 'Phương tiện và âm thanh nền hệ thống', description: 'Điều khiển nội dung đang phát từ đầu đảo hoặc chọn âm thanh nền macOS. Âm thanh có thể tự dừng khi khóa màn hình, bật trình bảo vệ hoặc màn hình ngủ.', detail: 'Điều khiển phát · Lời bài hát đồng bộ · Tự dừng âm thanh' },
      browserDownloads: { title: 'Tiến trình tải xuống trình duyệt', description: 'Phát hiện tải xuống từ Safari, Chrome, Edge, Firefox, Brave, Vivaldi, Opera và Arc, hiển thị nguồn và tiến trình trực tiếp ở trên.', detail: '8 trình duyệt · Nhận dạng nguồn · Thông báo hoàn tất' },
      copyAssistant: { title: 'Trợ lý sao chép và bước tiếp theo', description: 'Khi bật, văn bản, liên kết, tệp hoặc ảnh đã sao chép được xem trước trong thanh riêng, kèm đề xuất mở, hiện trong Finder, tìm kiếm, dịch, tính toán hoặc lưu chỉ sau khi bạn xác nhận.', detail: 'Bật tùy chọn · Nhận dạng cục bộ · Command+N mặc định' },
      aiManagement: { title: 'Quản lý CLI và Skills AI', description: 'Phát hiện, cài đặt, cập nhật và gỡ CLI AI trong Cài đặt, đồng thời xem và quản lý Skills cục bộ để ít phải chuyển giữa các terminal.', detail: 'Phát hiện và cài đặt · Cập nhật và gỡ · Skills cục bộ' },
      pet: { title: 'Thú cưng trong đảo', description: 'Chọn thú cưng tích hợp và đặt ở bên trái hoặc phải đảo. Tắt bất cứ lúc nào.', detail: 'Nhân vật tích hợp · Trái hoặc phải · Bật khi cần' },
      lockScreen: { title: 'Thông tin màn hình khóa', description: 'Tùy chọn hiển thị ngày, trạng thái và nội dung đang phát trên màn hình khóa macOS. Đây là lớp phủ riêng, không xuất hiện trong danh sách hay băng chuyền mô-đun của đảo.', detail: 'Lớp phủ riêng · Tùy chọn bật · Không chiếm tiêu điểm' },
    },
  },
  ai: {
    eyebrow: 'AI KHÔNG HỘP ĐEN',
    title: 'Xem trạng thái AI <span>mà không đọc cuộc trò chuyện.</span>',
    lede: 'Tác vụ, trạng thái và xu hướng token ở lại trên Mac. Trang này mô tả tính năng chứ không giả lập một tác vụ đang chạy.',
    summaryMono: 'TRẠNG THÁI CỤC BỘ / RANH GIỚI RÕ RÀNG',
    summaryLede: 'Kết nối các công cụ AI bạn dùng mà vẫn giữ ranh giới ngữ cảnh cần thiết.',
    summaryNote: 'Chỉ mô tả phạm vi phát hiện, ranh giới dữ liệu và cách kết nối; không mô phỏng phiên trực tiếp.',
    toolsHeading: 'Công cụ AI được hỗ trợ',
    toolsLede: 'Phát hiện hoạt động từ CLI, ứng dụng desktop và IDE được hỗ trợ rồi tổng hợp trạng thái tác vụ.',
    toolsAriaLabel: 'Công cụ AI được hỗ trợ',
    doubaoName: 'Doubao',
    boundariesHeading: 'Chỉ ghi lại ranh giới trạng thái',
    privacyPoints: ['Chỉ phân tích loại sự kiện, trạng thái, thời gian, mô hình và ID phiên từ sự kiện có cấu trúc', 'Không đọc văn bản prompt hay câu trả lời', 'Giao thức và trạng thái được lưu trên Mac'],
    bridgeHeading: 'Kết nối tác vụ của bạn',
    bridgeLede: 'Dùng zislactl để gửi trạng thái có cấu trúc của tác vụ bên ngoài vào thanh trạng thái.',
    zislactlTaskTitle: 'Build và phát hành',
    copyZislactlAriaLabel: 'Sao chép lệnh zislactl',
  },
  flow: {
    eyebrow: 'NHỊP TƯƠNG TÁC',
    title: 'Di chuyển lên, <span>xem rồi bỏ qua.</span>',
    lede: 'Không bao giờ chiếm tiêu điểm và tự thu lại sau khi bạn xem xong.',
    ariaLabel: 'Nhịp tương tác trên cùng',
    summaryMono: 'THANH TRẠNG THÁI / 3 BƯỚC',
    summaryLede: 'Mở rộng khi cần và thu lại khi bạn đọc xong.',
    summaryNote: 'Được kích hoạt theo vị trí con trỏ, không chiếm chỗ khi trống và không lấy tiêu điểm.',
    steps: {
      trigger: { phase: 'Kích hoạt', title: 'Di chuyển con trỏ đến giữa phía trên', desc: 'Màn hình có notch và màn hình ngoài dùng cùng một bộ kích hoạt; khi ẩn không chạy vòng lặp khung hình.' },
      review: { phase: 'Xem', title: 'Liếc nhanh trạng thái hiện tại', desc: 'Phương tiện, tệp, AI, lịch và công cụ hệ thống ở cùng một nơi.' },
      dismiss: { phase: 'Đóng', title: 'Quay lại công việc', desc: 'Đưa con trỏ ra ngoài và thanh sẽ thu lại; mở rộng không kích hoạt ứng dụng hay lấy tiêu điểm.' },
    },
  },
  download: {
    eyebrow: 'SẴN SÀNG KHI BẠN SẴN SÀNG',
    title: 'Tải zisla',
    copy: 'Dành cho Mac Apple Silicon. Phiên bản, kiến trúc khác và checksum có trên trang phát hành. Sau khi cài đặt, Sparkle xác minh chữ ký trước rồi tải, cài và khởi động lại thủ công hoặc tự động theo cài đặt.',
    primaryCta: 'Tải xuống',
    primaryCtaAriaLabel: 'Tải zisla',
    releaseCta: 'Xem bản phát hành',
    releaseCtaAriaLabel: 'Xem chi tiết bản phát hành trên GitHub',
    notes: {
      system: { term: 'Hệ thống', value: 'macOS 14 trở lên · Cấu hình được hỗ trợ: Mac Apple Silicon' },
      install: { term: 'Cài đặt', value: 'Gắn DMG rồi kéo vào Applications' },
      package: { term: 'Gói', value: 'Apple Silicon (arm64) · DMG' },
      architectures: { term: 'Kiến trúc khác', value: 'Trang phát hành' },
      mirror: { term: 'Bản sao', value: 'Gitee Releases' },
    },
  },
  faq: {
    eyebrow: 'MỘT VÀI CÂU TRẢ LỜI RÕ RÀNG',
    title: 'Câu hỏi thường gặp.',
    lede: 'Quyền, riêng tư và khả năng tương thích.',
    items: {
      audience: { question: 'zisla dành cho ai?', answer: 'Dành cho người dùng Mac muốn xem AI, phương tiện, tệp và lịch ở một nơi. Màn hình không có notch cũng được hỗ trợ.' },
      aiPrivacy: { question: 'zisla có đọc cuộc trò chuyện AI của tôi không?', answer: 'Không. Theo dõi AI chỉ đọc trạng thái tác vụ, không đọc văn bản prompt hay câu trả lời.' },
      copyAssistant: { question: 'Trợ lý sao chép có mở hoặc tải lên nội dung tôi sao chép không?', answer: 'Không. Nhận dạng và xem trước diễn ra trên Mac, bước tiếp theo chỉ chạy sau khi bạn xác nhận.' },
      permissions: {
        question: 'zisla cần những quyền hệ thống nào?',
        answer: `
      <p>zisla không yêu cầu mọi quyền ngay lần đầu khởi chạy. macOS chỉ hiển thị từng yêu cầu khi bạn bật và thực sự dùng tính năng tương ứng:</p>
      <ul>
        <li><strong>Lịch và Lời nhắc:</strong> được yêu cầu riêng khi bạn mở mô-đun lịch, để đọc, tạo và quản lý sự kiện lịch cùng lời nhắc có ngày.</li>
        <li><strong>Dịch vụ định vị:</strong> được yêu cầu khi bạn chọn thời tiết cho vị trí hiện tại. zisla chỉ lấy vị trí một lần và không theo dõi liên tục. Thêm thành phố thủ công không cần quyền định vị.</li>
        <li><strong>Micrô và Nhận dạng giọng nói:</strong> được yêu cầu khi bạn bắt đầu nhập bằng giọng nói. Âm thanh chỉ được thu trong lúc bạn chủ động ghi âm và chỉ bản ghi đó được chuyển thành văn bản.</li>
        <li><strong>Trợ năng:</strong> cần để tự động chèn bản chép lời vào ứng dụng hiện tại, sao chép nhanh bằng cử chỉ chuột, làm sạch bàn phím và điều khiển một số trình phát được hỗ trợ. Quyền này giúp tìm các ô nhập không phải ô mật khẩu hoặc gửi những phím hệ thống cần thiết.</li>
        <li><strong>Giám sát đầu vào:</strong> dùng cho âm thanh bàn phím, thống kê gõ cục bộ tùy chọn và các kích hoạt toàn cục như một phím bổ trợ đơn lẻ hoặc nút bên chuột. Chỉ các sự kiện toàn cục mà những tính năng này cần mới được theo dõi; phím tắt toàn cục thông thường không cần quyền này.</li>
        <li><strong>Ghi màn hình và Ghi âm thanh hệ thống:</strong> cần cho ảnh chụp màn hình, chỉnh sửa ảnh chụp và dạng sóng của âm thanh hệ thống đang phát. Ảnh chụp đọc hình ảnh trên màn hình; dạng sóng chỉ phân tích mức âm thanh hệ thống hiện tại và không lưu hay tải âm thanh lên.</li>
        <li><strong>Camera:</strong> chỉ dùng khi cửa sổ gương đang mở.</li>
        <li><strong>Bluetooth:</strong> chỉ dùng khi mô-đun pin đang mở, để đọc mức pin do các thiết bị đã kết nối hoặc ghép đôi công bố.</li>
        <li><strong>Tự động hóa:</strong> lần đầu bạn dùng Ghi chú nhanh, Mail, dọn màn hình nền hoặc điều khiển trực tiếp trình phát được hỗ trợ, macOS sẽ hỏi riêng liệu zisla có thể điều khiển Ghi chú, Mail, Finder hoặc ứng dụng đó hay không. Ghi chú nhanh đọc và ghi vào Ghi chú; Mail có thể đọc, soạn, trả lời, đánh dấu và xóa thư.</li>
        <li><strong>Toàn quyền truy cập ổ đĩa:</strong> chỉ cần khi Mail không chạy mà zisla vẫn phải đọc chỉ mục thư cục bộ để hiển thị tài khoản, người gửi, chủ đề, bản xem trước, dấu thời gian và trạng thái đã đọc.</li>
        <li><strong>Thông báo:</strong> được yêu cầu khi bạn bật bộ hẹn giờ Pomodoro hoặc báo thức, chỉ để hiển thị thông báo cục bộ khi bộ hẹn giờ kết thúc hoặc báo thức kêu.</li>
      </ul>
      <p><strong>Quyền thư mục không phải là toàn quyền truy cập ổ đĩa:</strong> với các thư mục kệ, nhập/xuất hoặc tải xuống bạn chọn trong bộ chọn tệp của hệ thống, zisla chỉ được truy cập thư mục đó, không được đọc toàn bộ ổ đĩa.</p>
      <p><strong>Âm thanh bàn phím và thống kê gõ:</strong> cả hai đều tắt theo mặc định, và sự kiện bàn phím toàn cục chỉ được theo dõi sau khi bạn bật một trong hai. Khi bật âm thanh bàn phím, sự kiện phím chỉ dùng để phát âm thanh; khi bật thống kê gõ, chỉ dữ liệu tổng hợp — số ký tự, mã phím vật lý, dấu thời gian và ứng dụng ở phía trước — được lưu, không bao giờ lưu nội dung bạn đã gõ. Bạn có thể tắt từng tính năng riêng trong Cài đặt; sau đó sẽ không ghi thêm dữ liệu. Dữ liệu đã lưu vẫn nằm trong tệp cơ sở dữ liệu cục bộ mà bạn có thể tự xóa.</p>
      <p>Bạn có thể tắt tính năng trong cài đặt ứng dụng hoặc thu hồi quyền bất cứ lúc nào tại Cài đặt hệ thống → Quyền riêng tư &amp; Bảo mật. Thu hồi một quyền chỉ tắt tính năng liên quan và không ảnh hưởng các mô-đun khác. Tên mục có thể hơi khác giữa các phiên bản macOS.</p>
    `.trim(),
      },
      network: { question: 'zisla có kết nối mạng không?', answer: 'Thời tiết, kiểm tra cập nhật có chữ ký, lượt tải bạn khởi động và làm sạch giọng nói từ xa tùy chọn dùng mạng khi cần. Nhận dạng liên kết clipboard chạy cục bộ.' },
      multiDisplay: { question: 'zisla có hỗ trợ nhiều màn hình không?', answer: 'Có: nhiều màn hình, Spaces và ứng dụng toàn màn hình thông thường; mở rộng không lấy tiêu điểm.' },
      intel: { question: 'Có thể dùng trên Mac Intel không?', answer: 'Có thể có bản dựng cho Intel nhưng không đảm bảo tương thích. Cấu hình được hỗ trợ hiện tại là Apple Silicon.' },
      storage: { question: 'zisla lưu dữ liệu ở đâu?', answer: 'Dữ liệu cục bộ nằm tại ~/Library/Application Support/zisla/. Thống kê gõ được lưu riêng tại ~/Library/Application Support/SimuBoard/typing-stats.sqlite3. Ghi chú nhanh dùng ứng dụng Ghi chú hệ thống.' },
    },
  },
  developers: {
    eyebrow: 'MÃ NGUỒN MỞ THEO MẶC ĐỊNH',
    title: 'Tài nguyên cho nhà phát triển.',
    lede: 'Giấy phép PolyForm Noncommercial 1.0.0 — chỉ dùng cho mục đích phi thương mại, dùng nguyên trạng hoặc build từ mã nguồn.',
    docs: {
      macos: { title: 'Hướng dẫn phát triển macOS', description: 'Tính năng, build, kiểm thử và giới hạn hệ thống' },
      architecture: { title: 'Kiến trúc và hiệu năng', description: 'Kích hoạt trên cùng, cửa sổ và thiết kế hiệu năng' },
      cli: { title: 'Tích hợp CLI', description: 'Lệnh và trường của zislactl' },
      releasing: { title: 'Ký và phát hành', description: 'Ký, công chứng và quy trình phát hành' },
      contributing: { title: 'Hướng dẫn đóng góp', description: 'Môi trường, nhánh, commit và yêu cầu pull request' },
    },
    quickStartMono: 'BẮT ĐẦU NHANH / MÃ NGUỒN',
    quickStartHeading: 'Chạy từ mã nguồn hoặc kết nối tác vụ của bạn.',
    copyRunCommandAriaLabel: 'Sao chép lệnh chạy từ mã nguồn',
    githubRepoLabel: 'Kho GitHub',
    giteeRepoLabel: 'Kho Gitee',
    checksumLabel: 'SHA-256',
    performancePoints: [
      'Hỗ trợ nhiều màn hình, Spaces và ứng dụng toàn màn hình thông thường; mở rộng không kích hoạt ứng dụng hay lấy tiêu điểm',
      'Khi ẩn không tạo cửa sổ vùng nóng trong suốt cố định và không chạy vòng lặp khung hình; mở rộng dựa trên sự kiện toàn cục và hình học',
      'Dùng một lớp vật liệu hệ thống và chuyển sang nền đục khi bật Giảm độ trong suốt',
      'Liquid Glass trên macOS 26+, tự động dùng vật liệu nguyên bản trên macOS 14 và 15',
      'Suy ra notch vật lý từ vùng an toàn hệ thống; màn hình ngoài không có notch dùng thanh trạng thái mô phỏng trong lớp phủ riêng',
    ],
  },
  footer: {
    brandHomeAriaLabel: 'Quay lại trang chủ zisla',
    previewChannelLabel: 'Kênh Preview',
    tagline: 'Mã nguồn mở, nguyên bản và nằm trong tầm kiểm soát của bạn.',
  },
  common: { copyCommandTitle: 'Sao chép lệnh', copiedAriaLabel: 'Đã sao chép' },
  toast: { runCommandCopied: 'Đã sao chép lệnh chạy mã nguồn', zislactlCopied: 'Đã sao chép lệnh zislactl' },
});
