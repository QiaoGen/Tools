import AppKit

// 生成 1024x1024 app 图标：深色圆角矩形 + 等宽 "0x7F" 字样
let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let inset: CGFloat = 100
let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
NSColor(calibratedRed: 0.118, green: 0.118, blue: 0.125, alpha: 1).setFill()
NSBezierPath(roundedRect: rect, xRadius: 180, yRadius: 180).fill()

// 细描边
NSColor(calibratedWhite: 1.0, alpha: 0.1).setStroke()
let border = NSBezierPath(roundedRect: rect.insetBy(dx: 4, dy: 4), xRadius: 176, yRadius: 176)
border.lineWidth = 8
border.stroke()

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont(name: "Menlo-Bold", size: 300) ?? NSFont.boldSystemFont(ofSize: 300),
    .foregroundColor: NSColor(calibratedRed: 0.039, green: 0.518, blue: 1.0, alpha: 1),
    .paragraphStyle: paragraph,
]
let text = NSAttributedString(string: "0x7F", attributes: attrs)
let textSize = text.size()
text.draw(in: NSRect(
    x: (size - textSize.width) / 2,
    y: (size - textSize.height) / 2,
    width: textSize.width,
    height: textSize.height
))

image.unlockFocus()

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("生成 PNG 失败\n", stderr)
    exit(1)
}
try! png.write(to: URL(fileURLWithPath: output))
print("已生成 \(output)")
