# Android SDK
# Kyash-Android の bootstrap.sh は ANDROID_HOME から sdk.dir を決めるため、
# SDK が無い環境で空の変数を渡さないよう存在チェックしてから export する。
if [ -d "$HOME/Library/Android/sdk" ]; then
  export ANDROID_HOME="$HOME/Library/Android/sdk"
  export ANDROID_SDK_ROOT="$ANDROID_HOME"
  export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"
fi
