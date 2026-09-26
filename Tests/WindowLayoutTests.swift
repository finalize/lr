import CoreGraphics
import Foundation

// ウィンドウ配置の計算（One/WindowLayout.swift・One/WindowHistory.swift）を確かめる。
//
// 画面もウィンドウも使わない。配置は枠（CGRect）と画面の並び（ScreenArea）だけで決まるので、
// 画面を自分で組み立てて渡せば、ディスプレイが1枚の機械でも縦長の画面や2段の並びを試せる。
//
// 実装は読まずに、仕様（「One のウィンドウ配置 — 決めごと」）だけを見て書いた。
// 期待値は仕様の例の数値か、仕様の規則から手で計算した値。実装の出力を写した値は無い。
// 奇数の幅や 3 で割り切れない幅は、仕様の境目の式（specBorder）で計算した値と照らす。

// MARK: - 組み立て

private func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
    CGRect(x: x, y: y, width: w, height: h)
}

/// visible の上にメニューバー 25 を足した frame を持つ画面。
private func screenWith(visible v: CGRect) -> ScreenArea {
    ScreenArea(frame: box(v.minX, v.minY - 25, v.width, v.height + 25), visible: v)
}

// 仕様の例の2枚。主画面（上にメニューバー 30、下に Dock 64）と、その右隣の小さい画面。
private let mainScreen = ScreenArea(frame: box(0, 0, 2560, 1440), visible: box(0, 30, 2560, 1346))
private let rightScreen = ScreenArea(frame: box(2560, 0, 1920, 1080), visible: box(2560, 25, 1920, 1055))
// 主画面の上の段。右へずらしてあるので、x だけで並べると主画面と右隣の間に入ってしまう。
// 下の辺（y = 0）は主画面の上の辺にちょうど接している。
private let upperScreen = ScreenArea(frame: box(1500, -1080, 1920, 1080), visible: box(1500, -1055, 1920, 1055))
// 主画面の左。下へずらしてあるが縦に重なっているので主画面と同じ段。minY で並べると最後に来てしまう。
private let leftScreen = ScreenArea(frame: box(-1920, 360, 1920, 1080), visible: box(-1920, 385, 1920, 1055))
// 主画面の下の段。
private let lowerScreen = ScreenArea(frame: box(0, 1440, 1920, 1080), visible: box(0, 1465, 1920, 1055))
// 主画面の右に縦置きした画面（幅 < 高さ）。高さ 1895 は 3 で割り切れない。
private let portraitScreen = ScreenArea(frame: box(2560, -400, 1080, 1920), visible: box(2560, -375, 1080, 1895))
// 主画面の左の、visible が正方形の画面。
private let squareScreen = ScreenArea(frame: box(-1000, 0, 1000, 1025), visible: box(-1000, 25, 1000, 1000))
// 主画面の左の、負の x にある奇数幅の画面。
private let oddLeftScreen = ScreenArea(frame: box(-1001, 0, 1001, 800), visible: box(-1001, 25, 1001, 775))
// 主画面の右に小さい画面を2枚縦に積んだ並び。上の2枚は互いに別の段だが、どちらも主画面とは縦に重なる。
private let stackTop = ScreenArea(frame: box(2560, 0, 1280, 720), visible: box(2560, 25, 1280, 695))
private let stackBottom = ScreenArea(frame: box(2560, 720, 1280, 720), visible: box(2560, 745, 1280, 695))

private let mainA = mainScreen.visible
/// 主画面の上の、どの端にも付いていないウィンドウ（仕様の例の「浮いているウィンドウ」）。
private let floating = box(500, 300, 800, 600)

private func act(
    _ action: WindowAction, _ window: CGRect, _ screens: [ScreenArea] = [mainScreen], restore: CGRect? = nil
) -> CGRect? {
    action.target(for: window, screens: screens, restore: restore)
}

// MARK: - 仕様の式（期待値を作るためのもの）

/// 仕様の境目の式: 始点 s・長さ L を n 等分した k 本目の境目 = s + round(L × k / n)。
/// round は四捨五入（0.5 は 0 から遠い側）で、Swift の `.rounded()` と同じ。
private func specBorder(_ s: CGFloat, _ length: CGFloat, _ k: Int, _ n: Int) -> CGFloat {
    s + (length * CGFloat(k) / CGFloat(n)).rounded()
}

/// n 等分の [k, m)。
private struct Span { let k: Int, m: Int, n: Int }
private let whole = Span(k: 0, m: 1, n: 1)
private func half(_ k: Int) -> Span { Span(k: k, m: k + 1, n: 2) }

private func specCell(_ a: CGRect, x: Span, y: Span) -> CGRect {
    let x0 = specBorder(a.minX, a.width, x.k, x.n), x1 = specBorder(a.minX, a.width, x.m, x.n)
    let y0 = specBorder(a.minY, a.height, y.k, y.n), y1 = specBorder(a.minY, a.height, y.m, y.n)
    return box(x0, y0, x1 - x0, y1 - y0)
}

/// 仕様の表をそのまま写したもの（横の範囲・縦の範囲）。
private let halvesTable: [(WindowAction, Span, Span)] = [
    (.leftHalf, half(0), whole), (.rightHalf, half(1), whole),
    (.topHalf, whole, half(0)), (.bottomHalf, whole, half(1)),
    (.topLeft, half(0), half(0)), (.topRight, half(1), half(0)),
    (.bottomLeft, half(0), half(1)), (.bottomRight, half(1), half(1)),
    (.maximize, whole, whole),
]
/// 3分割の表。分ける向きの範囲だけを持つ（向きは A の縦横で決まる）。
private let thirdsTable: [(WindowAction, Span)] = [
    (.firstThird, Span(k: 0, m: 1, n: 3)),
    (.centerThird, Span(k: 1, m: 2, n: 3)),
    (.lastThird, Span(k: 2, m: 3, n: 3)),
    (.firstTwoThirds, Span(k: 0, m: 2, n: 3)),
    (.lastTwoThirds, Span(k: 1, m: 3, n: 3)),
    (.centerTwoThirds, Span(k: 1, m: 5, n: 6)),
]
private let gridActions: [WindowAction] = halvesTable.map { $0.0 } + thirdsTable.map { $0.0 }
private let thirdActions: [WindowAction] = thirdsTable.map { $0.0 }

private func specGrid(_ action: WindowAction, _ a: CGRect) -> CGRect {
    if let row = halvesTable.first(where: { $0.0 == action }) { return specCell(a, x: row.1, y: row.2) }
    let row = thirdsTable.first(where: { $0.0 == action })!
    return a.width > a.height ? specCell(a, x: row.1, y: whole) : specCell(a, x: whole, y: row.1)
}

/// 仕様の並び: a.frame.maxY ≤ b.frame.minY なら a が上の段、縦に重なれば同じ段、段の中は frame.minX の順。
/// 段が1通りに決まらない並び（同じ段の関係が推移的でない、段の上下が組ごとに食い違う、段の中で minX が同じ）は
/// 仕様から答えが出ないので nil。
private func specOrder(_ screens: [ScreenArea]) -> [ScreenArea]? {
    func above(_ a: ScreenArea, _ b: ScreenArea) -> Bool { a.frame.maxY <= b.frame.minY }
    func sameRow(_ a: ScreenArea, _ b: ScreenArea) -> Bool { !above(a, b) && !above(b, a) }
    var rows: [[ScreenArea]] = []
    for s in screens {
        if let i = rows.firstIndex(where: { sameRow($0[0], s) }) { rows[i].append(s) } else { rows.append([s]) }
    }
    for row in rows {
        for a in row { for b in row where !sameRow(a, b) { return nil } }
        if Set(row.map { $0.frame.minX }).count != row.count { return nil }
    }
    for r1 in rows.indices {
        for r2 in rows.indices where r1 < r2 {
            let pairs = rows[r1].flatMap { a in rows[r2].map { (a, $0) } }
            if !pairs.allSatisfy({ above($0, $1) }) && !pairs.allSatisfy({ above($1, $0) }) { return nil }
        }
    }
    return rows.sorted { above($0[0], $1[0]) }.flatMap { $0.sorted { $0.frame.minX < $1.frame.minX } }
}

