import SwiftUI

/// 简单折线图（余额趋势）
struct SparklineView: View {
    let points: [Double]
    var height: CGFloat = 44

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let chartHeight = geo.size.height
            let mapped = Self.map(points, width: width, height: chartHeight)
            ZStack(alignment: .leading) {
                if mapped.count > 1 {
                    // 渐变填充
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: chartHeight))
                        for pt in mapped { p.addLine(to: pt) }
                        p.addLine(to: CGPoint(x: width, y: chartHeight))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(
                        colors: [Color.accentColor.opacity(0.28), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    ))

                    // 折线
                    Path { p in
                        for (i, pt) in mapped.enumerated() {
                            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                        }
                    }
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                    // 最新点
                    if let last = mapped.last {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 6, height: 6)
                            .overlay(Circle().stroke(.white, lineWidth: 1))
                            .position(last)
                    }
                } else {
                    Text("暂无数据")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(height: height)
    }

    private static func map(_ pts: [Double], width: CGFloat, height: CGFloat) -> [CGPoint] {
        guard !pts.isEmpty else { return [] }
        guard let minV = pts.min(), let maxV = pts.max(), maxV > minV else {
            return pts.enumerated().map { i, _ in
                CGPoint(
                    x: pts.count > 1 ? CGFloat(i) / CGFloat(pts.count - 1) * width : width / 2,
                    y: height / 2
                )
            }
        }
        let span = maxV - minV
        let usable = height - 10
        return pts.enumerated().map { i, v in
            let x = pts.count > 1 ? CGFloat(i) / CGFloat(pts.count - 1) * width : width / 2
            let y = 5 + (1 - CGFloat((v - minV) / span)) * usable
            return CGPoint(x: x, y: y)
        }
    }
}
