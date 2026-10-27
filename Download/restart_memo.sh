#!/system/bin/sh
# Reopen MemoMind after Gemini has finished, if we force-stopped it.
# Run through Shizuku when Gemini releases audio focus.
# Locked when Gemini let go of audio: it may be asking for an unlock (see below).
was_locked=
dumpsys window | grep -q 'isKeyguardShowing=true' && was_locked=1
sleep 2
# Gemini (voice or Live) still holds audio focus: it is not finished yet.
if dumpsys audio | sed -n '/Audio Focus stack entries/,/external focus policy/p' | grep -q 'com.google.android.googlequicksearchbox'; then
  exit 0
fi
# A phone call is still going (it may have been placed by Gemini): wait for it
# to end; the call releasing audio focus runs this script again.
if dumpsys telephony.registry 2>/dev/null | grep -q 'mCallState=[12]'; then
  exit 0
fi
# Memo's main service is running: nothing to restore.
if dumpsys activity services com.memomind.ai.aphrodite | grep -q 'services.ForegroundService'; then
  exit 0
fi
# The Gemini session is over: the glasses button should not end anything now.
rm -f /sdcard/Download/.glasses_gemini/live_start
# Only one of these waits at a time (Gemini can let go of audio several times).
LOCK=/sdcard/Download/.glasses_gemini/relaunch.lock
find "$LOCK" -maxdepth 0 -mmin +5 -exec rmdir {} \; 2>/dev/null
mkdir "$LOCK" 2>/dev/null || exit 0
trap 'rmdir "$LOCK" 2>/dev/null' EXIT
# Gemini lets go of audio when it asks for an unlock, and once unlocked it
# reopens its screen and carries on ~5s later (e.g. reading out the calendar).
# Opening Memo now would cut that off, so wait for it to speak again: letting
# go afterwards runs this script again. If it has not spoken within 15s,
# relaunch anyway so Memo is not left closed. Any other time Gemini goes quiet
# it has finished, so Memo comes straight back.
if [ -n "$was_locked" ] && ! dumpsys window | grep -q 'isKeyguardShowing=true' &&
  dumpsys activity activities | grep -m 1 'topResumedActivity' | grep -q 'com.google.android.googlequicksearchbox'; then
  waited=$(date +%s)
  while [ $(( $(date +%s) - waited )) -lt 15 ]; do
    if dumpsys audio | sed -n '/Audio Focus stack entries/,/external focus policy/p' | grep -q 'com.google.android.googlequicksearchbox'; then
      exit 0
    fi
    sleep 0.5
  done
fi
sh /sdcard/Download/glasses_gemini.sh relaunch