// MARK: - 性質を見るための入力

/// いろいろな visible。奇数・3 で割り切れない・縦長・正方形・幅が高さより 1 だけ大きい・とても小さい、
/// を、原点が 0・負・正の位置に置く。
private let sampleAreas: [CGRect] = {
    let sizes: [(CGFloat, CGFloat)] = [
        (2560, 1346), (1920, 1055), (1001, 775), (1053, 700), (1366, 743), (3440, 1415),
        (1080, 1895), (799, 1201), (1000, 1000), (1279, 1279), (1001, 1000),
        (7, 5), (5, 7), (11, 11),
    ]
    let origins: [(CGFloat, CGFloat)] = [(0, 30), (-1001, 25), (2560, -375), (-7, -13), (1440, 2000)]
    return origins.flatMap { o in sizes.map { s in box(o.0, o.1, s.0, s.1) } }
}()
/// larger / smaller を試せる大きさの visible。
private let roomyAreas = sampleAreas.filter { $0.width >= 700 && $0.height >= 700 }

/// A の中に置いたいろいろなウィンドウ。格子の位置（仕様の式で作る）と、端からの距離を変えた浮いたもの。
private func windowsInside(_ a: CGRect) -> [CGRect] {
    gridActions.map { specGrid($0, a) } + [
        box(a.minX + 100, a.minY + 100, 300, 200),
        box(a.minX + 5, a.minY + 5, 400, 300), // 始点側に許容差ちょうど
        box(a.minX + 6, a.minY + 6, 400, 300), // 許容差を 1 超える
        box(a.maxX - 405, a.maxY - 305, 400, 300), // 終点側に許容差ちょうど
        box(a.maxX - 416, a.maxY - 316, 400, 300), // 終点側から 16 離れている
        box(a.minX + 3, a.minY + 3, a.width - 6, a.height - 6), // 四辺とも許容差の中
        box(a.minX + 8, a.minY + 8, a.width - 16, a.height - 16), // 大きいが端に付いていない
    ]
}

/// 画面の並びの例。
private let layouts: [[ScreenArea]] = [
    [mainScreen, rightScreen],
    [mainScreen, rightScreen, upperScreen, leftScreen],
    [mainScreen, rightScreen, upperScreen, leftScreen, lowerScreen],
    [mainScreen, portraitScreen, oddLeftScreen],
    [mainScreen, stackTop, stackBottom],
]

// MARK: - 幾何の補助

private func overlapArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
    let w = min(a.maxX, b.maxX) - max(a.minX, b.minX)
    let h = min(a.maxY, b.maxY) - max(a.minY, b.minY)
    return max(0, w) * max(0, h)
}

private func isInside(_ r: CGRect, _ b: CGRect) -> Bool {
    r.minX >= b.minX && r.maxX <= b.maxX && r.minY >= b.minY && r.maxY <= b.maxY
}

private func isIntegral(_ r: CGRect) -> Bool {
    [r.origin.x, r.origin.y, r.size.width, r.size.height].allSatisfy { $0 == $0.rounded() }
}

/// rects が A を隙間も重なりもなく敷き詰めているか。崩れていれば理由を返す。
/// 全部が A の中・どの2枚も重ならない・面積の合計が A の面積、の3つが揃えば敷き詰めている。
private func tilingProblem(_ rects: [CGRect?], _ a: CGRect) -> String? {
    guard let rs = rects as? [CGRect] else { return "A \(show(a)) で nil が返った" }
    let all = rs.map(show).joined(separator: " ")
    for r in rs where !isInside(r, a) { return "A \(show(a)) から \(show(r)) がはみ出す" }
    for i in rs.indices {
        for j in rs.indices where i < j && overlapArea(rs[i], rs[j]) > 0 {
            return "A \(show(a)) で重なる: \(all)"
        }
    }
    let total = rs.map { $0.width * $0.height }.reduce(0, +)
    if total != a.width * a.height { return "A \(show(a)) に隙間: \(all)" }
    return nil
}

/// 2枚が1辺を共有して隣り合っているか（隙間も重なりも無く、接する辺の長さが同じ）。
private func adjacent(_ a: CGRect, _ b: CGRect) -> Bool {
    let sameRows = a.minY == b.minY && a.maxY == b.maxY
    let sameColumns = a.minX == b.minX && a.maxX == b.maxX
    return (sameRows && (a.maxX == b.minX || b.maxX == a.minX))
        || (sameColumns && (a.maxY == b.minY || b.maxY == a.minY))
}

// MARK: - 表示

private func num(_ v: CGFloat) -> String {
    v == v.rounded() && abs(v) < 1e9 ? String(Int(v)) : "\(v)"
}

private let screenNames: [(ScreenArea, String)] = [
    (mainScreen, "主画面"), (rightScreen, "右"), (upperScreen, "上"), (leftScreen, "左"),
    (lowerScreen, "下"), (portraitScreen, "縦長"), (squareScreen, "正方形"), (oddLeftScreen, "奇数幅"),
    (stackTop, "積んだ上"), (stackBottom, "積んだ下"),
]

private func screenName(_ s: ScreenArea) -> String {
    screenNames.first { $0.0 == s }?.1 ?? "frame\(show(s.frame))"
}

private func show(_ value: Any?) -> String {
    guard let value else { return "nil" }
    let mirror = Mirror(reflecting: value)
    if mirror.displayStyle == .optional {
        guard let inner = mirror.children.first?.value else { return "nil" }
        return show(inner)
    }
    if let r = value as? CGRect {
        return "(\(num(r.origin.x)), \(num(r.origin.y)), \(num(r.size.width)), \(num(r.size.height)))"
    }
    if let s = value as? ScreenArea { return screenName(s) }
    if mirror.displayStyle == .collection { return "[" + mirror.children.map { show($0.value) }.joined(separator: ", ") + "]" }
    return "\(value)"
}

// MARK: - 実行

@main
struct WindowLayoutTests {
    static var failures = 0

    /// 実際と期待を同じ型で比べる。
    static func check<T: Equatable>(_ name: String, _ actual: T, _ expected: T) {
        let ok = actual == expected
        if !ok { failures += 1 }
        print("\(ok ? "PASS" : "FAIL")  \(name)  期待=\(show(expected)) 実際=\(show(actual))")
    }

    /// 性質を全部の入力で確かめる。broken が理由を返した入力があれば失敗で、最初の1つを出す。
    /// 入力が 0 通りなら何も確かめていないので失敗にする。
    static func checkAll<C>(_ name: String, _ cases: [C], _ broken: (C) -> String?) {
        let found = cases.compactMap(broken)
        let ok = !cases.isEmpty && found.isEmpty
        if !ok { failures += 1 }
        let detail = cases.isEmpty ? "入力が 0 通り"
            : found.isEmpty ? "\(cases.count) 通り"
            : "\(cases.count) 通り中 \(found.count) 通りで崩れた。例: \(found[0])"
        print("\(ok ? "PASS" : "FAIL")  \(name)  \(detail)")
    }

