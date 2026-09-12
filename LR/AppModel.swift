import AppKit
import ApplicationServices
import Carbon

/// アプリ全体の状態と、状態を変える手続きをまとめた置き場。
///
/// `@Observable` を付けると、この class のプロパティを読んだ View が
/// そのプロパティが変わったときだけ描き直される。React の state + 再レンダリングに
/// 近いが、依存配列を自分で書く必要は無い。読んだ事実から自動で追跡される。
///
/// `struct` ではなく `class` にしているのは、状態は「1つの実体を共有したい」もので、
/// コピーされてほしくないから。Swift の struct は代入するたびにコピーされる
/// （Go の構造体と同じ値型）。class は参照型で、Go のポインタに近い。
@Observable
final class AppModel {
    // MARK: - View から読まれる状態

    /// いまの入力モードが日本語（かな）かどうか。メニューバーの文字はこれで決まる。
    ///
    /// `private(set)` は「読むのは誰でも、書けるのはこの型の中だけ」。
    /// 状態の変更経路を1か所に絞れるので、UI から勝手に書き換えられなくなる。
    private(set) var isKana = false

    /// アクセシビリティ（キー入力を見る許可）が下りているか。
    private(set) var isTrusted = false

    /// 英数側・かな側として実際に使う入力ソースの表示名。メニューに出す。
    private(set) var asciiName = "—"
    private(set) var kanaName = "—"

    /// 左右の割り当てを入れ替えるか。
    ///
    /// `didSet` はプロパティが変わった直後に走る。UI から変えられた値を
    /// そのまま UserDefaults（macOS の設定保存先。ブラウザの localStorage 的なもの）
    /// に書いておくと、次の起動でも保たれる。
    var isSwapped = false {
        didSet { UserDefaults.standard.set(isSwapped, forKey: Self.swapKey) }
    }

    /// メニューバーに現在のモード（A / あ）も並べるか。
    ///
    /// 既定は false。macOS 自身の入力メニューが既にメニューバーに A / あ を出して
    /// いることが多く、その隣に同じものを出しても二重になるだけだから。
    /// システムの入力メニューを消している人は true にすると状態が見えるようになる。
    var showsMode = false {
        didSet { UserDefaults.standard.set(showsMode, forKey: Self.showsModeKey) }
    }

    /// メニューバーに出す1文字。
    ///
    /// 計算プロパティ（computed property）。値を持たず、読まれるたびに評価される。
    /// `isKana` を読んでいるので、`isKana` が変わればこれを使っている View も更新される。
    var menuBarLabel: String { isKana ? "あ" : "A" }

    // MARK: - 内部

    private static let swapKey = "swapSides"
    private static let showsModeKey = "showsModeInMenuBar"

    private let watcher = CommandKeyWatcher()
    private var ascii: InputSource?
    private var kana: InputSource?
    private var trustTimer: Timer?
    /// 許可の状態を一度でも見たか。
    ///
    /// 起動直後の1回だけやりたいことが2つある。状態をログに必ず1行残すことと、
    /// 許可が無ければダイアログを出すこと。どちらも「初回かどうか」で決まるので
    /// このフラグ1つで見ているが、名前はログ側に寄せない（実際そう書いていて、
    /// ダイアログが出る条件がログ用の名前の裏に隠れていた）。
    private var hasCheckedTrust = false

    init() {
        isSwapped = UserDefaults.standard.bool(forKey: Self.swapKey)
        showsMode = UserDefaults.standard.bool(forKey: Self.showsModeKey)

        reloadInputSources()
        refreshCurrentMode()

        // 単独押しが来たときにやることを渡す。
        watcher.onTap = { [weak self] side in
            self?.switchInput(for: side)
        }

        // 入力ソースが変わったらメニューバーの文字を合わせる。
        // 入力の切り替えは他のプロセス（入力メソッド）が行うので、通知も
        // プロセスを越えて飛んでくる。だから NotificationCenter ではなく
        // DistributedNotificationCenter で受ける。
        //
        // この通知は1回の切り替えで何度も届く（実測で2〜4回）。なので受け取った側は
        // 何度呼ばれても同じ結果になる処理だけを置く。
        observe(kTISNotifySelectedKeyboardInputSourceChanged) { [weak self] in
            self?.refreshCurrentMode()
        }

        // 「どの入力ソースが有効か」が変わったときは別の通知が来る。
        // 一覧の作り直しは重いので、必要なこちらだけに繋いでおく。
        observe(kTISNotifyEnabledKeyboardInputSourcesChanged) { [weak self] in
            self?.reloadInputSources()
        }

        log.notice("起動した 英数=\(self.asciiName, privacy: .public) かな=\(self.kanaName, privacy: .public)")
        updateTrust()
    }

