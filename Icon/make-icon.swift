import AppKit

// 元画像から採った、左上→右下の対角線上の色。
// 右上と左下がほぼ同色だったので、対角に垂直な等色帯＝単純な線形グラデーションで再現できる。
let stops: [(Double, String)] = [
    (0.000, "D8B7FF"), (0.125, "D6B5FE"), (0.250, "E8A9D5"), (0.375, "FD958A"),
    (0.500, "FFA05C"), (0.625, "FCAF61"), (0.750, "EBCE66"), (0.875, "D9EA6A"),
    (1.000, "D0F768"),
]

func rgb(_ hex: String) -> (CGFloat, CGFloat, CGFloat) {
    var v: UInt64 = 0
    Scanner(string: hex).scanHexInt64(&v)
    return (CGFloat((v >> 16) & 0xFF) / 255, CGFloat((v >> 8) & 0xFF) / 255, CGFloat(v & 0xFF) / 255)
}

/// Apple のアイコンの角は円弧ではなく superellipse（squircle）。
/// |x/a|^n + |y/b|^n = 1 を n=5 で描くと、見た目がほぼ一致する。
func squircle(in rect: CGRect, n: Double = 5) -> CGPath {
    let path = CGMutablePath()
    let a = Double(rect.width) / 2, b = Double(rect.height) / 2
    let cx = Double(rect.midX), cy = Double(rect.midY)
    let steps = 1440
    for i in 0...steps {
        let t = Double(i) / Double(steps) * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = cx + a * (ct < 0 ? -1 : 1) * pow(abs(ct), 2 / n)
        let y = cy + b * (st < 0 ? -1 : 1) * pow(abs(st), 2 / n)
        if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

let size = 1024.0
let outPath = CommandLine.arguments[1]
let glyphIsWhite = CommandLine.arguments.count < 3 || CommandLine.arguments[2] == "white"
let glyphRatio = CommandLine.arguments.count > 3 ? Double(CommandLine.arguments[3])! : 0.52

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8,
                    bytesPerRow: 0, space: srgb,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// macOS のアイコンは 1024 の中に 824 の角丸が浮く形（周囲 100 は余白）。
let inset = 100.0
let box = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)

ctx.saveGState()
ctx.addPath(squircle(in: box))
ctx.clip()
let colors = stops.map { CGColor(colorSpace: srgb, components: [rgb($0.1).0, rgb($0.1).1, rgb($0.1).2, 1])! }
let gradient = CGGradient(colorsSpace: srgb, colors: colors as CFArray, locations: stops.map { CGFloat($0.0) })!
// CG は左下原点。左上 = (minX, maxY)、右下 = (maxX, minY)。
ctx.drawLinearGradient(gradient,
                       start: CGPoint(x: box.minX, y: box.maxY),
                       end: CGPoint(x: box.maxX, y: box.minY),
                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
ctx.restoreGState()

// ⌘（U+2318）を中央に。自前でパスを引かず、フォントの字形をそのまま使う。
//
// フォントのメトリクス（ascender / descender など）で中央を出すと上下にずれる。
// 字形の周りの余白はフォントの都合で決まっていて、見た目の重心とは一致しないからだ。
// なので一度別のレイヤーに描いてから、実際に色が付いた範囲（= インクの輪郭）を
// 走査して求め、その中心を箱の中心に合わせる。
let weightName = CommandLine.arguments.count > 4 ? CommandLine.arguments[4] : "semibold"
let weight: NSFont.Weight = [
    "medium": .medium, "semibold": .semibold, "bold": .bold, "heavy": .heavy,
][weightName] ?? .semibold

func glyphLayer() -> (CGImage, CGRect) {
    let side = Int(size)
    let lc = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                       bytesPerRow: side * 4, space: srgb,
                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: lc, flipped: false)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: box.width * glyphRatio, weight: weight),
        .foregroundColor: glyphIsWhite
            ? NSColor.white
            : NSColor(srgbRed: 0.16, green: 0.09, blue: 0.26, alpha: 1),
    ]
    NSAttributedString(string: "\u{2318}", attributes: attrs)
        .draw(at: CGPoint(x: size * 0.25, y: size * 0.25))
    NSGraphicsContext.restoreGraphicsState()

    let img = lc.makeImage()!
    // アルファが立っている画素の範囲を探す。
    let data = lc.data!.assumingMemoryBound(to: UInt8.self)
    var minX = side, minY = side, maxX = -1, maxY = -1
    for y in 0..<side {
        for x in 0..<side where data[(y * side + x) * 4 + 3] > 8 {
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }
        }
    }
    // このバッファは上の行から並ぶので、CG 座標に直すため y を反転する。
    let ink = CGRect(x: Double(minX), y: Double(side - 1 - maxY),
                     width: Double(maxX - minX + 1), height: Double(maxY - minY + 1))
    return (img, ink)
}

let (layer, ink) = glyphLayer()
ctx.draw(layer, in: CGRect(x: box.midX - ink.midX, y: box.midY - ink.midY,
                           width: size, height: size))
print("字形の輪郭: \(Int(ink.width))x\(Int(ink.height)) 箱に対して \(String(format: "%.0f%%", ink.width / box.width * 100))")

let cg = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: cg)
rep.size = NSSize(width: size, height: size)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))
print("書いた: \(outPath)")