    static func main() {
        constants()
        coordinates()
        containing()
        gridExamples()
        gridRounding()
        thirdsDirection()
        gridProperties()
        maximizeHeightAndCenter()
        largerAndSmaller()
        restore()
        displayOrder()
        displayMove()
        displayProperties()
        mappedAndNudged()
        history()

        print(failures == 0 ? "\nすべて通過" : "\n\(failures) 件 失敗")
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: 定数

    static func constants() {
        check("1回に変える量は 30", WindowAction.sizeStep, 30)
        check("smaller の下限は A の 0.25", WindowAction.minimumFraction, 0.25)
        check("端に付いているとみなす差は 5", WindowAction.edgeTolerance, 5)
    }

    // MARK: 座標

    static func coordinates() {
        let main = ScreenArea(
            cocoaFrame: box(0, 0, 2560, 1440), cocoaVisibleFrame: box(0, 64, 2560, 1346), primaryHeight: 1440)
        check("AppKit から: 主画面の visible は上にメニューバー 30・下に Dock 64（例）", main.visible, box(0, 30, 2560, 1346))
        check("AppKit から: 主画面の frame は左上が原点のまま", main.frame, box(0, 0, 2560, 1440))

        // 主画面の真上。上にメニューバー 25。
        let above = ScreenArea(
            cocoaFrame: box(0, 1440, 1920, 1080), cocoaVisibleFrame: box(0, 1440, 1920, 1055), primaryHeight: 1440)
        check("AppKit から: 主画面の真上の画面は y が負（例）", above.frame, box(0, -1080, 1920, 1080))
        check("AppKit から: visible にも frame と同じ式（真上の画面）", above.visible, box(0, -1055, 1920, 1055))

        // 主画面の下・右寄り。AppKit では y が負。上にメニューバー 25、下に Dock 50。
        let below = ScreenArea(
            cocoaFrame: box(300, -900, 1600, 900), cocoaVisibleFrame: box(300, -850, 1600, 825), primaryHeight: 1440)
        check("AppKit から: 主画面の下の画面は主画面の高さから始まる", below.frame, box(300, 1440, 1600, 900))
        check("AppKit から: x・幅・高さはそのまま（下の画面の visible）", below.visible, box(300, 1465, 1600, 825))
    }

    // MARK: どの画面の上にあるか

    static func containing() {
        let pair = [mainScreen, rightScreen]
        // 主画面と 160×400、右と 640×400 重なる。
        check("2枚にまたがるなら重なりの大きい画面（先頭でなくても）",
              ScreenArea.containing(box(2400, 100, 800, 400), in: pair), rightScreen)

        // frame で測ると 左 100×300・右 200×300。右は下半分が visible でないので、
        // visible で測ると右との重なりが 0 になり左が選ばれてしまう。
        let plain = ScreenArea(frame: box(0, 0, 1000, 1000), visible: box(0, 0, 1000, 1000))
        let shortVisible = ScreenArea(frame: box(1000, 0, 1000, 1000), visible: box(1000, 0, 1000, 500))
        check("重なりは visible でなく frame（画面全体）で測る",
              ScreenArea.containing(box(900, 600, 300, 300), in: [plain, shortVisible]), shortVisible)

        // 右の画面の右（x = 4480）より先。近いのは右の画面だが、決まりは「先頭」。
        check("どの画面とも重ならなければ先頭（近い画面ではなく）",
              ScreenArea.containing(box(5000, 100, 300, 300), in: pair), mainScreen)
        check("辺が接しているだけ（重なり 0）なら重ならない扱いで先頭",
              ScreenArea.containing(box(4480, 100, 300, 300), in: pair), mainScreen)
        check("ほとんど外でも少し重なればその画面",
              ScreenArea.containing(box(4470, 100, 300, 300), in: pair), rightScreen)
        // 右の画面の右下の角と 1×1 だけ重なる。
        check("重なりが 1×1 でもその画面",
              ScreenArea.containing(box(4479, 1079, 300, 300), in: pair), rightScreen)
        check("画面の配列が空なら nil", ScreenArea.containing(box(0, 0, 100, 100), in: []), nil)
    }

    // MARK: 格子（仕様の例と、表から手で計算した値）

    static func gridExamples() {
        check("leftHalf（例）", act(.leftHalf, floating), box(0, 30, 1280, 1346))
        check("firstThird（例）", act(.firstThird, floating), box(0, 30, 853, 1346))
        check("centerThird（例）", act(.centerThird, floating), box(853, 30, 854, 1346))
        check("lastThird（例）", act(.lastThird, floating), box(1707, 30, 853, 1346))
        check("centerTwoThirds は両側に 1/6 ずつ残す（例）", act(.centerTwoThirds, floating), box(427, 30, 1706, 1346))

        // 以下は A = (0, 30, 2560, 1346) に表を当てて手で計算した値。
        check("rightHalf", act(.rightHalf, floating), box(1280, 30, 1280, 1346))
        check("topHalf は上（y の小さい側）", act(.topHalf, floating), box(0, 30, 2560, 673))
        check("bottomHalf", act(.bottomHalf, floating), box(0, 703, 2560, 673))
        check("topLeft", act(.topLeft, floating), box(0, 30, 1280, 673))
        check("topRight", act(.topRight, floating), box(1280, 30, 1280, 673))
        check("bottomLeft", act(.bottomLeft, floating), box(0, 703, 1280, 673))
        check("bottomRight", act(.bottomRight, floating), box(1280, 703, 1280, 673))
        check("maximize は A そのもの", act(.maximize, floating), mainA)
        // 3 等分の境目は 0, 853, 1707, 2560。
        check("firstTwoThirds は境目 0〜1707", act(.firstTwoThirds, floating), box(0, 30, 1707, 1346))
        check("lastTwoThirds は境目 853〜2560", act(.lastTwoThirds, floating), box(853, 30, 1707, 1346))

        // ウィンドウが乗っている画面の visible を使う。
        let pair = [mainScreen, rightScreen]
        check("格子は右の画面に乗っていれば右の画面の中",
              act(.leftHalf, box(3000, 200, 500, 400), pair), box(2560, 25, 960, 1055))
        check("格子はまたがっていれば重なりの大きい画面の中",
              act(.leftHalf, box(2400, 100, 800, 400), pair), box(2560, 25, 960, 1055))
        check("格子はどの画面とも重ならなければ先頭の画面の中",
              act(.leftHalf, box(5000, 100, 300, 300), pair), box(0, 30, 1280, 1346))
    }

    // MARK: 格子の端数

    static func gridRounding() {
        // 高さ 1055 の半分は 527.5。四捨五入で上半分が 528、下半分が残りの 527。
        check("奇数の高さの topHalf は 0.5 を切り上げて 528",
              act(.topHalf, box(3000, 200, 500, 400), [mainScreen, rightScreen]), box(2560, 25, 1920, 528))

        // 始点 -1001・幅 1001。境目は -1001 + round(500.5) = -500。
        // 始点を足してから丸める（round(-500.5) = -501）と 1 ずれる。
        let odd = [mainScreen, oddLeftScreen]
        check("負の x・奇数幅の leftHalf は 501（始点を足す前に丸める）",
              act(.leftHalf, box(-900, 100, 300, 300), odd), box(-1001, 25, 501, 775))
        check("負の x・奇数幅の rightHalf は残りの 500",
              act(.rightHalf, box(-900, 100, 300, 300), odd), box(-500, 25, 500, 775))

        // 幅 1053 の 6 等分: 1053/6 = 175.5 → 176、1053×5/6 = 877.5 → 878。
        let s1053 = screenWith(visible: box(100, 25, 1053, 700))
        check("centerTwoThirds の 6 等分の端数も四捨五入（幅 1053）",
              act(.centerTwoThirds, box(500, 200, 100, 100), [s1053]), box(276, 25, 702, 700))
    }

    // MARK: 3分割の向き

    static func thirdsDirection() {
        // 縦長（1080×1895）は縦に分ける。1895 の 3 等分の境目は -375, 257, 888, 1520。
        let portrait = [mainScreen, portraitScreen]
        let onPortrait = box(2700, 0, 400, 400)
        check("縦長の画面の firstThird は上の 1/3（幅いっぱい）",
              act(.firstThird, onPortrait, portrait), box(2560, -375, 1080, 632))
        check("縦長の画面の centerThird", act(.centerThird, onPortrait, portrait), box(2560, 257, 1080, 631))
        check("縦長の画面の lastThird", act(.lastThird, onPortrait, portrait), box(2560, 888, 1080, 632))
        // 6 等分の境目は -375 + round(315.83) = -59 と -375 + round(1579.17) = 1204。
        check("縦長の画面の centerTwoThirds は上下に 1/6 ずつ残す",
              act(.centerTwoThirds, onPortrait, portrait), box(2560, -59, 1080, 1263))

        // 幅 = 高さは「横長」ではないので縦に分ける。
        check("正方形の画面は縦に分ける",
              act(.firstThird, box(-900, 100, 300, 300), [mainScreen, squareScreen]), box(-1000, 25, 1000, 333))
        check("幅が高さより 1 大きいだけでも横に分ける",
              act(.firstThird, box(100, 100, 100, 100), [screenWith(visible: box(0, 25, 1001, 1000))]),
              box(0, 25, 334, 1000))
        // frame は正方形だが visible（A）は横長。
        let squareFrame = ScreenArea(frame: box(0, 0, 1000, 1000), visible: box(0, 25, 1000, 975))
        check("向きは frame でなく visible の縦横で決める",
              act(.firstThird, box(100, 100, 100, 100), [squareFrame]), box(0, 25, 333, 975))
    }

    // MARK: 格子の性質

    static func gridProperties() {
        func grid(_ action: WindowAction, _ a: CGRect) -> CGRect? {
            act(action, box(a.minX + 1, a.minY + 1, 1, 1), [screenWith(visible: a)])
        }

        // ここが設計の判断。隣り合う領域は同じ境目を共有し、1pt の隙間も重なりも出さない。
        checkAll("3つの 1/3 は A を隙間も重なりもなく敷き詰める", sampleAreas) { a in
            tilingProblem([grid(.firstThird, a), grid(.centerThird, a), grid(.lastThird, a)], a)
        }
        checkAll("左半分と右半分は A を敷き詰める", sampleAreas) { a in
            tilingProblem([grid(.leftHalf, a), grid(.rightHalf, a)], a)
        }
        checkAll("上半分と下半分は A を敷き詰める", sampleAreas) { a in
            tilingProblem([grid(.topHalf, a), grid(.bottomHalf, a)], a)
        }
        checkAll("4つの 1/4 は A を敷き詰める", sampleAreas) { a in
            tilingProblem([grid(.topLeft, a), grid(.topRight, a), grid(.bottomLeft, a), grid(.bottomRight, a)], a)
        }
        checkAll("firstTwoThirds と lastThird は A を敷き詰める", sampleAreas) { a in
            tilingProblem([grid(.firstTwoThirds, a), grid(.lastThird, a)], a)
        }
        checkAll("firstThird と lastTwoThirds は A を敷き詰める", sampleAreas) { a in
            tilingProblem([grid(.firstThird, a), grid(.lastTwoThirds, a)], a)
        }

        let pairs = sampleAreas.flatMap { a in gridActions.map { (a, $0) } }
        checkAll("どの格子の配置も A の中に収まる", pairs) { a, action in
            guard let r = grid(action, a) else { return "\(action) が nil" }
            return isInside(r, a) ? nil : "A \(show(a)) の \(action) が \(show(r))"
        }
        checkAll("A が整数なら格子の配置も全部整数", pairs) { a, action in
            guard let r = grid(action, a) else { return "\(action) が nil" }
            return isIntegral(r) ? nil : "A \(show(a)) の \(action) が \(show(r))"
        }

        // 操作ごとに、仕様の境目の式で計算した値と照らす（奇数・3 で割り切れない・負の原点を含む）。
        for action in gridActions {
            checkAll("\(action) は境目の式どおり", sampleAreas) { a in
                let got = grid(action, a), want = specGrid(action, a)
                return got == want ? nil : "A \(show(a)) で 期待=\(show(want)) 実際=\(show(got))"
            }
        }

        let landscape = sampleAreas.filter { $0.width > $0.height }
        let upright = sampleAreas.filter { $0.width <= $0.height }
        checkAll("横長の画面では 3分割は横に分ける（高さは A いっぱい）",
                 landscape.flatMap { a in thirdActions.map { (a, $0) } }) { a, action in
            guard let r = grid(action, a) else { return "\(action) が nil" }
            return r.minY == a.minY && r.height == a.height ? nil : "A \(show(a)) の \(action) が \(show(r))"
        }
        checkAll("縦長・正方形の画面では 3分割は縦に分ける（幅は A いっぱい）",
                 upright.flatMap { a in thirdActions.map { (a, $0) } }) { a, action in
            guard let r = grid(action, a) else { return "\(action) が nil" }
            return r.minX == a.minX && r.width == a.width ? nil : "A \(show(a)) の \(action) が \(show(r))"
        }

        // 主画面の上のいろいろな位置・大きさのウィンドウ。はみ出したもの・A より大きいものも混ぜる。
        let windows = [
            box(0, 0, 10, 10), floating, mainA, box(2000, 1000, 2000, 2000),
            box(-100, -100, 5000, 5000), box(1279, 29, 3, 3),
        ]
        checkAll("格子の配置はウィンドウの位置や大きさに依らない", gridActions) { action in
            let results = windows.map { act(action, $0) }
            return Set(results.map(show)).count == 1 ? nil : "\(action): \(results.map(show))"
        }
        checkAll("格子の配置は restore 引数に左右されない", gridActions) { action in
            let with = act(action, floating, restore: box(123, 456, 789, 321)), without = act(action, floating)
            return with == without ? nil : "\(action): \(show(with)) と \(show(without))"
        }

        // 仕様には「画面の配列が空なら containing は nil」とだけある。A が無いので nil だと読んだ。
        checkAll("画面が1枚も無ければ restore 以外は nil（要確認）",
                 WindowAction.allCases.filter { $0 != .restore }) { action in
            let r = act(action, floating, [])
            return r == nil ? nil : "\(action) が \(show(r))"
        }
    }

    // MARK: maximizeHeight・center

    static func maximizeHeightAndCenter() {
        check("maximizeHeight は x と幅そのまま・縦は A いっぱい", act(.maximizeHeight, floating), box(500, 30, 800, 1346))
        check("maximizeHeight は乗っている画面の A を使う",
              act(.maximizeHeight, box(3000, 200, 500, 400), [mainScreen, rightScreen]), box(3000, 25, 500, 1055))

        // x = 0 + round(1760 / 2) = 880、y = 30 + round(746 / 2) = 403。
        check("center は大きさそのままで真ん中", act(.center, box(100, 200, 800, 600)), box(880, 403, 800, 600))
        // (2560 - 801) / 2 = 879.5 → 880、(1346 - 601) / 2 = 372.5 → 373。
        check("center の余りの 0.5 は四捨五入", act(.center, box(100, 200, 801, 601)), box(880, 403, 801, 601))
        check("center は A より広いウィンドウの幅を A に縮める",
              act(.center, box(-50, 200, 3000, 600)), box(0, 403, 2560, 600))
        check("center は A より高いウィンドウの高さを A に縮める",
              act(.center, box(100, 0, 800, 2000)), box(880, 30, 800, 1346))
        // x = 2560 + round(1420 / 2) = 3270、y = 25 + round(327.5) = 353。
        check("center は乗っている画面の A を使う",
              act(.center, box(3000, 200, 500, 400), [mainScreen, rightScreen]), box(3270, 353, 500, 400))

        // 始点 -1001 + round(250.5) = -750。始点を足してから丸める（round(-750.5) = -751）と 1 ずれる。
        check("centered(in:) は負の原点でも余りの側で四捨五入",
              CGSize(width: 500, height: 300).centered(in: oddLeftScreen.visible), box(-750, 263, 500, 300))
        check("centered(in:) は A より大きい大きさを A に縮める",
              CGSize(width: 3000, height: 2000).centered(in: mainA), mainA)

        let cases = roomyAreas.flatMap { a in (windowsInside(a) + [box(a.minX - 50, a.minY, a.width + 100, 90)]).map { (a, $0) } }
        checkAll("center の結果は A に収まる", cases) { a, w in
            guard let r = act(.center, w, [screenWith(visible: a)]) else { return "nil" }
            return isInside(r, a) ? nil : "A \(show(a)) の \(show(w)) が \(show(r))"
        }
        checkAll("center を2回しても1回と同じ", cases) { a, w in
            let s = [screenWith(visible: a)]
            guard let once = act(.center, w, s) else { return "nil" }
            let twice = act(.center, once, s)
            return twice == once ? nil : "\(show(w)) → \(show(once)) → \(show(twice))"
        }
    }

    // MARK: larger / smaller

    static func largerAndSmaller() {
        // 仕様の例（A = (0, 30, 2560, 1346)）。
        let leftHalf = box(0, 30, 1280, 1346), rightHalf = box(1280, 30, 1280, 1346)
        check("左半分の larger は右へ伸びる（例）", act(.larger, leftHalf), box(0, 30, 1310, 1346))
        check("左半分の smaller は右端が縮む（例）", act(.smaller, leftHalf), box(0, 30, 1250, 1346))
        check("右半分の larger は左へ伸びる（例）", act(.larger, rightHalf), box(1250, 30, 1310, 1346))
        check("最大化の smaller は四方から縮む（例）", act(.smaller, mainA), box(15, 45, 2530, 1316))
        check("最大化の larger は変わらない（例）", act(.larger, mainA), mainA)
        check("浮いているウィンドウの larger は四方へ 15 ずつ（例）", act(.larger, floating), box(485, 285, 830, 630))
        check("浮いているウィンドウの smaller は四方から 15 ずつ（例）", act(.smaller, floating), box(515, 315, 770, 570))
        check("smaller で幅が下限を割るなら nil（例: 630 < 640）", act(.smaller, box(0, 30, 660, 1346)), nil)

        // 以下は表から手で計算した値。
        check("右半分の smaller は右端に付いたまま縮む", act(.smaller, rightHalf), box(1310, 30, 1250, 1346))
        check("上半分の smaller は幅いっぱいのまま、上に付いて縮む",
              act(.smaller, box(0, 30, 2560, 673)), box(0, 30, 2560, 643))
        check("下半分の larger は下に付いたまま上へ伸びる",
              act(.larger, box(0, 703, 2560, 673)), box(0, 673, 2560, 703))
        check("横は終点側・縦は始点側と、縦横を別々に決める（larger）",
              act(.larger, box(1760, 30, 800, 600)), box(1730, 30, 830, 630))
        check("横は終点側・縦は始点側と、縦横を別々に決める（smaller）",
              act(.smaller, box(1760, 30, 800, 600)), box(1790, 30, 770, 570))
        check("横が両端に付いていても四辺でなければ、smaller で幅は A いっぱいのまま",
              act(.smaller, box(0, 300, 2560, 600)), box(0, 315, 2560, 570))

        // 端への付き方の許容差 5。
        check("端から 5 離れていても始点に付いている（smaller は A の始点に揃える）",
              act(.smaller, box(5, 30, 1280, 1346)), box(0, 30, 1250, 1346))
        check("端から 6 離れていれば付いていない（smaller は 15 内へ）",
              act(.smaller, box(6, 30, 1280, 1346)), box(21, 30, 1250, 1346))
        check("端から 3 はみ出していても始点に付いている",
              act(.smaller, box(-3, 30, 1280, 1346)), box(0, 30, 1250, 1346))
        check("縦の両端が許容差の中なら、smaller で縦は A いっぱいに揃う",
              act(.smaller, box(0, 33, 1280, 1340)), box(0, 30, 1250, 1346))
        check("larger は両端が許容差の中なら A いっぱい",
              act(.larger, box(3, 32, 2555, 1342)), mainA)
        check("smaller は四辺が許容差の中なら最大化とみなし、四方から縮む",
              act(.smaller, box(2, 32, 2556, 1342)), box(17, 47, 2526, 1312))

        // larger でどこにも付いていないときの A の中への寄せ。
        check("larger で右へはみ出す分は左へ寄せる", act(.larger, box(1750, 300, 800, 600)), box(1730, 285, 830, 630))
        check("larger で上へはみ出す分は下へ寄せる", act(.larger, box(500, 40, 800, 600)), box(485, 30, 830, 630))
        check("larger の新しい長さは A の長さまで", act(.larger, box(10, 300, 2540, 600)), box(0, 285, 2560, 630))
        check("larger で終点側に付いていて A の長さまで伸びるなら始点は A の始点",
              act(.larger, box(20, 300, 2540, 600)), box(0, 285, 2560, 630))

        // 下限は floor(A × 0.25): 幅 floor(640) = 640、高さ floor(336.5) = 336。
        check("smaller で幅がちょうど下限なら縮む", act(.smaller, box(0, 30, 670, 1346)), box(0, 30, 640, 1346))
        check("smaller で高さがちょうど floor(336.5) = 336 なら縮む",
              act(.smaller, box(500, 300, 800, 366)), box(515, 315, 770, 336))
        check("smaller で高さが 335 になるなら nil", act(.smaller, box(500, 300, 800, 365)), nil)

        // 1280 - 30 × 21 = 650 までは縮み、22 回目は 620 < 640 で止まる。
        var steps = 0
        var current: CGRect? = leftHalf
        while let w = current, steps < 200, let next = act(.smaller, w) { current = next; steps += 1 }
        check("左半分に smaller を繰り返すと 21 回で止まる", steps, 21)

        check("浮いているウィンドウは larger → smaller で元に戻る",
              act(.larger, floating).flatMap { act(.smaller, $0) }, floating)

        // いろいろな A と、その中のウィンドウで。
        let cases = roomyAreas.flatMap { a in windowsInside(a).map { (a, $0) } }
        checkAll("larger の結果は A に収まる", cases) { a, w in
            guard let r = act(.larger, w, [screenWith(visible: a)]) else { return "A \(show(a)) の \(show(w)) で nil" }
            return isInside(r, a) ? nil : "A \(show(a)) の \(show(w)) が \(show(r))"
        }
        // A からはみ出したウィンドウでも、端に揃えるか A の中へ寄せるので、結果は A に収まる。
        let outside = roomyAreas.flatMap { a in
            [
                box(a.minX - 100, a.minY + 50, 400, 300), box(a.maxX - 200, a.maxY - 100, 400, 300),
                box(a.minX - 50, a.minY - 50, a.width + 100, a.height + 100),
            ].map { (a, $0) }
        }
        checkAll("A からはみ出したウィンドウの larger も A に収まる", outside) { a, w in
            guard let r = act(.larger, w, [screenWith(visible: a)]) else { return "A \(show(a)) の \(show(w)) で nil" }
            return isInside(r, a) ? nil : "A \(show(a)) の \(show(w)) が \(show(r))"
        }
        checkAll("larger で縦横とも縮まない", cases) { a, w in
            guard let r = act(.larger, w, [screenWith(visible: a)]) else { return "A \(show(a)) の \(show(w)) で nil" }
            return r.width >= w.width && r.height >= w.height ? nil : "A \(show(a)) の \(show(w)) が \(show(r))"
        }
        checkAll("smaller の結果は A に収まる", cases) { a, w in
            guard let r = act(.smaller, w, [screenWith(visible: a)]) else { return nil }
            return isInside(r, a) ? nil : "A \(show(a)) の \(show(w)) が \(show(r))"
        }
        checkAll("smaller の結果は下限 floor(A × 0.25) を割らない", cases) { a, w in
            guard let r = act(.smaller, w, [screenWith(visible: a)]) else { return nil }
            let ok = r.width >= (a.width * 0.25).rounded(.down) && r.height >= (a.height * 0.25).rounded(.down)
            return ok ? nil : "A \(show(a)) の \(show(w)) が \(show(r))"
        }
    }

    // MARK: restore

    static func restore() {
        // 別の画面の上の枠でも、そのまま返す。
        let saved = box(3000, 200, 777, 333)
        check("restore は restore 引数をそのまま返す", act(.restore, floating, restore: saved), saved)
        check("restore は restore 引数が nil なら nil", act(.restore, floating, restore: nil), nil)
    }

    // MARK: 画面の並び

    static func displayOrder() {
        check("並びは同じ段なら左から右（例の2枚を逆に渡す）",
              ScreenArea.ordered([rightScreen, mainScreen]), [mainScreen, rightScreen])
        check("縦に重なっていれば、ずれていても同じ段",
              ScreenArea.ordered([mainScreen, leftScreen]), [leftScreen, mainScreen])
        // 上の画面の下の辺 = 主画面の上の辺（maxY ≤ minY）。同じ段とみなすと x の順で後ろに来る。
        let touching = ScreenArea(frame: box(1000, -1080, 1920, 1080), visible: box(1000, -1055, 1920, 1055))
        check("辺が接しているだけなら別の段（上の段が先）",
              ScreenArea.ordered([mainScreen, touching]), [touching, mainScreen])
        check("上の段が先。右寄りの上の画面も左の画面より先（2段）",
              ScreenArea.ordered([mainScreen, rightScreen, upperScreen, leftScreen]),
              [upperScreen, leftScreen, mainScreen, rightScreen])
        check("3段",
              ScreenArea.ordered([lowerScreen, mainScreen, rightScreen, upperScreen, leftScreen]),
              [upperScreen, leftScreen, mainScreen, rightScreen, lowerScreen])

        let four = [mainScreen, rightScreen, upperScreen, leftScreen]
        let expected = [upperScreen, leftScreen, mainScreen, rightScreen]
        checkAll("並びは渡す順に依らない（4枚の全部の並べ方）", permutations(four)) { input in
            let got = ScreenArea.ordered(input)
            return got == expected ? nil : "\(show(input)) → \(show(got))"
        }
        checkAll("並びは渡した画面を1枚ずつそのまま持つ", layouts) { input in
            let got = ScreenArea.ordered(input)
            let same = got.count == input.count && input.allSatisfy { s in got.filter { $0 == s }.count == 1 }
            return same ? nil : "\(show(input)) → \(show(got))"
        }
        checkAll("並べたものをもう一度並べても同じ", layouts) { input in
            let once = ScreenArea.ordered(input)
            let twice = ScreenArea.ordered(once)
            return twice == once ? nil : "\(show(once)) → \(show(twice))"
        }

        // 段を組み立てて作った並び。段の中の画面は互いに縦に重なり（y が 0〜299 ずれ、高さ 900 以上）、
        // 段どうしは重ならない（段の間隔 2000）。組み立てた順（上の段から、段の中は左から）が期待する並び。
        // 段の中の画面は、接しているものと少し離れているものを混ぜる。種を固定しているので毎回同じ。
        var seed: UInt64 = 20_260_923
        func draw(_ n: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((seed >> 33) % UInt64(n))
        }
        var built: [([ScreenArea], [ScreenArea])] = []
        for _ in 0..<60 {
            var layout: [ScreenArea] = []
            for row in 0..<(1 + draw(3)) {
                let base = CGFloat(row * 2000 - 3000)
                var x = CGFloat(draw(3000) - 4000)
                for _ in 0..<(1 + draw(3)) {
                    let w = CGFloat(800 + draw(2000)), h = CGFloat(900 + draw(600)), y = base + CGFloat(draw(300))
                    layout.append(ScreenArea(frame: box(x, y, w, h), visible: box(x, y + 25, w, h - 25)))
                    x += w + (draw(3) == 0 ? 0 : CGFloat(draw(500)))
                }
            }
            var shuffled = layout
            for i in shuffled.indices.reversed() where i > 0 { shuffled.swapAt(i, draw(i + 1)) }
            built.append((layout, layout.reversed()))
            built.append((layout, shuffled))
        }
        // 重ならない画面（辺で接するのは可）を 80 刻みでばらばらに置いた並び。段が1通りに決まるものだけを使い、
        // 期待する並びは仕様の文（specOrder）から計算する。上の組み立てでは出てこない、
        // 段の中で高さの範囲が入れ子になった画面や、段の中で接している画面が多く出る。
        var scattered = 0
        while scattered < 3000 {
            var frames: [CGRect] = []
            for _ in 0..<(2 + draw(3)) {
                let f = box(CGFloat(draw(61) - 30) * 80, CGFloat(draw(61) - 30) * 80,
                            CGFloat(1 + draw(25)) * 80, CGFloat(1 + draw(25)) * 80)
                if !frames.contains(where: { overlapArea($0, f) > 0 }) { frames.append(f) }
            }
            let input = frames.map { ScreenArea(frame: $0, visible: $0) }
            guard input.count > 1, let expected = specOrder(input) else { continue }
            built.append((expected, input))
            scattered += 1
        }
        checkAll("上の段から下の段へ、同じ段は左から（組み立てた並び・ばらばらに置いた並び）", built) { expected, input in
            let got = ScreenArea.ordered(input)
            return got == expected ? nil
                : "渡した=\(input.map { show($0.frame) }) 期待=\(expected.map { show($0.frame) }) 実際=\(got.map { show($0.frame) })"
        }
    }

    // MARK: 画面の移動（値）

    static func displayMove() {
        let pair = [mainScreen, rightScreen]
        let leftHalf = box(0, 30, 1280, 1346)
        check("nextDisplay で左半分は隣の画面の左半分（例）", act(.nextDisplay, leftHalf, pair), box(2560, 25, 960, 1055))
        check("2枚なら previousDisplay も隣へ（最初の前は最後）",
              act(.previousDisplay, leftHalf, pair), box(2560, 25, 960, 1055))
        check("最後の次は最初", act(.nextDisplay, box(2560, 25, 960, 1055), pair), leftHalf)
        check("画面が1枚なら nextDisplay は nil", act(.nextDisplay, leftHalf, [mainScreen]), nil)
        check("画面が1枚なら previousDisplay は nil", act(.previousDisplay, leftHalf, [mainScreen]), nil)

        // 並びは [上, 左, 主画面, 右]。
        let four = [mainScreen, rightScreen, upperScreen, leftScreen]
        func screenAfter(_ action: WindowAction, from window: CGRect) -> ScreenArea? {
            act(action, window, four).flatMap { ScreenArea.containing($0, in: four) }
        }
        check("2段: 主画面の次は右", screenAfter(.nextDisplay, from: leftHalf), rightScreen)
        check("2段: 右の次は上の段の画面（巡回）", screenAfter(.nextDisplay, from: box(3000, 200, 500, 400)), upperScreen)
        check("2段: 上の段の画面の次は下の段の左端", screenAfter(.nextDisplay, from: box(2000, -800, 500, 400)), leftScreen)
        check("2段: 上の段の画面の前は右（巡回）", screenAfter(.previousDisplay, from: box(2000, -800, 500, 400)), rightScreen)
        check("2段: 主画面の前は左の画面の左半分",
              act(.previousDisplay, leftHalf, four), box(-1920, 385, 960, 1055))

        // 主画面と 160×400、右と 640×400 重なる → 右の上にある → 次は主画面。
        check("またがるウィンドウは重なりの大きい画面から次へ",
              act(.nextDisplay, box(2400, 100, 800, 400), pair).flatMap { ScreenArea.containing($0, in: pair) },
              mainScreen)
        check("どの画面とも重ならないウィンドウは先頭の画面から次へ",
              act(.nextDisplay, box(-5000, 100, 300, 300), pair).flatMap { ScreenArea.containing($0, in: pair) },
              rightScreen)

        // 辺ごとに写して丸める。上辺 38.32 → 38、下辺 446.69 → 447 で高さ 409。
        // 高さを 521 × 1055 / 1346 = 408.36 → 408 と丸めると 1 ずれる。
        check("移すときは大きさでなく四辺それぞれを丸める",
              act(.nextDisplay, box(200, 47, 800, 521), pair), box(2710, 38, 600, 409))
        // 右へはみ出していたウィンドウは写すと x = 4060 で右隣の画面の右（4480）を越えるので押し戻す。
        check("移したあと行き先の visible の中へ押し戻す",
              act(.nextDisplay, box(2000, 100, 700, 500), pair), box(3955, 80, 525, 392))
    }

    // MARK: 画面の移動（性質）

    static func displayProperties() {
        /// 並びの中で、ある画面の次（前）の画面。期待値を作るために並びの定義から引く。
        func neighbor(_ screen: ScreenArea, in layout: [ScreenArea], step: Int) -> ScreenArea {
            let order = ScreenArea.ordered(layout)
            let i = order.firstIndex(of: screen)!
            return order[(i + step + order.count) % order.count]
        }
        let moves: [(WindowAction, Int)] = [(.nextDisplay, 1), (.previousDisplay, -1)]
        let placed = layouts.flatMap { layout in layout.map { (layout, $0) } }

        // ここが設計の判断。大きさではなく辺を写すので、隣り合っていた2枚は移しても隣り合ったまま。
        let adjacentPairs: [(WindowAction, WindowAction)] = [
            (.leftHalf, .rightHalf), (.topHalf, .bottomHalf), (.topLeft, .topRight), (.topLeft, .bottomLeft),
            (.bottomLeft, .bottomRight), (.topRight, .bottomRight), (.firstThird, .centerThird),
            (.centerThird, .lastThird), (.firstTwoThirds, .lastThird), (.firstThird, .lastTwoThirds),
        ]
        let pairCases = placed.flatMap { layout, screen -> [([ScreenArea], CGRect, CGRect)] in
            let v = screen.visible
            let a = box(v.minX + 137, v.minY + 91, 411, 333)
            return adjacentPairs.map { (layout, specGrid($0.0, v), specGrid($0.1, v)) } + [
                (layout, a, box(a.maxX, a.minY, 297, 333)), // 右隣
                (layout, a, box(a.minX, a.maxY, 411, 250)), // 下隣
            ]
        }
        for (action, _) in moves {
            checkAll("隣り合う2枚は \(action) で移しても隣り合ったまま", pairCases) { layout, a, b in
                guard layout.count > 1 else { return nil }
                guard let ma = act(action, a, layout), let mb = act(action, b, layout) else { return "nil" }
                return adjacent(ma, mb) ? nil : "\(show(a)) \(show(b)) → \(show(ma)) \(show(mb))"
            }
        }

        // 幅が偶数の画面だけの並び（左半分の右辺がちょうど半分になる）。
        let evenWidths = [mainScreen, rightScreen, upperScreen, leftScreen, lowerScreen]
        let evenCases = evenWidths.flatMap { s in moves.map { (s, $0) } }
        checkAll("左半分は大きさの違う画面へ移しても左半分", evenCases) { screen, move in
            let dest = neighbor(screen, in: evenWidths, step: move.1)
            let got = act(move.0, specGrid(.leftHalf, screen.visible), evenWidths)
            let want = specGrid(.leftHalf, dest.visible)
            return got == want ? nil : "\(screenName(screen)) → \(screenName(dest)) で 期待=\(show(want)) 実際=\(show(got))"
        }
        checkAll("最大化は移しても行き先で最大化", placed.flatMap { p in moves.map { (p.0, p.1, $0) } }) {
            layout, screen, move in
            guard layout.count > 1 else { return nil }
            let dest = neighbor(screen, in: layout, step: move.1)
            let got = act(move.0, screen.visible, layout)
            return got == dest.visible ? nil : "\(screenName(screen)) → \(screenName(dest)) が \(show(got))"
        }

        let windowCases = placed.flatMap { layout, screen in
            (gridActions.map { specGrid($0, screen.visible) } + [box(screen.visible.midX - 150, screen.visible.midY - 100, 300, 200)])
                .map { (layout, screen, $0) }
        }
        checkAll("nextDisplay → previousDisplay で元の画面に戻る", windowCases) { layout, screen, w in
            let back = act(.nextDisplay, w, layout).flatMap { act(.previousDisplay, $0, layout) }
            let on = back.flatMap { ScreenArea.containing($0, in: layout) }
            return on == screen ? nil : "\(screenName(screen)) の \(show(w)) が \(show(back))（\(show(on))）"
        }
        checkAll("previousDisplay → nextDisplay で元の画面に戻る", windowCases) { layout, screen, w in
            let back = act(.previousDisplay, w, layout).flatMap { act(.nextDisplay, $0, layout) }
            let on = back.flatMap { ScreenArea.containing($0, in: layout) }
            return on == screen ? nil : "\(screenName(screen)) の \(show(w)) が \(show(back))（\(show(on))）"
        }
        checkAll("nextDisplay を画面の数だけ続けると並びの順に全部を回って戻る", placed) { layout, start in
            var w = start.visible, visited: [ScreenArea] = []
            for _ in layout {
                guard let moved = act(.nextDisplay, w, layout), let on = ScreenArea.containing(moved, in: layout)
                else { return "\(screenName(start)) から \(visited.count) 回目で nil" }
                visited.append(on)
                w = moved
            }
            let want = (1...layout.count).map { neighbor(start, in: layout, step: $0) }
            return visited == want ? nil : "\(screenName(start)) から 期待=\(show(want)) 実際=\(show(visited))"
        }
    }

    // MARK: mapped・nudged

    static func mappedAndNudged() {
        let from = mainA, to = rightScreen.visible
        check("mapped は左半分を行き先の左半分へ（例の数値）", box(0, 30, 1280, 1346).mapped(from: from, to: to),
              box(2560, 25, 960, 1055))
        check("mapped は四辺それぞれを丸める", box(200, 47, 800, 521).mapped(from: from, to: to), box(2710, 38, 600, 409))
        check("mapped は押し戻しまで含む", box(2000, 100, 700, 500).mapped(from: from, to: to), box(3955, 80, 525, 392))
        // 1.5 倍に写す。辺 3 → 4.5 → 5、辺 103 → 154.5 → 155。偶数への丸めなら 4 と 154 になる。
        check("mapped の辺の 0.5 は四捨五入（0 から遠い側）",
              box(3, 3, 100, 100).mapped(from: box(0, 0, 1000, 1000), to: box(0, 0, 1500, 1500)), box(5, 5, 150, 150))
        // 実際に直した入力（2026-09-23）。座標そのものを丸めていた版では、右辺が -500.5 を
        // 0 から遠い側へ丸めて -501 になり、行き先の格子の左半分（境目 -1001 + round(500.5) = -500）と
        // 1pt ずれていた。丸めるのは行き先の始点からの距離で、格子の境目の式と同じ形にする。
        check("始点が負の奇数幅の画面へ移した左半分は、その画面の格子の左半分と一致する",
              box(0, 30, 1280, 1346).mapped(from: mainA, to: oddLeftScreen.visible),
              act(.leftHalf, oddLeftScreen.visible, [oddLeftScreen]))
        let identity = roomyAreas.flatMap { a in windowsInside(a).map { (a, $0) } }
        checkAll("同じ枠へ mapped するとそのまま", identity) { a, w in
            let got = w.mapped(from: a, to: a)
            return got == w ? nil : "A \(show(a)) の \(show(w)) が \(show(got))"
        }

        check("nudged: 収まっていれば動かない", box(100, 100, 400, 300).nudged(into: mainA), box(100, 100, 400, 300))
        check("nudged: 右にはみ出していれば左へ", box(2400, 100, 400, 300).nudged(into: mainA), box(2160, 100, 400, 300))
        check("nudged: 下にはみ出していれば上へ", box(100, 1200, 400, 300).nudged(into: mainA), box(100, 1076, 400, 300))
        check("nudged: 左にはみ出していれば右へ", box(-50, 100, 400, 300).nudged(into: mainA), box(0, 100, 400, 300))
        check("nudged: 上にはみ出していれば下へ（メニューバーの下へ）",
              box(100, 0, 400, 300).nudged(into: mainA), box(100, 30, 400, 300))
        // ここが設計の判断。タイトルバーを画面の外に出さないため、収まらないときは左上を揃える。
        check("nudged: bounds より広ければ左端を揃える", box(100, 100, 3000, 300).nudged(into: mainA), box(0, 100, 3000, 300))
        check("nudged: bounds より高ければ上端を揃える", box(100, 500, 400, 2000).nudged(into: mainA), box(100, 30, 400, 2000))

        // bounds のまわりの色々な位置に、収まる大きさと収まらない大きさを置く。
        let bounds = [mainA, oddLeftScreen.visible, portraitScreen.visible]
        let offsets: [CGFloat] = [-5000, -301, -1, 0, 1, 57, 699, 5000]
        let rects = bounds.flatMap { b in
            [(100, 100), (400, 300), (b.width, b.height), (b.width + 1, 50), (60, b.height + 7)].flatMap { size in
                offsets.flatMap { dx in offsets.map { dy in (b, box(b.minX + dx, b.minY + dy, size.0, size.1)) } }
            }
        }
        let fits = rects.filter { b, r in r.width <= b.width && r.height <= b.height }
        let tooBig = rects.filter { b, r in r.width > b.width || r.height > b.height }
        checkAll("nudged: 収まる大きさなら結果は bounds の中", fits) { b, r in
            let got = r.nudged(into: b)
            return isInside(got, b) ? nil : "\(show(r)) → \(show(got))"
        }
        checkAll("nudged: 大きさは変えない", rects) { b, r in
            let got = r.nudged(into: b)
            return got.size == r.size ? nil : "\(show(r)) → \(show(got))"
        }
        checkAll("nudged: 2回しても1回と同じ", rects) { b, r in
            let once = r.nudged(into: b), twice = once.nudged(into: b)
            return twice == once ? nil : "\(show(r)) → \(show(once)) → \(show(twice))"
        }
        checkAll("nudged: 収まらない辺は左・上を bounds に揃える", tooBig) { b, r in
            let got = r.nudged(into: b)
            let xOK = r.width <= b.width || got.minX == b.minX
            let yOK = r.height <= b.height || got.minY == b.minY
            return xOK && yOK ? nil : "\(show(r)) → \(show(got))"
        }
    }

    // MARK: WindowHistory

    static func history() {
        let first = box(100, 100, 800, 600) // 利用者が置いていた位置
        let leftHalf = box(0, 30, 1280, 1346)
        let rightHalf = box(1280, 30, 1280, 1346)
        let byHand = box(300, 200, 700, 500)

        check("記録していないキーは nil", WindowHistory<String>().restoreFrame(for: "safari"), nil)

        var h = WindowHistory<String>()
        h.recordMove(of: "safari", from: first, to: leftHalf)
        check("初めて動かしたら戻す先は動かす前の位置", h.restoreFrame(for: "safari"), first)

        // ここが設計の判断。One で続けて動かしても、最初の位置に戻れる。
        h = WindowHistory<String>()
        h.recordMove(of: "safari", from: first, to: leftHalf)
        h.recordMove(of: "safari", from: leftHalf, to: rightHalf)
        check("One で続けて動かしたら戻す先は最初の位置のまま", h.restoreFrame(for: "safari"), first)
        h.recordMove(of: "safari", from: rightHalf, to: leftHalf)
        check("3回続けても最初の位置のまま", h.restoreFrame(for: "safari"), first)

        h = WindowHistory<String>()
        h.recordMove(of: "safari", from: first, to: leftHalf)
        h.recordMove(of: "safari", from: box(1, 29, 1281, 1345), to: rightHalf)
        check("前回の行き先と今回の元が 1 ずつずれていても続きとみなす", h.restoreFrame(for: "safari"), first)

        h = WindowHistory<String>()
        h.recordMove(of: "safari", from: first, to: leftHalf)
        h.recordMove(of: "safari", from: box(0, 30, 1282, 1346), to: rightHalf)
        check("幅が 2 違えば手で動かしたとみなし、今回の元を戻す先にする",
              h.restoreFrame(for: "safari"), box(0, 30, 1282, 1346))
        // x・y・高さも、それぞれ 1 つだけが 2 違えば手で動かしたとみなす。
        for (what, moved) in [("x", box(2, 30, 1280, 1346)), ("y", box(0, 32, 1280, 1346)), ("高さ", box(0, 30, 1280, 1344))] {
            h = WindowHistory<String>()
            h.recordMove(of: "safari", from: first, to: leftHalf)
            h.recordMove(of: "safari", from: moved, to: rightHalf)
            check("\(what) だけが 2 違っても手で動かしたとみなす", h.restoreFrame(for: "safari"), moved)
        }

        // ここが設計の判断。手で整えた位置を新しい出発点にする。
        h = WindowHistory<String>()
        h.recordMove(of: "safari", from: first, to: leftHalf)
        h.recordMove(of: "safari", from: byHand, to: rightHalf)
        check("手で動かしてから One で動かしたら戻す先は手で置いた位置", h.restoreFrame(for: "safari"), byHand)
        h.recordMove(of: "safari", from: rightHalf, to: leftHalf)
        check("手で置いた位置から続けて動かしても戻す先は手で置いた位置", h.restoreFrame(for: "safari"), byHand)

        h = WindowHistory<String>()
        h.recordMove(of: "safari", from: first, to: leftHalf)
        h.recordMove(of: "mail", from: leftHalf, to: rightHalf)
        check("別のキーの行き先は続きとみなさない", h.restoreFrame(for: "mail"), leftHalf)

        h = WindowHistory<String>()
        h.recordMove(of: "safari", from: first, to: leftHalf)
        h.recordMove(of: "mail", from: byHand, to: rightHalf)
        h.forget("safari")
        check("forget したキーは nil", h.restoreFrame(for: "safari"), nil)
        check("forget は他のキーに影響しない", h.restoreFrame(for: "mail"), byHand)

        h = WindowHistory<String>()
        h.recordMove(of: "safari", from: first, to: leftHalf)
        h.forget("safari")
        h.recordMove(of: "safari", from: leftHalf, to: rightHalf)
        check("forget のあとは初めて扱い（前の行き先から続けても前の元には戻らない）",
              h.restoreFrame(for: "safari"), leftHalf)

        // limit を超えたら、最後に記録したのが一番古いキーから捨てる。
        var small = WindowHistory<String>(limit: 3)
        for key in ["a", "b", "c", "d"] { small.recordMove(of: key, from: first, to: leftHalf) }
        check("limit を超えたら一番古いキーを捨てる", small.restoreFrame(for: "a"), nil)
        check("limit を超えても新しいほうの limit 個は残る",
              ["b", "c", "d"].map { small.restoreFrame(for: $0) }, [first, first, first])

        small = WindowHistory<String>(limit: 3)
        small.recordMove(of: "a", from: first, to: leftHalf)
        small.recordMove(of: "b", from: first, to: leftHalf)
        small.recordMove(of: "c", from: first, to: leftHalf)
        small.recordMove(of: "a", from: leftHalf, to: rightHalf) // a を記録し直す（続きなので戻す先は first のまま）
        small.recordMove(of: "d", from: first, to: leftHalf)
        check("記録し直したキーは一番新しくなり、次に古いキーが捨てられる", small.restoreFrame(for: "b"), nil)
        check("記録し直したキーは残り、戻す先も引き継いだまま", small.restoreFrame(for: "a"), first)

        var full = WindowHistory<Int>()
        for key in 0..<50 { full.recordMove(of: key, from: first, to: leftHalf) }
        check("既定の limit は 50（50 個なら最初のキーも残る）", full.restoreFrame(for: 0), first)
        full.recordMove(of: 50, from: first, to: leftHalf)
        check("既定の limit は 50（51 個目で最初のキーを捨てる）", full.restoreFrame(for: 0), nil)
    }
}

/// 並べ方を全部。
private func permutations<T>(_ items: [T]) -> [[T]] {
    guard items.count > 1 else { return [items] }
    return items.indices.flatMap { i -> [[T]] in
        var rest = items
        let head = rest.remove(at: i)
        return permutations(rest).map { [head] + $0 }
    }
}
