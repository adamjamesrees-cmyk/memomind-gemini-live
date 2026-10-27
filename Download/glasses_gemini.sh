#!/system/bin/sh
# MemoMind glasses wake word ("Hi Memo" / "Bye Memo") -> Gemini Live toggle.
# Run by Tasker through Shizuku (shell user) on the Memo KWS log line.
# Prints "live" once Live is listening, so Tasker can play a ready beep and then
# run "glasses_gemini.sh memo" to bring Memo back while Live keeps running.

GEMINI=com.google.android.googlequicksearchbox
MEMO=com.memomind.ai.aphrodite
STATE=/sdcard/Download/.glasses_gemini
mkdir -p "$STATE"

live_running() {
  dumpsys audio | sed -n '/Audio Focus stack entries/,/external focus policy/p' | grep -q "$GEMINI"
}

# One line per step in timing.log, wall clock to the ms, for tuning start-up.
# Kept small: past ~100 KB the older half is dropped.
if [ -f "$STATE/timing.log" ] && [ $(wc -c < "$STATE/timing.log") -gt 100000 ]; then
  tail -n 500 "$STATE/timing.log" > "$STATE/timing.tmp" && mv "$STATE/timing.tmp" "$STATE/timing.log"
fi
mark() {
  echo "$(date +%H:%M:%S.%N | cut -c1-12) $1 $2" >> "$STATE/timing.log"
}

