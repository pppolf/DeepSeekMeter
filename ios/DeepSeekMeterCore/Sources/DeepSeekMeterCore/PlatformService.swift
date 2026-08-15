import Foundation

/// 平台错误（带用户可读的中文 message，对齐 macOS 版 PlatformError）
public enum PlatformError: LocalizedError {
    case emptyToken
    case network(String)
    case http(Int)
    case api(code: Int, msg: String)
    case decoding(String)

    public var errorDescription: String? { message }

    /// 展示给用户的中文错误信息
    public var message: String {
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

/// 平台私有接口客户端（platform.deepseek.com，用浏览器登录态 userToken 鉴权）。
/// 对齐 macOS 版 PlatformService.swift：接口契约（4 个已验证接口）与请求头完全一致；
/// 仅将 URLSession 改为可注入（默认 .shared），便于自测/预览注入 Mock。
public struct PlatformService {
    private static let baseURL = "https://platform.deepseek.com"
    private static let userAgent: String = {
        #if os(iOS)
        return "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        #else
        return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
        #endif
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - 接口

    /// 校验 Token 并返回用户信息（email、currency）；data / biz_data 为空视为校验失败
    public func fetchCurrentUser(token: String) async throws -> (email: String, currency: String) {
        struct CurrentUserData: Decodable {
            let id: String
            let email: String?
            let currency: String?
        }
        struct CurrentUserBiz: Decodable {
            let bizCode: Int
            let bizMsg: String
            let bizData: CurrentUserData?
        }
        struct CurrentUserResponse: Decodable {
            let code: Int
            let msg: String
            let data: CurrentUserBiz?
        }
        let response: CurrentUserResponse = try await get("/auth-api/v0/users/current", token: token)
        try ensureSuccess(response.code, msg: response.msg)
        guard let data = response.data else {
            throw PlatformError.api(code: response.code, msg: "用户信息为空")
        }
        try ensureBizSuccess(data.bizCode, msg: data.bizMsg)
        guard let user = data.bizData else {
            throw PlatformError.api(code: response.code, msg: "用户信息为空")
        }
        return (user.email ?? "", user.currency ?? "CNY")
    }

    /// 平台侧账户汇总（余额 / 累计消费）
    public func fetchSummary(token: String) async throws -> UserSummary {
        struct SummaryBiz: Decodable {
            let bizCode: Int
            let bizMsg: String
            let bizData: UserSummary?
        }
        struct SummaryResponse: Decodable {
            let code: Int
            let msg: String
            let data: SummaryBiz?
        }
        let response: SummaryResponse = try await get("/api/v0/users/get_user_summary", token: token)
        try ensureSuccess(response.code, msg: response.msg)
        guard let data = response.data else {
            throw PlatformError.api(code: response.code, msg: "summary 为空")
        }
        try ensureBizSuccess(data.bizCode, msg: data.bizMsg)
        guard let bizData = data.bizData else {
            throw PlatformError.api(code: response.code, msg: "summary 为空")
        }
        return bizData
    }

    /// 按 API Key 的 token 用量（实时；start/end 为 Unix 秒，tz 为秒偏移，bucket=86400 按天分桶）
    public func fetchAPIKeyAmount(token: String, start: Int, end: Int, tz: Int) async throws -> APIKeyAmountData {
        struct Biz: Decodable {
            let bizCode: Int
            let bizMsg: String
            let bizData: APIKeyAmountData?
        }
        struct Resp: Decodable {
            let code: Int
            let msg: String
            let data: Biz?
        }
        let response: Resp = try await get("/api/v0/usage/by_api_key/amount?start=\(start)&end=\(end)&tz=\(tz)&bucket=86400", token: token)
        try ensureSuccess(response.code, msg: response.msg)
        guard let data = response.data else {
            throw PlatformError.api(code: response.code, msg: "by_api_key amount 为空")
        }
        try ensureBizSuccess(data.bizCode, msg: data.bizMsg)
        guard let bizData = data.bizData else {
            throw PlatformError.api(code: response.code, msg: "by_api_key amount 为空")
        }
        return bizData
    }

    /// 按 API Key 的费用（实时；start/end 为 Unix 秒，tz 为秒偏移，bucket=86400 按天分桶）
    public func fetchAPIKeyCost(token: String, start: Int, end: Int, tz: Int) async throws -> APIKeyCostData {
        struct Biz: Decodable {
            let bizCode: Int
            let bizMsg: String
            let bizData: APIKeyCostData?
        }
        struct Resp: Decodable {
            let code: Int
            let msg: String
            let data: Biz?
        }
        let response: Resp = try await get("/api/v0/usage/by_api_key/cost?start=\(start)&end=\(end)&tz=\(tz)&bucket=86400", token: token)
        try ensureSuccess(response.code, msg: response.msg)
        guard let data = response.data else {
            throw PlatformError.api(code: response.code, msg: "by_api_key cost 为空")
        }
        try ensureBizSuccess(data.bizCode, msg: data.bizMsg)
        guard let bizData = data.bizData else {
            throw PlatformError.api(code: response.code, msg: "by_api_key cost 为空")
        }
        return bizData
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
            (data, response) = try await session.data(for: request)
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

    /// 业务层成功判断：data.biz_code 非 0 时抛 Api 异常（对齐 Windows 版）
    private func ensureBizSuccess(_ code: Int, msg: String) throws {
        guard code == 0 else {
            throw PlatformError.api(code: code, msg: msg)
        }
    }
}
