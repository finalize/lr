#!/bin/sh
# Release ビルドを /Applications に置いて起動し直す。
#
# なぜ Xcode の ⌘R ではなくこれを使うのか:
#   - Xcode が起動したアプリには get-task-allow（デバッグ可の印）が付く。
#     アクセシビリティ許可が絡むと挙動が読みにくくなる。
#   - 置き場所を固定しておけば、許可を与える先が毎回同じになる。
#   - ~/Applications は Finder 上の表示名が /Applications と同じ「アプリケーション」で
#     見分けがつかない。許可を与えるときに迷うので /Applications に置く。
set -e
cd "$(dirname "$0")"

APP=/Applications/LR.app
BUNDLE_ID=com.finalize.lr
BUILT=build/Build/Products/Release/LR.app

xcodebuild -project LR.xcodeproj -scheme LR -configuration Release \
  -derivedDataPath build -quiet build

# アクセシビリティの記録を捨てるべきか、入れ替える前に決める。
#
# TCC は「このアプリか」を designated requirement で判定する。ここが今までと
# 変わると、記録は残っているのに一致しなくなり、tccd がこう言う:
#
#   Failed to match existing code requirement for subject com.finalize.lr
#
# 厄介なのは、**システム設定のスイッチは ON のまま残る**ことだ。許可済みに
# 見えるのに一切動かない、という一番分かりにくい壊れ方をする。スイッチを
# 押し直しても入らない。記録を消すしか直し方が無い。
#
# requirement が変わる場面は2つある:
#   - ad-hoc 署名。証明書チェーンが無いので条件が cdhash で書かれ、毎回変わる
#   - 署名に使う証明書を変えたとき（ad-hoc → 自己署名、別マシンで作り直した等）
#
# どちらも「前に入っていたものと requirement が違う」で一度に判定できるので、
# 署名方式を場合分けせず、新旧を突き合わせる。
req() { codesign -d -r- "$1" 2>/dev/null | grep '^designated' || true; }
old_req=$(req "$APP")
new_req=$(req "$BUILT")

pkill -x LR 2>/dev/null || true
rm -rf ~/Applications/LR.app        # 昔ここに置いていた分の掃除
rm -rf "$APP"
cp -R "$BUILT" "$APP"

if [ -n "$old_req" ] && [ "$old_req" != "$new_req" ]; then
  tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
  regrant=yes
fi

open "$APP"

echo "起動した: $APP"
if [ "$regrant" = yes ]; then
  echo
  echo "署名の条件が前回と変わったので、許可の記録を消した。与え直しが必要:"
  echo "  ダイアログの「システム設定を開く」→ 一覧の LR をオン"
  echo
  echo "  前回: $old_req"
  echo "  今回: $new_req"
  case "$new_req" in
    *cdhash*) echo
              echo "  cdhash で条件が書かれている = ad-hoc 署名。毎回これが起きる。"
              echo "  ./Cert/make-cert.sh を一度走らせると起きなくなる。" ;;
  esac
fi
echo "ログ: log show --last 2m --predicate 'subsystem == \"$BUNDLE_ID\"' --style compact"
