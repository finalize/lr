import AppKit

// 単独押しの判定（CommandKeyWatcher）を、合成した NSEvent で確かめる。
//
// 実際のキーボードを叩くテストは書けない。アクセシビリティの許可が要るし、
// 「⌘ を押して離す」を機械にやらせるのも面倒だ。判定を
// `CommandKeyWatcher.process(_:)` に切り出してあるので、イベントを自分で
// 組み立てて流し込めばキーボード無しで全部試せる。

// MARK: - NSEvent.ModifierFlags の生ビット

private let CMD: UInt = 0x0010_0000 // .command（左右どちらかが押されている）
private let SHIFT: UInt = 0x0002_0000 // .shift
private let CAPS: UInt = 0x0001_0000 // .capsLock
private let LCMD: UInt = 0x0000_0008 // 左 Command（デバイス依存ビット）
private let RCMD: UInt = 0x0000_0010 // 右 Command

// MARK: - イベントの組み立て

private func flagsEvent(_ raw: UInt, keyCode: UInt16 = 55) -> NSEvent {
    NSEvent.keyEvent(
        with: .flagsChanged, location: .zero,
        modifierFlags: NSEvent.ModifierFlags(rawValue: raw),
        timestamp: 0, windowNumber: 0, context: nil,
        characters: "", charactersIgnoringModifiers: "",
        isARepeat: false, keyCode: keyCode
    )!
}

private func keyDownEvent(_ raw: UInt) -> NSEvent {
    NSEvent.keyEvent(
        with: .keyDown, location: .zero,
        modifierFlags: NSEvent.ModifierFlags(rawValue: raw),
        timestamp: 0, windowNumber: 0, context: nil,
        characters: "c", charactersIgnoringModifiers: "c",
        isARepeat: false, keyCode: 8
    )!
}

private func clickEvent(_ raw: UInt) -> NSEvent {
    NSEvent.mouseEvent(
        with: .leftMouseDown, location: .zero,
        modifierFlags: NSEvent.ModifierFlags(rawValue: raw),
        timestamp: 0, windowNumber: 0, context: nil,
        eventNumber: 0, clickCount: 1, pressure: 1
    )!
}

// MARK: - 実行

@main
struct WatcherTests {
    static var failures = 0

    /// イベント列を流して、発火した側が期待と一致するかを見る。
    static func check(_ name: String, _ events: [NSEvent], expect: [CommandSide]) {
        let watcher = CommandKeyWatcher()
        var fired: [CommandSide] = []
        watcher.onTap = { fired.append($0) }
        for event in events { watcher.process(event) }

        let ok = fired == expect
        if !ok { failures += 1 }
        func describe(_ sides: [CommandSide]) -> String {
            sides.isEmpty ? "発火なし" : sides.map { $0 == .left ? "左" : "右" }.joined(separator: "→")
        }
        print("\(ok ? "PASS" : "FAIL")  \(name)  期待=\(describe(expect)) 実際=\(describe(fired))")
    }

    static func main() {
        // 切り替わってほしいとき
        check("左⌘ 単独押し", [flagsEvent(CMD | LCMD), flagsEvent(0)], expect: [.left])
        check("右⌘ 単独押し", [flagsEvent(CMD | RCMD, keyCode: 54), flagsEvent(0)], expect: [.right])

        // 切り替わってはいけないとき
        check("⌘C", [flagsEvent(CMD | LCMD), keyDownEvent(CMD | LCMD), flagsEvent(0)], expect: [])
        check("⌘ のあと ⇧ を足す", [
            flagsEvent(CMD | LCMD),
            flagsEvent(CMD | LCMD | SHIFT),
            flagsEvent(CMD | LCMD),
            flagsEvent(0),
        ], expect: [])
        check("⇧ のあと ⌘（順番が逆）", [
            flagsEvent(SHIFT),
            flagsEvent(SHIFT | CMD | LCMD),
            flagsEvent(SHIFT),
            flagsEvent(0),
        ], expect: [])
        check("左右 ⌘ を同時に押す", [
            flagsEvent(CMD | LCMD),
            flagsEvent(CMD | LCMD | RCMD),
            flagsEvent(CMD | LCMD),
            flagsEvent(0),
        ], expect: [])
        check("⌘ + クリック", [flagsEvent(CMD | LCMD), clickEvent(CMD | LCMD), flagsEvent(0)], expect: [])
        check("⇧ だけ押して離す", [flagsEvent(SHIFT), flagsEvent(0)], expect: [])

        // 状態が持ち越されていないか
        check("左→右→左 と続けて単独押し", [
            flagsEvent(CMD | LCMD), flagsEvent(0),
            flagsEvent(CMD | RCMD, keyCode: 54), flagsEvent(0),
            flagsEvent(CMD | LCMD), flagsEvent(0),
        ], expect: [.left, .right, .left])
        check("⌘C の直後に 左⌘ 単独", [
            flagsEvent(CMD | LCMD), keyDownEvent(CMD | LCMD), flagsEvent(0),
            flagsEvent(CMD | LCMD), flagsEvent(0),
        ], expect: [.left])
        check("Caps Lock 入りで 左⌘ 単独", [flagsEvent(CAPS | CMD | LCMD), flagsEvent(CAPS)], expect: [.left])

        print(failures == 0 ? "\nすべて通過" : "\n\(failures) 件 失敗")
        exit(failures == 0 ? 0 : 1)
    }
}
