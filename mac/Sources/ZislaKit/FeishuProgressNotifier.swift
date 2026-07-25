import Foundation

public enum FeishuProgressNotifier {
    /// 只发送任务名和状态，不推送 prompt、回答、附件路径或 API key。
    public static func send(
        webhookURL: String,
        title: String,
        detail: String,
        session: URLSession = .shared
    ) async {
        guard let url = URL(string: webhookURL), url.scheme == "https" else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let compactTitle = String(title.prefix(100))
        let compactDetail = String(detail.prefix(500))
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "msg_type": "text",
            "content": ["text": "zisla AI · \(compactTitle)\n\(compactDetail)"],
        ])
        _ = try? await session.data(for: request)
    }
}
