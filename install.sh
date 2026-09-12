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

# ad-hoc 署名のときだけ、アクセシビリティの記録を消す。
#
# ad-hoc には証明書チェーンが無いので、TCC は許可の条件をバイナリのハッシュで
# 固定する。再ビルドすると一致しなくなるのに、システム設定のスイッチは ON のまま
# 残る。「許可済みに見えるのに一切動かない」という一番分かりにくい壊れ方をする。
# 与え直す手間より、嘘の ON が残る方が高くつくので消してしまう。
#
# 証明書（Cert/make-cert.sh）で署名していればこの問題は起きない。条件が
# ハッシュではなく証明書で書かれるので、何度ビルドしても許可が残る。
if codesign -dvv /Applications/LR.app 2>&1 | grep -q "Signature=adhoc"; then
  tccutil reset Accessibility com.finalize.lr >/dev/null 2>&1 || true
  adhoc=yes
fi

open /Applications/LR.app

echo "起動した: /Applications/LR.app"
if [ "$adhoc" = yes ]; then
  echo
  echo "ad-hoc 署名なので許可の記録を消した。与え直しが必要:"
  echo "  ダイアログの「システム設定を開く」→ 一覧の LR をオン"
  echo "  毎回これをやりたくなければ ./Cert/make-cert.sh"
fi
echo "ログ: log show --last 2m --predicate 'subsystem == \"com.finalize.lr\"' --style compact"
