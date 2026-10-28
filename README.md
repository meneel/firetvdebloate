# firetvdebloate: a fast, ad-free, Apple-TV-style Home for the Fire TV Stick Lite

A reversible debloat plus a custom launcher for the **Fire TV Stick Lite** (Fire OS 7 / Android 9, 1 GB RAM, no root).
Home opens a full-screen "Featured" screen (new, recommended and top-rated films and shows that stream on **your** apps),
with a glass dock for your apps, Continue watching, weather, a Now Playing card, an Aurora screensaver, and apps closed
when you leave them. No ads, no tracking, nothing uninstalled.

<p align="center"><img src="docs/screenshots/featured-pirates.jpg" alt="Featured screen" width="860"></p>

> ### Read this first: forks, credits, no affiliation
> This repository is a **toolkit**. The launcher and the Home-button hook are **modified forks of other people's projects**,
> not my original work:
> - the launcher is a fork of **[CleanYourTV](https://github.com/Gathin23/cleanyourtv)** by **Gathin** (MIT) → [my fork](https://github.com/meneel/cleanyourtv), branch `continue-watching`;
> - the Home hook is a fork of **[dumbtv](https://github.com/humblemuzzu/dumbtv)** by the **dumbtv contributors** (MIT) → [my fork](https://github.com/meneel/dumbtv), branch `guard-target`.
>
> Their licences and copyright notices are kept; each fork says so in its README and in a `FORK.md` listing what changed. They are **not** the official
> projects and are not endorsed, maintained or supported by their authors. If you want the originals, use the links above.
> This project is also not affiliated with or endorsed by Amazon, Apple, TMDB, Netflix or any streaming service. "Fire TV", "Apple TV" and other names are
> trademarks of their owners, used only to say what this works with or what the look resembles; no Apple or Amazon assets are used.

> **Status:** one person's setup, built and tested on one stick. It works there; on other devices treat it as a starting point.
> Everything below is reversible, but read [Safety](#safety-and-rollback) first.

## Screenshots

**Featured Home.** Full-screen backdrops and details for new, recommended and top-rated titles that stream on *your* apps. Left/Right browses, OK opens details, Down brings the dock up.

<p><img src="docs/screenshots/featured-mission.jpg" alt="Another featured title" width="49%"> <img src="docs/screenshots/featured-pirates.jpg" alt="Featured title" width="49%"></p>

**Dock.** Down blurs the backdrop and lifts a glass dock with your apps; Up from the dock returns. Up again goes to the header (heavy blur).

<p><img src="docs/screenshots/dock.jpg" alt="Dock up over the blurred backdrop" width="49%"> <img src="docs/screenshots/header.jpg" alt="Header focused, heavy blur" width="49%"></p>

**Three Home looks**, switched in Settings → Home screen → Home page: Recommendations (above), Landscape (a generated sky for the hour) and Classic (your wallpaper).

<p><img src="docs/screenshots/landscape.jpg" alt="Landscape home" width="49%"> <img src="docs/screenshots/classic.jpg" alt="Classic home" width="49%"></p>

**Settings.** A left menu and one glass panel at a time.

<p><img src="docs/screenshots/settings-layout.jpg" alt="Settings: layout" width="49%"> <img src="docs/screenshots/settings-home.jpg" alt="Settings: home screen" width="49%"></p>
<p><img src="docs/screenshots/settings-motion.jpg" alt="Settings: motion and start" width="49%"> <img src="docs/screenshots/settings-system.jpg" alt="Settings: reset and system" width="49%"></p>

**Aurora screensaver.** Slow colour drift with the time, date and weather; it starts after 5 minutes idle and the TV sleeps after 2 hours (both configurable in the TV's own settings).

<p><img src="docs/screenshots/screensaver.jpg" alt="Aurora screensaver" width="49%"></p>

*Screenshots are from a real TV in Kolkata; posters and app logos belong to their owners.*

## What is in here

| Path | What it is |
|---|---|
| `fire.sh`, `tiers/` | Debloat: `backup`, `apply tier1 tier2 tier4`, `revert`, `status`. Only `pm disable-user` is used, so every change can be undone. Tier 3 (the Alexa voice stack) breaks the voice button and is not applied by default. |
| `vendor/cleanyourtv` | Submodule: my **modified fork** of [Gathin23/cleanyourtv](https://github.com/Gathin23/cleanyourtv) (original by Gathin, MIT), the launcher (branch `continue-watching`). Featured screen, glass dock, weather, Now Playing, screensaver, close-apps, settings. |
| `vendor/dumbtv` | Submodule: my **modified fork** of [humblemuzzu/dumbtv](https://github.com/humblemuzzu/dumbtv) (original by the dumbtv contributors, MIT) (branch `guard-target`). Its accessibility "Guard" makes the Home button open another launcher in about 2 to 3 seconds. |
| `themes/glass-firetv/` | Example launcher configuration (`config.device.json` is the live one). |
| `tools/` | Build wrapper, verification gates, a Home-handoff timer. |
| `docs/` | Design notes and plans; `docs/DEVLOG.md` is the build diary with measurements. |

## Quick start

You need a Mac or Linux machine with `adb`, JDK 17 and the Android SDK command-line tools, and a TV with
**Developer options → ADB debugging** on. Replace `<TV_IP>` with your stick's address.

```bash
git clone --recurse-submodules https://github.com/meneel/firetvdebloate.git && cd firetvdebloate
export FIRETV_IP=<TV_IP> ADB_SERIAL=<TV_IP>:5555
adb connect $ADB_SERIAL

# 1. Debloat (backs up first; nothing is uninstalled)
./fire.sh backup
./fire.sh apply tier1 tier2          # read tiers/*.txt first, they are plain package lists

# 2. Build and install the launcher
tools/cy-gradle.sh :app:assembleRelease
adb -s $ADB_SERIAL install -r vendor/cleanyourtv/launcher/app/build/outputs/apk/release/app-release.apk
adb -s $ADB_SERIAL shell pm grant com.gathin.tvhome android.permission.READ_TV_LISTINGS

# 3. Make Home open it (the dumbtv Guard), then point the Guard at the launcher
#    --build compiles the fork (it has the home_target feature; the upstream release APK does not) and signs it with a
#    key it creates locally. It also enables the accessibility service tv.dumbtv.home/.Guard.
bash vendor/dumbtv/launcher/install.sh --build
adb -s $ADB_SERIAL shell "echo 'home_target=com.gathin.tvhome/.MainActivity' >> /sdcard/Android/data/tv.dumbtv.home/files/home.conf"
#    (if that file does not exist yet, open dumbtv once, or see "Choosing which launcher Home opens" in docs/DEVLOG.md)

# 4. Optional: your launcher settings
touch themes/glass-firetv/config.device.json
adb -s $ADB_SERIAL push themes/glass-firetv/config.device.json /sdcard/Android/data/com.gathin.tvhome/files/config.json
```

Edit `dock_apps` in the config to your own packages (`adb shell pm list packages`). A pushed config **replaces** any
choices made in the on-TV settings screen, so back them up if you care.

### Recommendations need your own TMDB key
The Featured screen and the Recommended row use [The Movie Database](https://www.themoviedb.org) (free account → API
"Read Access Token"). Put it on the TV only, never in this repo:

```bash
printf '%s' 'YOUR_TMDB_READ_TOKEN' > /tmp/tmdb_token
adb -s $ADB_SERIAL push /tmp/tmdb_token /sdcard/Android/data/com.gathin.tvhome/files/tmdb_token && rm /tmp/tmdb_token
```
Region and provider ids are set in `TmdbRules` (India and Netflix, Prime, Apple TV, JioHotstar, hoichoi by default); change them for your country
and apps. Without a token the carousel and the Recommended row stay empty and everything else works.

## Privacy
No analytics. The launcher talks to three hosts only, enforced by a test (`OnlyPosterCacheOpensConnectionsTest`):
`api.open-meteo.com` (weather), `ipwho.is` (rough location from your IP, once a day) and `api.themoviedb.org` / `image.tmdb.org`.
Titles from your Watch Next row are sent to TMDB to find similar films. The Now Playing card needs a notification-listener grant to see other
apps' media sessions; it never reads notification text (also enforced by a test).

## Safety and rollback
- **Back up first** (`./fire.sh backup`). `./fire.sh revert backups/<timestamp>` re-enables everything disabled since that backup.
- Whole launcher off: `adb install -r` the original CleanYourTV APK, or remove `home_target` from dumbtv's config; Guard off:
  `adb shell settings put secure enabled_accessibility_services ""` then `bash vendor/dumbtv/launcher/install.sh --undo`.
- Fire OS may land on Amazon's stock Home after an install; open any app and press Home.
- You are changing system packages on your own device. It worked on mine; no warranty (see the licence).

## Build notes
`tools/cy-gradle.sh` wraps Gradle with Homebrew defaults (`JAVA_HOME`, `ANDROID_HOME` override them). Unit tests:
`tools/cy-gradle.sh :app:testDebugUnitTest`. `tools/cy-verify.sh` runs on-device checks (Home handoff, memory, jank); its thresholds
were tuned for one stick and are not gospel. Memory is tight on 1 GB: the Featured screen costs about 60 MB over the plain launcher.

## Credits and licences
- **This repository's own files** (`fire.sh`, `tools/`, `tiers/`, `themes/`, `docs/`, this README): MIT, Copyright (c) 2026 Indraneel Dutta (see `LICENSE`).
  That licence covers only those files, not the submodules.
- **Launcher: [CleanYourTV](https://github.com/Gathin23/cleanyourtv), Copyright (c) 2026 Gathin, MIT.** `vendor/cleanyourtv` is a modified fork; the original licence and
  copyright are kept in its `LICENSE`, and `FORK.md` lists what I changed. All credit for the original launcher and the TV-cleaning pipeline goes to its author.
- **Home hook: [dumbtv](https://github.com/humblemuzzu/dumbtv), Copyright (c) 2026 dumbtv contributors, MIT.** `vendor/dumbtv` is a modified fork with the same arrangement.
- Font: [Inter](https://rsms.me/inter/), Copyright (c) 2016 The Inter Project Authors, SIL Open Font License 1.1 (copy in `vendor/cleanyourtv/launcher/fonts/`).
- Film and show data and images: **This product uses the TMDB API but is not endorsed or certified by TMDB.**
- Weather by [Open-Meteo](https://open-meteo.com), location by [ipwho.is](https://ipwho.is).
- Screenshots show posters and app logos belonging to their owners. Fire TV, Amazon, Apple TV, Netflix and the other product names are trademarks of their respective owners.
- Not legal advice: if you redistribute or sell anything built from this, check the licences of the forks and of the services you connect to.
