import Foundation

enum PlatformError: LocalizedError {
    case emptyToken
    case network(String)
    case http(Int)
    case api(code: Int, msg: String)
    case decoding(String)

    var errorDescription: String? { message }

    /// 展示给用户的中文错误信息
    var message: String {
        switch self {
        case .emptyToken:
            return "请先在设置中填写平台 Token"
        case .network(let detail):
            return "用量获取失败：\(detail)"
        case .http(let code):
            return "用量获取失败（HTTP \(code)）"
        case .api(let code, let msg):
            if code == 40002 || code == 40003 {
                return "平台 Token 无效或已过期，请重新获取"
            }
            return "平台接口错误（\(code)）：\(msg)"
        case .decoding(let detail):
            return "用量解析失败：\(detail)"
        }
    }
}

/// 平台私有接口（platform.deepseek.com，用浏览器登录态 userToken 鉴权）
struct PlatformService {
    private static let baseURL = "https://platform.deepseek.com"
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    // MARK: - 接口

    /// 校验 Token 并返回用户信息（email、currency）
    func fetchCurrentUser(token: String) async throws -> (email: String, currency: String) {
        struct CurrentUserData: Decodable {
            let id: String
            let email: String?
            let currency: String?
        }
        struct CurrentUserBiz: Decodable {
            let bizData: CurrentUserData
        }
        struct CurrentUserResponse: Decodable {
            let code: Int
            let msg: String
            let data: CurrentUserBiz?
        }
        let response: CurrentUserResponse = try await get("/auth-api/v0/users/current", token: token)
        try ensureSuccess(response.code, msg: response.msg)
        let user = response.data?.bizData
        return (user?.email ?? "", user?.currency ?? "CNY")
    }

    /// 平台侧账户汇总（余额 / 累计消费）
    func fetchSummary(token: String) async throws -> UserSummary {
        struct SummaryBiz: Decodable {
            let bizData: UserSummary
        }
        struct SummaryResponse: Decodable {
            let code: Int
            let msg: String
            let data: SummaryBiz?
        }
        let response: SummaryResponse = try await get("/api/v0/users/get_user_summary", token: token)
        try ensureSuccess(response.code, msg: response.msg)
        guard let data = response.data?.bizData else {
            throw PlatformError.api(code: response.code, msg: "summary 为空")
        }
        return data
    }

    /// 本月 token 用量（biz_data 是对象）
    func fetchUsageAmount(token: String, month: Int, year: Int) async throws -> UsageData {
        struct Biz: Decodable {
            let bizData: UsageData
        }
        struct Resp: Decodable {
            let code: Int
            let msg: String
            let data: Biz?
        }
        let response: Resp = try await get("/api/v0/usage/amount?month=\(month)&year=\(year)", token: token)
        try ensureSuccess(response.code, msg: response.msg)
        guard let data = response.data?.bizData else {
            throw PlatformError.api(code: response.code, msg: "amount 为空")
        }
        return data
    }

    /// 本月费用（biz_data 是数组，取第一个）
    func fetchUsageCost(token: String, month: Int, year: Int) async throws -> UsageData {
        struct Biz: Decodable {
            let bizData: [UsageData]
        }
        struct Resp: Decodable {
            let code: Int
            let msg: String
            let data: Biz?
        }
        let response: Resp = try await get("/api/v0/usage/cost?month=\(month)&year=\(year)", token: token)
        try ensureSuccess(response.code, msg: response.msg)
        guard let first = response.data?.bizData.first else {
            throw PlatformError.api(code: response.code, msg: "cost 为空")
        }
        return first
    }

    // MARK: - 请求

    private func get<T: Decodable>(_ path: String, token: String) async throws -> T {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PlatformError.emptyToken
        }
        guard let url = URL(string: Self.baseURL + path) else {
            throw PlatformError.decoding("无效 URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("https://platform.deepseek.com/usage", forHTTPHeaderField: "Referer")
        request.setValue("https://platform.deepseek.com", forHTTPHeaderField: "Origin")
        request.timeoutInterval = 15

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw PlatformError.network(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw PlatformError.http(http.statusCode)
        }

        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw PlatformError.decoding(error.localizedDescription)
        }
    }

    private func ensureSuccess(_ code: Int, msg: String) throws {
        guard code == 0 else {
            throw PlatformError.api(code: code, msg: msg)
        }
    }
}
