import Foundation

// 轻量自测（不依赖 XCTest，命令行工具环境可直接运行）
var failures = 0

func check(_ cond: Bool, _ name: String) {
    if cond {
        print("✅ \(name)")
    } else {
        failures += 1
        print("❌ \(name)")
    }
}

// 1. 官方 balance 接口 JSON 解码
let json = """
{
  "is_available": true,
  "balance_infos": [
    {
      "currency": "CNY",
      "total_balance": "110.00",
      "granted_balance": "10.00",
      "topped_up_balance": "100.00"
    }
  ]
}
"""
do {
    let response = try JSONDecoder().decode(BalanceResponse.self, from: Data(json.utf8))
    check(response.isAvailable, "解码 is_available")
    check(response.balanceInfos.count == 1, "解码 balance_infos")
    let info = response.balanceInfos[0]
    check(info.currency == "CNY", "解码 currency")
    check(abs(info.total - 110) < 0.0001, "解码 total_balance -> 110")
    check(abs(info.granted - 10) < 0.0001, "解码 granted_balance -> 10")
    check(abs(info.toppedUp - 100) < 0.0001, "解码 topped_up_balance -> 100")
} catch {
    check(false, "JSON 解码抛错：\(error)")
}

// 2. 账户不可用
let json2 = #"{"is_available": false, "balance_infos": []}"#
do {
    let response = try JSONDecoder().decode(BalanceResponse.self, from: Data(json2.utf8))
    check(!response.isAvailable && response.balanceInfos.isEmpty, "解码不可用账户")
} catch {
    check(false, "不可用账户解码抛错：\(error)")
}

// 3. 格式化与币种符号
check(format(110.0) == "110.00", "format(110.0) -> 110.00")
check(format(0.35) == "0.35", "format(0.35) -> 0.35")
check(format(1234.5) == "1234.5", "format(1234.5) -> 1234.5")
check(currencySymbol("CNY") == "¥", "CNY -> ¥")
check(currencySymbol("USD") == "$", "USD -> $")
check(currencySymbol("EUR") == "€", "EUR -> €")
check(currencySymbol("XXX") == "XXX", "未知币种原样返回")

if failures > 0 {
    print("\n❌ \(failures) 项未通过")
    exit(1)
}
print("\n✅ 全部通过")
