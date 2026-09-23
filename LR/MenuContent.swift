import SwiftUI

/// メニューバーアイコンをクリックしたときに開くメニューの中身。
///
/// `View` は「画面の一部分」を表すプロトコル。`body` に「どう見えるか」を書くと、
/// SwiftUI が必要なときに読み直して描く。React のコンポーネントの render に近い。
/// struct（値型）なのは、View 自体は使い捨ての設計図で、状態を持たないから。
struct MenuContent: View {
    /// `@Bindable` は `@Observable` なオブジェクトから `$model.isSwapped` の形で
    /// 双方向の結び付き（Binding）を作れるようにする印。Toggle のように
    /// 「読むだけでなく書き換えもする」部品に渡すときに必要になる。
    @Bindable var model: AppModel

    var body: some View {
        // MenuBarExtra の既定のスタイル（.menu）では、ここに書けるのは
        // Text / Button / Toggle / Divider / Menu などメニューにできるものだけ。
        // HStack で凝ったレイアウトを組みたくなったら
        // `.menuBarExtraStyle(.window)` にするとふつうの SwiftUI が使える。

        if !model.isTrusted {
            Text("キー入力を見る許可がありません")
            Button("アクセシビリティ設定を開く…") {
                model.openAccessibilitySettings()
            }
            Divider()
        }

        Text("左 ⌘  →  \(model.isSwapped ? model.kanaName : model.asciiName)")
        Text("右 ⌘  →  \(model.isSwapped ? model.asciiName : model.kanaName)")

        Divider()

        Toggle("左右を入れ替える", isOn: $model.isSwapped)
        Toggle("メニューバーに A / あ も出す", isOn: $model.showsMode)

        Divider()

        // `Menu` はメニューの中の入れ子（サブメニュー）になる。
        Menu("ウィンドウ") {
            ForEach(Self.windowGroups, id: \.self) { group in
                ForEach(group, id: \.self) { action in
                    Button(action.title) { model.arrange(action) }
                        // ショートカットを登録しているときだけ、右側にキーを出す。
                        // 切っているのに出すと、押せば効くように見えてしまう。
                        .keyboardShortcut(model.arrangesWindows ? action.keyboardShortcut : nil)
                }
                Divider()
            }
            Toggle("ショートカットで動かす", isOn: $model.arrangesWindows)
            Toggle("ドラッグで端に寄せて並べる", isOn: $model.snapsWindows)
        }

        Divider()

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
