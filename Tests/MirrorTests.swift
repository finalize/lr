import Foundation

// 鏡のうち、ノッチの位置・窓の置き場所・画質の読み戻しを、画面もカメラも無しで確かめる。
//
// 開発機（Mac Studio）にはノッチが無い。MacBook に持っていく前に
// 数字の部分だけはここで潰しておく。

private var failures = 0

private func check<T: Equatable>(_ name: String, _ actual: T, _ expected: T) {
    let ok = actual == expected
    if !ok { failures += 1 }
    print("\(ok ? "PASS" : "FAIL")  \(name)  期待=\(expected) 実際=\(actual)")
}

@main
struct MirrorTests {
    static func main() {
        // MARK: ノッチ

        // MacBook Pro 14 インチの既定の解像度（1512×982pt）を想定した値。
        // 左右の領域の幅（654pt）とノッチの高さ（32pt）は計算を確かめるための仮の数字で、
        // 実機の値は MacBook で起動したときのログ（ノッチを見つけた: …）で分かる。
        let mbp14 = CGRect(x: 0, y: 0, width: 1512, height: 982)
        check(
            "ノッチは左右の領域に挟まれた部分",
            NotchGeometry.notchRect(screenFrame: mbp14, topInset: 32, leftWidth: 654, rightWidth: 654),
            CGRect(x: 654, y: 950, width: 204, height: 32)
        )

        check(
            "上の余白が 0 ならノッチは無い",
            NotchGeometry.notchRect(screenFrame: mbp14, topInset: 0, leftWidth: 654, rightWidth: 654),
            nil
        )

        check(
            "左右の領域が取れなければノッチは無い",
            NotchGeometry.notchRect(screenFrame: mbp14, topInset: 32, leftWidth: nil, rightWidth: 654),
            nil
        )

        check(
            "左右の領域が画面幅を埋め尽くしていたらノッチは無い",
            NotchGeometry.notchRect(screenFrame: mbp14, topInset: 32, leftWidth: 756, rightWidth: 756),
            nil
        )

        // 外部ディスプレイをメインにして、MacBook を左下にずらして並べた場合。
        // 画面の原点が (0,0) でなくても、その画面の中でのノッチの位置になること。
        let shifted = CGRect(x: -1512, y: -300, width: 1512, height: 982)
        check(
            "原点がずれた画面でもその画面の上端中央",
            NotchGeometry.notchRect(screenFrame: shifted, topInset: 32, leftWidth: 654, rightWidth: 654),
            CGRect(x: -858, y: 650, width: 204, height: 32)
        )

        // この Mac の DELL（2560×1440pt）。メニューバーの高さは仮に 25pt。
        let dell = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        check(
            "偽のノッチは上端中央",
            NotchGeometry.fakeNotchRect(screenFrame: dell, height: 25),
            CGRect(x: 1180, y: 1415, width: 200, height: 25)
        )

        // MARK: 窓の置き場所

        // メニューバー 32pt、Dock は隠している。
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 950)
        let size = CGSize(width: 400, height: 250)

        check(
            "ノッチの真下、メニューバーから 8pt 下",
            PanelPlacement.frame(size: size, anchorMidX: 756, visibleFrame: visible),
            CGRect(x: 556, y: 692, width: 400, height: 250)
        )

        check(
            "右端のアイコンの下に出しても画面からはみ出さない",
            PanelPlacement.frame(size: size, anchorMidX: 1500, visibleFrame: visible),
            CGRect(x: 1104, y: 692, width: 400, height: 250)
        )

        check(
            "左端でも同じ",
            PanelPlacement.frame(size: size, anchorMidX: 10, visibleFrame: visible),
            CGRect(x: 8, y: 692, width: 400, height: 250)
        )

        check(
            "画面より大きく覚えていたら画面に収まるまで縮める",
            PanelPlacement.frame(size: CGSize(width: 2400, height: 1300), anchorMidX: 756, visibleFrame: visible),
            CGRect(x: 8, y: 8, width: 1496, height: 934)
        )

        let offsetVisible = CGRect(x: -1512, y: -300, width: 1512, height: 950)
        check(
            "原点がずれた画面でもその画面の中に置く",
            PanelPlacement.frame(size: size, anchorMidX: -756, visibleFrame: offsetVisible),
            CGRect(x: -956, y: 392, width: 400, height: 250)
        )

        // MARK: 画質

        check("保存が無ければ自動", Quality(saved: nil), .auto)
        check("知らない値なら自動", Quality(saved: "8K"), .auto)
        check("保存した段を読み戻す", Quality(saved: "1080"), .fhd1080)

        let only720 = { (q: Quality) in q == .hd720 || q == .vga480 }
        check("使える段ならそのまま", Quality.hd720.effective(supported: only720), .hd720)
        check("使えない段なら自動で映す", Quality.uhd2160.effective(supported: only720), .auto)
        check("自動は何にも対応していなくても自動", Quality.auto.effective(supported: { _ in false }), .auto)

        check(
            "メニューの並びは自動が先頭、あとは高い順",
            Quality.allCases.map(\.rawValue),
            ["auto", "2160", "1080", "720", "540", "480"]
        )

        print(failures == 0 ? "\nすべて通った" : "\n\(failures) 件失敗")
        exit(failures == 0 ? 0 : 1)
    }
}
