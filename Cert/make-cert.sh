#!/bin/sh
# コード署名用の自己署名証明書を作って login キーチェーンに入れる。
#
# なぜ要るか
# ----------
# ad-hoc 署名（CODE_SIGN_IDENTITY = "-"）には証明書チェーンが無いので、TCC は
# アクセシビリティ許可の条件をバイナリのハッシュで固定する。再ビルドすると
# ハッシュが変わって一致しなくなるのに、システム設定のスイッチは ON のまま残る。
# 「許可済みに見えるのに一切動かない」という一番分かりにくい壊れ方をする。
#
# 証明書で署名すると、条件が証明書で書かれるようになる:
#
#   designated => identifier "com.finalize.lr" and certificate root = H"…"
#
# ハッシュを参照していないので、何度ビルドしても許可が残る。
#
# Apple Developer への登録は要らない。信頼設定（GUI の認証が要る）も要らない。
# codesign は信頼されていない自己署名の identity でも署名できる。
#
# 注意: 実行するたびに別の証明書ができる。別のマシンで作り直した場合は
# 条件のハッシュが変わるので、アクセシビリティ許可を一度だけ与え直すこと。
set -e

NAME="LR Code Signing"

if security find-identity -p codesigning 2>/dev/null | grep -q "$NAME"; then
  echo "すでにある: $NAME"
  security find-identity -p codesigning | grep "$NAME"
  exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT   # 秘密鍵をディスクに残さない

cat > "$work/req.cnf" <<'CNF'
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no

[dn]
CN = LR Code Signing
O = finalize

[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
CNF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$work/key.pem" -out "$work/cert.pem" -config "$work/req.cnf" 2>/dev/null

# 空パスワードの PKCS#12 は macOS の security import が受け付けないので、
# 使い捨てのパスワードを付けて渡す。
pw=$(openssl rand -hex 16)
openssl pkcs12 -export -inkey "$work/key.pem" -in "$work/cert.pem" \
  -out "$work/id.p12" -passout "pass:$pw" -name "$NAME" 2>/dev/null

# -A はこの鍵をどのアプリからも使えるようにする指定。これが無いと
# codesign のたびにキーチェーンの確認ダイアログが出る。
security import "$work/id.p12" -k ~/Library/Keychains/login.keychain-db -P "$pw" -A

echo
echo "作った:"
security find-identity -p codesigning | grep "$NAME"
echo
echo "CSSMERR_TP_NOT_TRUSTED と出るのは正常。信頼設定を入れていないだけで、"
echo "codesign は信頼されていない自己署名の identity でも署名できる。
