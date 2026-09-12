#!/bin/sh
# Release ビルドを ~/Applications に置いて起動し直す。
#
# なぜ Xcode の ⌘R ではなくこれを使うのか:
#   - Xcode が起動したアプリには get-task-allow（デバッグ可の印）が付く。
#     アクセシビリティ許可が絡むと挙動が読みにくくなる。
#   - ad-hoc 署名なので、macOS は「同じアプリか」をバイナリのハッシュで見ている。
#     置き場所を固定しておけば、許可を与え直す先が毎回同じになる。
set -e
cd "$(dirname "$0")"

xcodebuild -project LR.xcodeproj -scheme LR -configuration Release \
  -derivedDataPath build -quiet build

pkill -x LR 2>/dev/null || true
# ~/Applications は Finder 上の表示名が /Applications と同じ「アプリケーション」で
# 見分けがつかない。許可を与えるときに迷うので /Applications に置く。
rm -rf ~/Applications/LR.app
rm -rf /Applications/LR.app
cp -R build/Build/Products/Release/LR.app /Applications/LR.app

# アクセシビリティの記録を消してから起動する。
#
# ad-hoc 署名には証明書チェーンが無いので、TCC は「このアプリか」を
# バイナリのハッシュ（cdhash）で固定する。ビルドし直すとハッシュが変わり、
# 記録と一致しなくなる。このとき tccd はこう言う:
#
#   Failed to match existing code requirement for subject com.finalize.lr
#
# 厄介なのは、システム設定のスイッチは ON のまま残ることだ。画面上は許可済みに
# 見えるのに一切動かない、という一番分かりにくい状態になる。だから毎回消す。
# 許可を与え直す手間より、嘘の ON が残る方が高くつく。
tccutil reset Accessibility com.finalize.lr >/dev/null 2>&1 || true

open /Applications/LR.app

echo "起動した: /Applications/LR.app"
echo
echo "アクセシビリティの許可を消したので、与え直しが必要:"
echo "  ダイアログの「システム設定を開く」→ 一覧の LR をオン"
echo "ログ: log show --last 2m --predicate 'subsystem == \"com.finalize.lr\"' --style compact"
