import SwiftUI

/// アプリの入口。
///
/// `@main` が付いた構造体が起動時の起点になる。Go の `func main()` と同じ役割だが、
/// 本体は書かない。`App` プロトコルの `body` に「どんな画面を持つか」を宣言すると、
/// SwiftUI が裏で NSApplication を組み立てて実行してくれる。
///
/// ここでは `WindowGroup`（通常のウィンドウ）を一切持たず、`MenuBarExtra` と
/// 設定の窓（`Settings`）だけを置く。
/// これと Info.plist の `LSUIElement = YES`（プロジェクト設定の
/// `INFOPLIST_KEY_LSUIElement`）が揃うと、Dock にも ⌘Tab にも出てこない、
/// メニューバーだけのアプリになる。
@main
struct LRApp: App {
    /// アプリが生きている間ずっと使う状態。
    ///
    /// `@State` は「この View が持ち主で、生存期間もこの View に合わせる」という印。
    /// React の `useState` に近い。`AppModel` は `@Observable` なので、
    /// この中のプロパティを読んだ画面だけが、そのプロパティの変化で描き直される。
    @State private var model = AppModel()

    /// 鏡（ノッチのクリックで出るカメラの映像）の状態。`AppModel` と分けてある理由は
    /// `MirrorModel` の注釈に書いた。
    @State private var mirror = MirrorModel()

    /// `some Scene` は「Scene プロトコルを満たす何らかの型」。
    /// 具体的な型名を書かなくていい（TypeScript のジェネリクス推論に近い）。
    var body: some Scene {
        MenuBarExtra {
            // ここが「クリックしたときに開くメニュー」の中身。
            MenuContent(model: model, mirror: mirror)
        } label: {
            // ここが「メニューバーに出る見た目」。
            //
            // アイコンは SF Symbols の "command"。画像を自分で用意しなくても
            // メニューバーの明暗に合わせて自動で白黒が反転する（テンプレート画像）。
            // アプリのアイコン（グラデーション）はここには使えない。メニューバーは
            // 単色しか許さないので、色を付けても全部潰される。
            if model.showsMode {
                Label(model.menuBarLabel, systemImage: "command")
            } else {
                Image(systemName: "command")
            }
        }

        // メニューの「設定…」で開く窓。機能ごとのタブは SettingsView に書いてある。
        //
        // `Settings` は macOS のアプリの設定の窓を作るための Scene。開く・閉じる・
        // 前に開いていたら同じ窓を前に出す、を SwiftUI が面倒を見る。
        Settings {
            SettingsView(model: model, mirror: mirror)
        }
    }
}
