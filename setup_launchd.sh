#!/bin/bash
# macOS launchd で毎朝8時に自動実行する設定
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST_PATH="$HOME/Library/LaunchAgents/com.klms-to-todo.plist"
PYTHON="$SCRIPT_DIR/.venv/bin/python"
MAIN="$SCRIPT_DIR/main.py"
LOG="$SCRIPT_DIR/klms-to-todo.log"

cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.klms-to-todo</string>
    <key>ProgramArguments</key>
    <array>
        <string>$PYTHON</string>
        <string>$MAIN</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>8</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>WorkingDirectory</key>
    <string>$SCRIPT_DIR</string>
    <key>StandardOutPath</key>
    <string>$LOG</string>
    <key>StandardErrorPath</key>
    <string>$LOG</string>
    <key>RunAtLoad</key>
    <false/>
</dict>
</plist>
EOF

launchctl unload "$PLIST_PATH" 2>/dev/null || true
launchctl load "$PLIST_PATH"

echo "✅ 毎朝8時に自動実行するよう設定しました。"
echo "   ログ: $LOG"
echo ""
echo "停止する場合:"
echo "  launchctl unload $PLIST_PATH"
