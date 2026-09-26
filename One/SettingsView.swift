import SwiftUI

/// 設定の窓。機能ごとにタブを分ける。
///
/// `OneApp` の `Settings` シーンの中身。macOS では `Settings` の中に `TabView` を置くと、
/// 窓の上にアイコン付きのタブが並ぶ、システム設定の各アプリでおなじみの形になる。
/// タブごとに高さが違ってよく、切り替えると窓の高さが中身に合わせて伸び縮みする。
///
/// メニューには操作（ウィンドウを動かす・鏡を出す）だけを残し、切り替えや選択は
/// ここに集めた。
struct SettingsView: View {
    /// `@Bindable` は `@Observable` なオブジェクトから `$model.isSwapped` の形で
    /// 双方向の結び付き（Binding）を作れるようにする印。Toggle のように
    /// 「読むだけでなく書き換えもする」部品に渡すときに必要になる。
    @Bindable var model: AppModel
    @Bindable var mirror: MirrorModel

    var body: some View {
        TabView {
            GeneralSettings(model: model)
                .tabItem { Label("一般", systemImage: "gearshape") }
            InputSettings(model: model)
                .tabItem { Label("英かな", systemImage: "command") }
            WindowSettings(model: model)
                .tabItem { Label("ウィンドウ", systemImage: "uiwindow.split.2x1") }
            MirrorSettings(mirror: mirror)
                .tabItem { Label("鏡", systemImage: "web.camera") }
        }
        // `.grouped` は、システム設定と同じ「角の丸い箱に項目を並べる」見た目。
        // 幅は固定し、高さは中身に任せる。
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct GeneralSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Toggle("ログイン時に起動", isOn: $model.launchesAtLogin)

            Section("許可") {
                // `LabeledContent` は「左に名前、右に値」の1行。
                LabeledContent("アクセシビリティ") {
                    if model.isTrusted {
                        Text("あり")
                    } else {
                        Button("システム設定を開く…") { model.openAccessibilitySettings() }
                    }
                }
                Text("⌘ の単独押しを見るのと、ほかのアプリのウィンドウを動かすのに使う。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct InputSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section {
                LabeledContent("左 ⌘", value: model.isSwapped ? model.kanaName : model.asciiName)
                LabeledContent("右 ⌘", value: model.isSwapped ? model.asciiName : model.kanaName)
                Toggle("左右を入れ替える", isOn: $model.isSwapped)
            } footer: {
                Text("⌘ を押して、ほかのキーもクリックも挟まずに離すと切り替わる。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Toggle の見出しに Text を2つ書くと、2つ目は説明として小さく出る。
            Toggle(isOn: $model.showsMode) {
                Text("メニューバーに A / あ も出す")
                Text("macOS の入力メニューが同じものを出しているなら、二重になるだけなので要らない。")
            }
        }
    }
}

private struct WindowSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Toggle(isOn: $model.arrangesWindows) {
                Text("ショートカットで動かす")
                Text("⌃⌥← などで、手前のウィンドウを半分や 1/3 に並べる。キーはメニューの「ウィンドウ」に出る。Rectangle と一緒に使うなら切る。メニューから選んで動かすのは、切っていてもできる。")
            }
            Toggle(isOn: $model.snapsWindows) {
                Text("ドラッグで端に寄せて並べる")
                Text("macOS 自身の、端へ寄せて並べる機能（システム設定 > デスクトップと Dock）を使うなら切る。両方入っていると1回のドラッグに両方が反応する。")
            }
        }
    }
}

private struct MirrorSettings: View {
    @Bindable var mirror: MirrorModel

    var body: some View {
        Form {
            Section {
                Picker("カメラ", selection: $mirror.cameraID) {
                    // nil を「自動」に当てる。タグの型は `cameraID` と同じ `String?` に揃える。
                    Text("自動").tag(String?.none)
                    ForEach(mirror.cameras, id: \.id) { camera in
                        Text(camera.name).tag(Optional(camera.id))
                    }
                }
                Picker("画質", selection: $mirror.quality) {
                    // 今のカメラで使えない段は並べない。Picker の項目には `.disabled` が効かず
                    // （ポップアップでもラジオボタンでも、灰色にならずに選べてしまう）、
                    // 並べないことで代える。
                    //
                    // ただし選んである段は、使えなくても出す。無いと Picker が今の選択を見失う。
                    // 4K のカメラで 4K を選んだまま内蔵カメラに切り替えたときがこれ。
                    ForEach(qualities, id: \.self) { quality in
                        Text(mirror.supports(quality) ? quality.label : "\(quality.label)（このカメラでは使えない）")
                            .tag(quality)
                    }
                }
                if let resolution = mirror.activeResolution {
                    LabeledContent("いま映っている", value: resolution)
                }
            } footer: {
                Text("今のカメラで使えない画質は出さない。選んであった画質が使えないカメラでは、自動で映す。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("鏡像にする", isOn: $mirror.isMirrored)
                Toggle("外をクリックしても閉じない", isOn: $mirror.isPinned)
                Toggle(isOn: $mirror.opensFromNotch) {
                    Text("ノッチのクリックで開く")
                    Text("ノッチの無い Mac では、メニューの「鏡を出す」で開く。")
                }
            }

            // この窓は One の窓なので、ここを押しても鏡は閉じない（外のクリックにならない）。
            // 鏡を出したまま上の設定を変えると、映りがその場で変わる。
            Button(mirror.isVisible ? "鏡を隠す" : "鏡を出して確かめる") { mirror.toggleUnderMouse() }
        }
    }

    /// 画質の選択肢。今のカメラで使える段と、選んである段。
    private var qualities: [Quality] {
        Quality.allCases.filter { mirror.supports($0) || $0 == mirror.quality }
    }
}
