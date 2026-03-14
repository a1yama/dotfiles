# notify-wio: Wio Terminal にシリアル経由で通知を送る
# 未接続時はスキップする
notify-wio() {
  local port=$(ls /dev/tty.usbmodem* 2>/dev/null | head -1)
  [ -z "$port" ] && return 0
  printf "%s\n" "$1" > "$port" 2>/dev/null &!
}

# git push 後に CI を監視して結果を Wio Terminal に通知する
git-push-watch() {
  git push "$@"
  local exit_code=$?
  [ $exit_code -ne 0 ] && return $exit_code

  # バックグラウンドで CI 監視
  (
    gh run watch --exit-status 2>/dev/null \
      && notify-wio "CI passed" \
      || notify-wio "CI FAILED"
  ) &!
}