# Centre of Gemini's "Open Gemini Live" button, or nothing while it is not on
# screen. Reads the Gemini window's own view tree (dumpsys activity <component>,
# ~75ms) and adds up each view's offset inside its parent, so it works in
# either of the app's layouts and never answers before the button is drawn.
GEMINI_UI=$GEMINI/com.google.android.apps.search.assistant.surfaces.voice.robin.main.MainActivity
live_button() {
  dumpsys activity $GEMINI_UI 2>/dev/null | awk '
    /DecorView/ { on = 1; n = 0 }
    !on || !match($0, /[{][0-9a-f]+ [^ ]+ [^ ]+ -?[0-9]+,-?[0-9]+--?[0-9]+,-?[0-9]+/) { next }
    {
      line = $0
      split(substr(line, RSTART + 1, RLENGTH - 1), f, " ")
      t = line; sub(/^ */, "", t); ind = length(line) - length(t)
      c = f[4]
      for (i = 2; i <= length(c); i++)
        if (substr(c, i, 1) == "-" && substr(c, i - 1, 1) ~ /[0-9]/) break
      split(substr(c, 1, i - 1), a, ","); split(substr(c, i + 1), b, ",")
      while (n > 0 && sd[n] >= ind) n--
      px = n ? sx[n] : 0; py = n ? sy[n] : 0; pv = n ? sv[n] : 1
      n++; sd[n] = ind; sx[n] = px + a[1]; sy[n] = py + a[2]
      sv[n] = pv && substr(f[2], 1, 1) == "V"
      if (line ~ /voice_chat_button_compose/ && sv[n] && b[1] > a[1]) {
        print int(sx[n] + (b[1] - a[1]) / 2), int(sy[n] + (b[2] - a[2]) / 2)
        exit
      }
    }'
}

# Bring Memo back so the glasses reconnect. Memo only reconnects if its screen
# actually opens, so it has to come to the front for about a second; then put
# back whatever was there (e.g. Maps that the assistant just opened), or go
# home if that was the home screen. Behind the lock screen nothing shows, so
# launch straight away, then after the unlock (up to a minute, plus 5s for the
# assistant to open what it asked to be unlocked for) only press Home if Memo
# is the thing on screen.
restart_memo() {
  home=$(cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null | tail -n 1 | cut -d/ -f1)
  prev=$(dumpsys activity activities | grep -m 1 'topResumedActivity' | sed -n 's/.* u0 \([^/ ]*\)\/.*/\1/p')
  locked=
  dumpsys window | grep -q 'isKeyguardShowing=true' && locked=1
  k=0
  dumpsys activity services $MEMO | grep -q 'services.ForegroundService' && k=25
  t=$(date +%s.%N | cut -c1-14)
  am start -n $MEMO/.MainActivity >/dev/null 2>&1
  while [ $k -lt 25 ] && ! logcat -d -T "$t" 2>/dev/null | grep -q 'BluetoothConnectState.connected'; do
    k=$((k + 1))
    sleep 0.2
  done
  sleep 0.3
  if [ -n "$locked" ]; then
    k=0
    while [ $k -lt 120 ] && dumpsys window | grep -q 'isKeyguardShowing=true'; do
      k=$((k + 1))
      sleep 0.5
    done
    sleep 5
    prev=$home
  fi
  dumpsys activity activities | grep -m 1 'topResumedActivity' | grep -q "$MEMO" || return 0
  # Gemini counts as home: after Live starts, Home collapses it to its bar.
  if [ -z "$prev" ] || [ "$prev" = "$home" ] || [ "$prev" = "$MEMO" ] || [ "$prev" = "$GEMINI" ]; then
    input keyevent KEYCODE_HOME
  else
    back=$(cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER "$prev" 2>/dev/null | tail -n 1)
    case "$back" in
      */*) am start -a android.intent.action.MAIN -c android.intent.category.LAUNCHER -f 0x10200000 -n "$back" >/dev/null 2>&1 ;;
      *) input keyevent KEYCODE_HOME ;;
    esac
  fi
}

# End the Gemini session. Live (unlocked) is ended with its own "End Live mode"
# button, which keeps the Gemini app loaded so the next start is ~1s quicker
# than after a force-stop. That button has no view id, so it is found by its
# label with a full screen dump (~2-3s, fine for stopping). Locked voice mode,
# or a Live screen that cannot be read, falls back to force-stopping the app.
end_live() {
  if [ "$(cat "$STATE/mode" 2>/dev/null)" = live ] && ! dumpsys window | grep -q 'isKeyguardShowing=true'; then
    am start -n com.google.android.apps.bard/.shellapp.BardEntryPointActivity >/dev/null 2>&1
    k=0
    while [ $k -lt 3 ]; do
      sleep 0.5
      timeout 8 uiautomator dump /sdcard/.gemini_end.xml >/dev/null 2>&1
      e=$(tr '>' '\n' < /sdcard/.gemini_end.xml 2>/dev/null | grep 'content-desc="End Live mode"' | sed -n 's/.*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\]".*/\1 \2 \3 \4/p' | head -n 1)
      if [ -n "$e" ]; then
        set -- $e
        input tap $(( ($1 + $3) / 2 )) $(( ($2 + $4) / 2 ))
        mark end_tap
        break
      fi
      k=$((k + 1))
    done
    rm -f /sdcard/.gemini_end.xml
    k=0
    while [ $k -lt 10 ] && live_running; do
      k=$((k + 1))
      sleep 0.3
    done
    input keyevent KEYCODE_HOME
  fi
  live_running && { am force-stop $GEMINI; mark end_forced; }
  rm -f "$STATE/mode"
}

# "button" argument: the glasses' Play/Pause during a Gemini session. In the
# session's "call" the glasses still send AVRCP PLAY; Android drops it but logs
# "SendMessage to handle=..." (press + release; the handle number changes
# when the glasses reconnect, e.g. 0000 then 0x01), and Tasker runs this on that
# line. The same line is also logged when a media player changes (e.g. Gemini
# starts speaking) or the glasses connect, so only act when the last ~1 s of
# AVRCP logging is a clean press: 2-3 of those lines and no player updates.
if [ "$1" = button ]; then
  live_running || exit 0
  [ -f "$STATE/live_start" ] || exit 0
  now=$(date +%s)
  started=$(cat "$STATE/live_start")
  last=$(cat "$STATE/button" 2>/dev/null || echo 0)
  [ $((now - started)) -ge 8 ] || exit 0
  [ $((now - last)) -ge 5 ] || exit 0
  sleep 0.6
  t=$(date +%s.%N | cut -c1-14)
  verdict=$(logcat -d -v epoch -t 3000 | awk -v now="$t" '
    $1 + 0 >= now - 1.2 && /avrcp/ {
      if (/SendMessage to handle=/) h++
      else if (/SendMediaUpdate|SendFolderUpdate|SendPlayerSettings|MetadataChanged|TrackChanged|PlaybackPos|PlayerUpdate/) o++
    }
    END { print (h >= 2 && h <= 3 && o == 0) ? "press" : "other" }')
  [ "$verdict" = press ] || exit 0
  echo "$now" > "$STATE/button"
  rm -f "$STATE/live_start"
  end_live
  # Locked voice mode runs with Memo closed; bring it back so the glasses reconnect.
  if ! dumpsys activity services $MEMO | grep -q 'services.ForegroundService'; then
    sleep 1
    restart_memo
  fi
  echo stopped
  exit 0
fi

# "relaunch" argument: restart_memo.sh (Gemini has finished) uses the same
# relaunch as everything else.
if [ "$1" = relaunch ]; then
  restart_memo
  exit 0
fi

# "memo" argument: bring Memo back (Tasker calls this once Live is listening).
# Wait first: Memo reconnecting to the glasses right as the user starts
# talking can clip the start of the question.
if [ "$1" = memo ]; then
  sleep 4
  restart_memo
  exit 0
fi

# Memo's own assistant has just opened: closing the app hides it silently.
mark start
am force-stop $MEMO

# Second wake word while Live is running: end Live.
if live_running; then
  rm -f "$STATE/live_start"
  end_live
  restart_memo
  echo stopped
  exit 0
fi

# Locked: the Gemini app cannot open over the lock screen; use voice mode.
# Memo is reopened by the RestartMemo profile when Gemini lets go of audio.
if dumpsys window | grep -q 'isKeyguardShowing=true'; then
  tap_time=$(date +%s.%N | cut -c1-14)
  am start -a android.intent.action.VOICE_COMMAND -p $GEMINI -f 0x10000000 >/dev/null 2>&1
  date +%s > "$STATE/live_start"
  echo voice > "$STATE/mode"
  mark voice_opened
  # Same ready point as Live: the assistant holds audio focus and the glasses'
  # call audio link is open, so Tasker's chime is heard and means "talk now".
  i=0
  while [ $i -lt 20 ] && ! live_running; do
    i=$((i + 1))
    sleep 0.15
  done
  i=0
  while [ $i -lt 20 ] && ! logcat -d -T "$tap_time" 2>/dev/null | grep -q 'BT_SCO=on'; do
    i=$((i + 1))
    sleep 0.1
  done
  sleep 0.3
  mark ready
  echo voice
  exit 0
fi

# Unlocked: open the Gemini app (it does not start listening by itself) and
# tap its "Open Gemini Live" button once it is on screen and has stopped
# moving (seen at the same spot three times in a row). The app often draws the
# button low down first and then moves it up as the page fills in, and a tap
# at the old spot does nothing, so after each tap keep watching: Live taking
# audio focus means done; the button moving means tap again where it settles.
am start -n com.google.android.apps.bard/.shellapp.BardEntryPointActivity >/dev/null 2>&1
mark gemini_opened
tapped=0
last=
same=0
tap_time=
i=0
while [ $i -lt 60 ] && [ $tapped -eq 0 ]; do
  # A tap can start Live even when the button then jumps (Live's own screen
  # opening moves it), so check for Live on every pass, not only before a tap.
  [ -n "$tap_time" ] && live_running && { tapped=1; break; }
  spot=$(live_button)
  if [ -z "$spot" ]; then
    i=$((i + 1))
    sleep 0.1
    continue
  fi
  # Three reads in a row at the same spot (~0.35s still): the button slides
  # up as the page fills in, and a tap on a spot it is just leaving misses.
  if [ "$spot" = "$last" ]; then
    same=$((same + 1))
  else
    last=$spot
    same=1
  fi
  if [ $same -lt 3 ]; then
    i=$((i + 1))
    sleep 0.15
    continue
  fi
  tap_time=$(date +%s.%N | cut -c1-14)
  input tap $spot
  mark tap "$spot"
  # Up to ~1.6s for Live to start (it shows in ~0.3s). If the button has
  # moved, look again after 0.75s instead: never sooner, because Live opening
  # also moves it and a second tap must not land on Live's own screen.
  j=0
  moved=
  while [ $j -lt 8 ]; do
    live_running && { tapped=1; break; }
    now=$(live_button)
    if [ -z "$moved" ] && [ -n "$now" ] && [ "$now" != "$spot" ]; then
      moved=1
      mark moved "$now"
    fi
    [ -n "$moved" ] && [ $j -ge 5 ] && break
    j=$((j + 1))
    sleep 0.15
  done
  last=
  same=0
  i=$((i + j + 1))
done
[ $tapped -eq 1 ] || { restart_memo; echo failed; exit 1; }

# Wait until Live holds audio focus, i.e. it is really listening.
i=0
while [ $i -lt 20 ] && ! live_running; do
  i=$((i + 1))
  sleep 0.25
done
date +%s > "$STATE/live_start"
echo live > "$STATE/mode"
mark focus
# The glasses' call audio link (SCO) opens ~0.5s after Live takes focus and a
# beep sent before then is lost: wait for Android's "BT_SCO=on" log line
# (at most 2s), then a little more for the glasses to start playing it.
i=0
while [ $i -lt 20 ] && ! logcat -d -T "$tap_time" 2>/dev/null | grep -q 'BT_SCO=on'; do
  i=$((i + 1))
  sleep 0.1
done
mark sco_open
sleep 0.3
mark ready
# Tasker then beeps and runs "glasses_gemini.sh memo" so "Bye Memo" can be heard.
echo live
exit 0
