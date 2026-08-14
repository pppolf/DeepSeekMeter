import Foundation

enum BalanceError: LocalizedError {
    case emptyAPIKey
    case network(String)
    case http(Int)
    case decoding(String)

    var errorDescription: String? { message }

    /// 展示给用户的中文错误信息
    var message: String {
        switch self {
        case .emptyAPIKey:
            return "请先在设置中填写 DeepSeek API Key"
        case .network(let detail):
            return "网络请求失败：\(detail)"
        case .http(let code):
            switch code {
            case 401: return "API Key 无效或已过期（HTTP 401）"
            case 402: return "账户不可用或余额不足（HTTP 402）"
            case 429: return "请求过于频繁，请稍后再试（HTTP 429）"
            default: return "请求失败（HTTP \(code)）"
            }
        case .decoding(let detail):
            return "数据解析失败：\(detail)"
        }
    }
}

struct BalanceService {
    static let endpoint = URL(string: "https://api.deepseek.com/user/balance")!

    func fetch(apiKey: String) async throws -> BalanceResponse {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BalanceError.emptyAPIKey
        }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw BalanceError.network(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw BalanceError.http(http.statusCode)
        }

        do {
            return try JSONDecoder().decode(BalanceResponse.self, from: data)
        } catch {
            throw BalanceError.decoding(error.localizedDescription)
        }
    }
}
