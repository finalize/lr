import SwiftUI

/// メニューバーアイコンをクリックしたときに開くメニューの中身。
///
/// `View` は「画面の一部分」を表すプロトコル。`body` に「どう見えるか」を書くと、
/// SwiftUI が必要なときに読み直して描く。React のコンポーネントの render に近い。
/// struct（値型）なのは、View 自体は使い捨ての設計図で、状態を持たないから。
struct MenuContent: View {
    /// ここでは読むだけなので `@Bindable` は要らない。`@Observable` のオブジェクトは、
    /// ふつうのプロパティとして持つだけで、読んだ値の変化が追われる。
    let model: AppModel
    let mirror: MirrorModel

    /// 設定の窓（`LRApp` の `Settings` シーン）を開く手続き。
    ///
    /// `@Environment` は、SwiftUI が外から渡してくれる値を受け取る印。React の
    /// useContext に近い。`openSettings` は関数のように呼べる値になっている。
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        // MenuBarExtra の既定のスタイル（.menu）では、ここに書けるのは
        // Text / Button / Toggle / Divider / Menu などメニューにできるものだけ。
        //
        // メニューには操作だけを置く。切り替えや選択は設定の窓（SettingsView）に集めた。

        if !model.isTrusted {
            Text("キー入力を見る許可がありません")
            Button("アクセシビリティ設定を開く…") {
                model.openAccessibilitySettings()
            }
            Divider()
        }

        // `Menu` はメニューの中の入れ子（サブメニュー）になる。
        Menu("ウィンドウ") {
            ForEach(Self.windowGroups, id: \.self) { group in
                ForEach(group, id: \.self) { action in
                    Button(action.title) { model.arrange(action) }
                        // ショートカットを登録しているときだけ、右側にキーを出す。
                        // 切っているのに出すと、押せば効くように見えてしまう。
                        .keyboardShortcut(model.arrangesWindows ? action.keyboardShortcut : nil)
                }
                // 最後のまとまりの後ろには区切り線を入れない。
                if group != Self.windowGroups.last {
                    Divider()
                }
            }
        }
        Button(mirror.isVisible ? "鏡を隠す" : "鏡を出す") { mirror.toggleUnderMouse() }

        Divider()

        Button("設定…") {
            // LR は Dock に出ないアプリで、ふだんは前面のアプリではない。前に出さないと、
            // 設定の窓が他のアプリの窓の後ろに開く。
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")
        Button("LR を終了") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    /// ウィンドウのメニューに並べる順と、区切り線の入れ方。
    private static let windowGroups: [[WindowAction]] = [
        [.leftHalf, .rightHalf, .topHalf, .bottomHalf],
        [.topLeft, .topRight, .bottomLeft, .bottomRight],
        [.firstThird, .centerThird, .lastThird, .firstTwoThirds, .centerTwoThirds, .lastTwoThirds],
        [.maximize, .maximizeHeight, .center, .larger, .smaller, .restore],
        [.previousDisplay, .nextDisplay],
    ]
}

private extension WindowAction {
    /// メニューの項目の右に出すキー。
    var keyboardShortcut: KeyboardShortcut {
        KeyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
    }
}
