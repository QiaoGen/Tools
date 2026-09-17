import AppKit

// 生成 1024x1024 app 图标：深色圆角矩形 + 寄存器格意象
// 注意：用 NSBitmapImageRep 精确控制像素尺寸，避免 Retina 下输出 2x 尺寸。
let pixelSize = 1024
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixelSize,
    pixelsHigh: pixelSize,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("创建位图失败\n", stderr)
    exit(1)
}
rep.size = NSSize(width: pixelSize, height: pixelSize)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let size = CGFloat(pixelSize)
let inset: CGFloat = 100
let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
NSColor(calibratedRed: 0.106, green: 0.106, blue: 0.114, alpha: 1).setFill()
NSBezierPath(roundedRect: rect, xRadius: 180, yRadius: 180).fill()

// 细描边
NSColor(calibratedWhite: 1.0, alpha: 0.1).setStroke()
let border = NSBezierPath(roundedRect: rect.insetBy(dx: 4, dy: 4), xRadius: 176, yRadius: 176)
border.lineWidth = 8
border.stroke()

// 4×3 寄存器格（等宽块 + 高亮单元），Modbus 数据表意象
let accent = NSColor(calibratedRed: 0.039, green: 0.518, blue: 1.0, alpha: 1)
let rows = 3
let cells = 4
let cellSize: CGFloat = 130
let gap: CGFloat = 18
let tableWidth = CGFloat(cells) * cellSize + CGFloat(cells - 1) * gap
let tableHeight = CGFloat(rows) * cellSize + CGFloat(rows - 1) * gap
let originX = (size - tableWidth) / 2
let originY = (size - tableHeight) / 2 - 40

// 亮起的单元
let lit: Set<[Int]> = [[0, 2], [1, 0], [1, 3], [2, 1]]

for r in 0..<rows {
    for c in 0..<cells {
        let cellRect = NSRect(x: originX + CGFloat(c) * (cellSize + gap),
                              y: originY + CGFloat(rows - 1 - r) * (cellSize + gap),
                              width: cellSize, height: cellSize)
        let isLit = lit.contains([r, c])
        if isLit {
            accent.setFill()
        } else {
            NSColor(calibratedWhite: 1.0, alpha: 0.10).setFill()
        }
        NSBezierPath(roundedRect: cellRect, xRadius: 26, yRadius: 26).fill()
        if isLit {
            // 高亮单元里画 "1"
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont(name: "Menlo-Bold", size: 84) ?? NSFont.boldSystemFont(ofSize: 84),
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraph,
            ]
            let text = NSAttributedString(string: "1", attributes: attrs)
            let textSize = text.size()
            text.draw(in: NSRect(
                x: cellRect.midX - textSize.width / 2,
                y: cellRect.midY - textSize.height / 2,
                width: textSize.width,
                height: textSize.height
            ))
        }
    }
}

NSGraphicsContext.restoreGraphicsState()

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
guard let png = rep.representation(using: .png, properties: [:]) else {
    fputs("生成 PNG 失败\n", stderr)
    exit(1)
}
try! png.write(to: URL(fileURLWithPath: output))
print("已生成 \(output)")
