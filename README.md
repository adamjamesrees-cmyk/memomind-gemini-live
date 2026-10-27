# MemoMind glasses + Gemini Live

Say "Hi Memo" to your MemoMind glasses and Gemini Live opens on your phone, listening through the glasses' mic and talking back through the glasses' speaker. A short chime tells you it's ready. Double press the glasses and pick Play/Pause to end it.

It works from the lock screen too. There you get Gemini's voice assistant instead of Live, and if it needs the phone unlocked for something (opening Maps, reading your calendar), unlock and it carries on.

It's free. You need Tasker and Shizuku, and a PC once for a single command.

This is an unofficial setup. It isn't made by or connected to MemoMind or Google.

## How it works

1. "Hi Memo" makes the MemoMind app write a line to the phone's log. Tasker watches for it.
2. Tasker runs a small script (through Shizuku) that closes Memo's own assistant, opens Gemini and presses its Live button.
3. Once Gemini is listening and the glasses' audio is connected, Tasker plays the chime.
4. Memo is reopened a few seconds later so the glasses stay connected, and the phone goes back to where you were.
5. Play/Pause on the glasses (or saying "Hi Memo" again) presses Gemini's End button.

## What you need

- MemoMind glasses and the MemoMind app, paired and working
- An Android phone with the Gemini app, signed in, with Gemini Live working
- [Tasker](https://play.google.com/store/apps/details?id=net.dinglisch.android.taskerm) (paid app)
- [Shizuku](https://github.com/RikkaApps/Shizuku/releases)
- A PC with [adb](https://developer.android.com/tools/releases/platform-tools), for one command

Tested on a Unihertz Titan 2 (Android 16) with MemoMind 1.3.81, Tasker 6.6.20, Shizuku 13.5.4 and the Google app 17.68. Other phones should work, but see "Things to know" below.

## Setup

### 1. Gemini

- Install Gemini, sign in, and make sure Gemini Live works when you open it yourself.
- Set Gemini as the phone's default digital assistant (Settings > Apps > Default apps > Digital assistant app). The lock screen version needs this.
- Connect the glasses and try Live once with them on. You should hear Gemini through the glasses.

### 2. Shizuku

- Install Shizuku and start it with Wireless debugging (the Shizuku app walks you through it).
- MediaTek phones: Shizuku 13.6.0 crashes on some MediaTek phones. If it won't start, install 13.5.4 from the [GitHub releases page](https://github.com/RikkaApps/Shizuku/releases) and turn off auto updates for it in the Play Store.
- Shizuku stops when the phone restarts. Open Shizuku and start it again after every restart.

### 3. Tasker permissions

- Install Tasker and open it once.
- In Shizuku, allow Tasker (Tasker asks for this the first time a task uses Shizuku, or allow it under Authorized apps in Shizuku).
- Give Tasker All files access (Android Settings > Apps > Tasker > Permissions > Files). It needs this to play the chime.
- Connect the phone to your PC with USB debugging on and run this once, so Tasker can read the phone's log:

```
adb shell pm grant net.dinglisch.android.taskerm android.permission.READ_LOGS
```

- Android sometimes shows an "Allow one-time access" box for Tasker's log access, mainly after a restart. Tap Allow.

### 4. Copy the files

To get the files, use the green Code button at the top of this page > Download ZIP, and unzip it.

Copy everything in this repo's `Download` folder into your phone's Download folder, so you end up with:

```
Download/glasses_gemini.sh
Download/restart_memo.sh
Download/glasses_chimes/ready.wav
```

The scripts expect exactly these paths.

### 5. Import the Tasker project

- Copy `Tasker/MemoMind_Gemini.prj.xml` to your phone.
- In Tasker, long press the house icon at the bottom left > Import Project > pick the file.
- You get a project called MemoMind Gemini with four profiles: Hi Memo, Gemini finished, Call ended and Glasses Play Pause. Make sure all four are switched on.
- Press back to leave Tasker so it saves.

### 6. MemoMind app

- Settings > Device > Quick Launch: put Play/Pause in one of the slots. That's the double press menu on the glasses.
- If you forward phone notifications to the glasses, turn Tasker off in that list, or Tasker's notifications end up on the glasses.

## Using it

- Say "Hi Memo". Wait for the chime, then talk.
- To finish: double press the glasses and choose Play/Pause, or say "Hi Memo" again.
- Live times out by itself after a minute or two of silence.
- Locked phone: same wake word. You get Gemini's voice assistant rather than Live, and the chime still tells you when to talk.

## Things to know

- The first start after a restart is slower (about 3 seconds before the chime). After that it's usually under 2.
- The Memo app pops up for about a second when it reopens. That's how it reconnects to the glasses.
- Ending Live shows Gemini on screen for a couple of seconds while the End button is pressed.
- The stop button relies on the phone logging the glasses' Play/Pause press. If Play/Pause doesn't end Live on your phone, say "Hi Memo" again instead.
- The End button is found by its English label ("End Live mode"). On a phone in another language, ending still works but closes the Google app instead, which makes the next start a bit slower.
- Gemini app updates could move or rename the Live button. If "Hi Memo" opens Gemini but Live never starts, that's the likely cause.
- The chime is a Google navigation sound that ships inside the MemoMind app. Swap in any short sound you like by replacing `ready.wav`.

## If something isn't working

- Check Shizuku is running and Tasker is allowed in it.
- Check the four profiles are on in Tasker.
- The script keeps a timing log at `Download/.glasses_gemini/timing.log` (a hidden folder). It shows each step of the last few starts, which helps narrow down where it stops.
