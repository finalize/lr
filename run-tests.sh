#!/bin/sh
# 単独押しの判定ロジックだけを、合成した NSEvent で確かめる。
#
# 実際のキーボードを叩くテストは書けない（アクセシビリティ許可が要るし、
# CI でも走らない）。判定を CommandKeyWatcher.process() に切り出してあるので、
# イベントを自分で作って流し込めば、キーボード無しで全部試せる。
set -e
cd "$(dirname "$0")"
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
swiftc -o "$out/tests" LR/CommandKeyWatcher.swift LR/Log.swift Tests/WatcherTests.swift
"$out/tests"
