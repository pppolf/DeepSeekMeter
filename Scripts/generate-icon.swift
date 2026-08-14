import AppKit

// 用法：swift Scripts/generate-icon.swift <输出目录(iconutil 兼容的 .iconset)>
// 绘制一个「深蓝渐变 + 三道白浪」的鲸鱼尾意象图标

let args = CommandLine.arguments
let outDir: URL
if args.count > 1 {
    outDir = URL(fileURLWithPath: args[1], isDirectory: true)
} else {
    outDir = URL(fileURLWithPath: "build/AppIcon.iconset", isDirectory: true)
}
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

let rect = NSRect(origin: .zero, size: size)
let clip = NSBezierPath(roundedRect: rect, xRadius: 224, yRadius: 224)
clip.addClip()

if let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.16, green: 0.42, blue: 0.98, alpha: 1),
    NSColor(calibratedRed: 0.05, green: 0.18, blue: 0.55, alpha: 1)
]) {
    gradient.draw(in: rect, angle: -70)
}

func drawWave(y: CGFloat, phase: CGFloat, amplitude: CGFloat, alpha: CGFloat) {
    let path = NSBezierPath()
    let step: CGFloat = 8
    var x: CGFloat = 96
    path.move(to: NSPoint(x: x, y: y))
    while x <= 928 {
        let yy = y + sin((x + phase) * 0.022) * amplitude * 0.5
        path.line(to: NSPoint(x: x, y: yy))
        x += step
    }
    NSColor.white.withAlphaComponent(alpha).setStroke()
    path.lineWidth = 40
    path.lineCapStyle = .round
    path.stroke()
}

drawWave(y: 470, phase: 0, amplitude: 110, alpha: 0.95)
drawWave(y: 610, phase: 1.4, amplitude: 150, alpha: 0.55)
drawWave(y: 750, phase: 2.6, amplitude: 70, alpha: 0.30)

image.unlockFocus()

let entries: [(name: String, size: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for entry in entries {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: entry.size, pixelsHigh: entry.size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { continue }
    rep.size = NSSize(width: entry.size, height: entry.size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(origin: .zero, size: rep.size))
    NSGraphicsContext.restoreGraphicsState()
    if let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: outDir.appendingPathComponent(entry.name))
    }
}
print("✅ 图标已生成到 \(outDir.path)")