    /// TIS の通知を受け取る。名前が C の定数なので変換をここでまとめている。
    private func observe(_ name: CFString, _ handler: @escaping () -> Void) {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(name as String),
            object: nil,
            queue: .main
        ) { _ in handler() }
    }

    // MARK: - 許可

    /// 許可を求めるダイアログを出す。
    ///
    /// これを呼ぶと、macOS が「LR がコンピュータの制御を求めています」という
    /// ダイアログを出し、**同時にアクセシビリティの一覧にこのアプリを登録する**。
    /// 登録さえされていれば、ユーザーはスイッチを入れるだけでよく、
    /// `.app` の場所を自分で探して「+」で追加する必要が無い。
    ///
    /// ダイアログはアプリごとに一度しか出ない。一度断られたあとに出したいときは
    /// `tccutil reset Accessibility com.finalize.lr` で記録を消す。
    func promptForAccessibility() {
        // kAXTrustedCheckOptionPrompt は CFString の定数。Unmanaged で包まれて
        // いるので、いったん取り出してから辞書のキーとして使う。
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        log.notice("許可ダイアログを出した")
    }

    /// システム設定のアクセシビリティのページを開く。
    func openAccessibilitySettings() {
        promptForAccessibility()
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) {
            NSWorkspace.shared.open(url)
        }
    }

    /// 許可の状態を見に行く。下りていたら監視を始める。
    ///
    /// 許可はユーザーがシステム設定で与えるもので、「与えられた瞬間」を知らせる通知が
    /// 用意されていない。なので下りるまで1秒ごとに見に行き、下りたらタイマーを止める。
    private func updateTrust() {
        let trusted = AXIsProcessTrusted()
        let isFirstCheck = !hasCheckedTrust
        hasCheckedTrust = true

        // 起動直後は必ず1行残す。ログが出ないことと許可が無いことを区別できないと、
        // 動かないときに何も分からなくなる。
        if trusted != isTrusted || isFirstCheck {
            log.notice("アクセシビリティ許可: \(trusted ? "あり" : "なし", privacy: .public)")
            isTrusted = trusted
        }

        // 起動して最初に見たときに許可が無ければ、こちらからダイアログを出す。
        // 一覧に登録される副作用が本命で、これが無いとユーザーは .app を
        // 自分で探して「+」で追加することになる。
        if isFirstCheck && !trusted {
            promptForAccessibility()
        }

        if trusted {
            watcher.start()
            trustTimer?.invalidate()
            trustTimer = nil
        } else if trustTimer == nil {
            trustTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.updateTrust()
            }
        }
    }

    // MARK: - 切り替え

    /// 単独押しされた側に応じて入力を切り替える。
    private func switchInput(for side: CommandSide) {
        // 右がかな、左が英数。入れ替え設定が入っていれば逆。
        // `!=` を Bool 同士に使うと排他的論理和（XOR）になる。
        let wantKana = (side == .right) != isSwapped
        let target = wantKana ? kana : ascii
        let ok = target?.select() ?? false
        // うまくいっているときは debug（残さない）、失敗したときだけ error（残す）。
        // 「たまに切り替わらない」を後から追えるようにしておきたいのは失敗の方だけ。
        if ok {
            log.debug("切り替え \(wantKana ? "かな" : "英数", privacy: .public) 対象=\(target?.id ?? "なし", privacy: .public)")
        } else {
            log.error("切り替えに失敗 \(wantKana ? "かな" : "英数", privacy: .public) 対象=\(target?.id ?? "見つからない", privacy: .public)")
        }
    }

    /// 英数側・かな側に使う入力ソースを拾い直す。
    private func reloadInputSources() {
        ascii = InputSource.resolveASCII()
        kana = InputSource.resolveKana()
        asciiName = ascii?.localizedName ?? "見つかりません"
        kanaName = kana?.localizedName ?? "見つかりません"
    }

    /// いまの入力ソースを見て `isKana` を合わせる。
    private func refreshCurrentMode() {
        guard let current = InputSource.current else { return }
        // ID の一致ではなく「日本語を扱う入力モードか」で見る。ことえりでも
        // 他の IME でも同じ判定で通る。
        // 変数名を kana にしないこと。プロパティの `kana`（InputSource?）を
        // この関数の中だけ Bool で隠してしまう。Swift は警告を出さない。
        let nowKana = current.type == (kTISTypeKeyboardInputMode as String)
            && current.languages.contains("ja")
        // 同じ値でも代入すると @Observable は変化として扱い、View を描き直させる。
        // この通知は何度も届くので、変わったときだけ書く。
        if nowKana != isKana { isKana = nowKana }
    }
}
