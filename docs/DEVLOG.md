> Developer log of how this setup was built (one owner, one Fire TV Stick Lite). It is a diary, not a guide: start with the README. Package lists, numbers and device addresses are from that one TV (the address is replaced with `<TV_IP>`).

# Fire TV Stick Lite (AFTSSS, Fire OS 7) debloat
Everything is reversible: packages are only *disabled* (`pm disable-user`), never uninstalled.
Device IP default <TV_IP> (override: `FIRETV_IP=x.x.x.x ./fire.sh ...`). adb must be connected.

## Commands
- `./fire.sh backup`            snapshot package state + settings to backups/<ts>/
- `./fire.sh apply tier1 tier2 anim`   tier3 = Alexa voice stack (breaks the voice button; NOT applied)
- `./fire.sh launcher-on|launcher-off` Projectivy launcher (apk/projectivy.apk, v4.72, sha256 in apk/)
- `./fire.sh revert [dir]`      re-enable everything disabled since that backup + restore animation settings
- `./fire.sh status`

## Backups (revert targets)
- backups/20261027-223329  original state (revert with this = undo ALL of tier1+tier2+anim)
- backups/20261027-224506  after tier1+anim, before tier2 (revert with this = undo tier2 only)

## Full undo
    ./fire.sh launcher-off
    ./fire.sh revert backups/20261027-223329
    adb -s <TV_IP>:5555 reboot

## If Home looks broken
adb survives a reboot. `./fire.sh launcher-off` restores Amazon's home. Amazon's launcher was never disabled.
Five tier1 packages are protected by Amazon and refuse to disable (harmless). An OTA update may undo changes;
re-run `apply`. Block softwareupdates.amazon.com at the router to stop OTAs.

## Final state (2026-10-27)
Applied: tier1 (25 of 30; 5 protected), tier2 (14), anim 0.5x. NOT applied: tier3 (tried, reverted: voice button breaks, only ~1s gain).
Projectivy launcher tried and removed: Fire OS 7 hard-codes Amazon's launcher as Home (`set-home-activity` is ignored),
and the accessibility-hook handoff took ~5s every Home press. No non-root fix found (Launcher Manager has the same delay).
Ads: use Settings > Preferences > Featured Content / Privacy; optional DNS blocking not yet done.
Backups: 20261027-223329 original | 224506 after tier1 | 225521 after tier2+launcher, before tier3.
Full undo: ./fire.sh revert backups/20261027-223329

## Update: stock-launcher tuning
- secure.amz_limit_ad_tracking / non_amz_limit_ad_tracking = 1 (restored by `revert`; they live in the *secure* namespace)
- Disabled com.amazon.media.recommendations, com.amazon.providers.contentsupport (feed packages). Undo: `./fire.sh revert backups/20261027-230626`
- Caches trimmed (`pm trim-caches 999G`, ~260 MB). Launcher force-stop is refused (protected).
- Not yet verified: whether sponsored rows are gone (needs eyes on the TV) and RAM gain (re-measure after a day of use).
- Confirmed by user 2026-10-27: Home rows cleaner and feels faster after the feed-package + cache change.
- tier4 written from Gathin23/cleanyourtv Stick Lite list (not yet applied)

## dumbtv launcher (installed 2026-10-28)
- Source: github.com/humblemuzzu/dumbtv @755991b, cloned to vendor/dumbtv; only `launcher/install.sh` was run (APK v1.6, sha256-verified).
  It enables accessibility service tv.dumbtv.home/.Guard and sets global alarm_manager_constants=min_futurity=0 (was null).
- Why it is faster than Projectivy: Guard starts the launcher via an alarm PendingIntent sent by system_server, which is exempt from Android's 5s
  app-switch hold after Home. Log confirms: START from uid 1000, no "Activity start request ... stopped".
- Measured Home->dumbtv displayed (system log): 2.0, 3.5, 4.95, 3.7, ~2.9 s (was ~5s with Projectivy). Floor = Amazon's home loading (~1.7s) + dumbtv ~0.7s.
- UNDO: `ADB_SERIAL=<TV_IP>:5555 bash vendor/dumbtv/launcher/install.sh --undo` then `adb -s <TV_IP>:5555 uninstall tv.dumbtv.home`
  (fire.sh revert does not restore alarm_manager_constants; --undo does). Triple-press Home = Amazon's own fail-safe back to stock home.
- Couchy launcher: tried and removed 2026-10-28 (no Home capture on Fire OS).
- Confirmed by user 2026-10-28: Home works with the real remote on dumbtv launcher.

## tvOS launcher fork: toolchain (2026-10-28)
Spec approved: docs/superpowers/specs/2026-10-28-tvos-launcher-fork-design.md
Installed (brew): openjdk@17, android-commandlinetools; sdkmanager: platforms;android-25, build-tools;34.0.0 (513 MB at /opt/homebrew/share/android-commandlinetools).
Phase 0 build proven: `bash vendor/dumbtv/launcher/build.sh` -> launcher/build/dumbtv-home.apk (62 KB, own keystore launcher/release.keystore; NOT installed on TV).
Remove toolchain: brew uninstall --cask android-commandlinetools; brew uninstall openjdk@17.

## tvOS fork, plan 1 result (2026-10-28)
Fork: vendor/dumbtv, branch `tvos` (not pushed). Installed on the TV via `install.sh --build` (own keystore vendor/dumbtv/launcher/release.keystore: KEEP IT, updates must use the same key).
Config now: layout=tvos, tile_style=original, tiles=medium, background=midnight. tile_style=afterglow is upstream's own slow style on this stick: 70% janky frames, 66 MB (the official 1.6 release predates it, so it silently ignored that setting).
Gates (tools/tvos-verify.sh, HANDOFF_MAX=2.66): PSS 49.7 MB (<=60), janky 0% (<=10), Home handoff mean 2.32 s (<=2.66; release baseline 1.66 s, one 3.9 s outlier run).
Host tests: bash vendor/dumbtv/launcher/tests/run.sh (7 tests). Screenshots: scan/shots/tvos-*.png; references: scan/refs/.
ROLLBACK to the official release launcher:
  export ADB_SERIAL=<TV_IP>:5555
  bash vendor/dumbtv/launcher/install.sh --undo
  adb -s $ADB_SERIAL uninstall tv.dumbtv.home
  bash vendor/dumbtv/launcher/install.sh        # downloads release 1.6, checks sha256
  adb -s $ADB_SERIAL push backups/dumbtv-conf/home.conf.pre-fork /sdcard/Android/data/tv.dumbtv.home/files/home.conf
Note: the pre-fork config has tile_style=afterglow (ignored by the release); switch to layout=rows there if you prefer the stock look.

## Projectivy through dumbtv's Home hook (2026-10-28)
Branch `guard-target` of vendor/dumbtv (on top of `tvos`): Guard can start another launcher via the alarm path (home_target).
Why: Projectivy's own accessibility override starts its activity directly after Home, which Android holds ~5 s (log: "Activity start request ... stopped").
Guard launches through an alarm PendingIntent sent by system_server (exempt) with alarm_manager_constants min_futurity=0, behind a cover window.
Setup on the TV: Projectivy installed (apk/projectivy.apk, v4.72); ONLY tv.dumbtv.home/.Guard in enabled_accessibility_services (Projectivy's own service OFF);
home.conf has `home_target=com.spocky.projengmenu/.ui.home.MainActivity`.
Measured (tools/handoff-time.py, Home from Netflix): 2.06, 2.17, 2.37, 2.22 s, no held-start lines (vs 4.9-6.3 s with Projectivy's own override).
Switch back to dumbtv's own home: delete the home_target line from /sdcard/Android/data/tv.dumbtv.home/files/home.conf (no reinstall).
Known: Projectivy's tiles/Settings entry may not open Amazon's settings (Amazon keeps them inside its launcher); long-press Home opens Amazon's quick menu, and
`am start -n com.amazon.tv.launcher/.ui.MainSettingsActivity` opens settings directly (per Projectivy issue #338). Untested here.

## CleanYourTV's launcher through dumbtv's Home hook (2026-10-28)
Built from source (no prebuilt APK exists): vendor/cleanyourtv @fa1a2f0, `./gradlew :app:assembleRelease` (JDK 17, Gradle 8.9, AGP 8.5.2, Android platform 34 installed via sdkmanager).
APK: apk/cleanyourtv-launcher.apk (545 KB, v3.1, package com.gathin.tvhome, sha256 in apk/cleanyourtv-launcher.apk.sha256).
Audited: permissions ACCESS_NETWORK_STATE, ACCESS_WIFI_STATE, ACCESS_FINE_LOCATION (Wi-Fi name; NOT granted by me), WRITE_SECURE_SETTINGS, yandex TV permission; no INTERNET; no network code.
Its own accessibility helpers (HomeKeyService, InputKeyService) are NOT enabled; only tv.dumbtv.home/.Guard is.
Handoff (Home from Netflix): 3.76, 2.69, 3.05, 1.94, 2.79, 2.63 s (mean 2.81); 0 held-start lines. While navigating: 4.2% janky frames, PSS 61 MB.

## Choosing which launcher Home opens (one line in home.conf, no reinstall)
File: /sdcard/Android/data/tv.dumbtv.home/files/home.conf
  home_target=com.gathin.tvhome/.MainActivity                    CleanYourTV launcher   (Home ~2.8 s)
  home_target=com.spocky.projengmenu/.ui.home.MainActivity       Projectivy             (Home ~2.2 s)
  (delete the line)                                              dumbtv's own tvos home (Home ~2.3 s; release baseline 1.66 s)
Switch with e.g.: adb -s <TV_IP>:5555 shell "sed -i 's|^home_target=.*|home_target=com.spocky.projengmenu/.ui.home.MainActivity|' /sdcard/Android/data/tv.dumbtv.home/files/home.conf"

## Cleanup (2026-10-28)
Final choice: CleanYourTV's launcher (com.gathin.tvhome) opened through dumbtv's Home hook. Kept on the TV: tv.dumbtv.home (the hook + fallback screen) and com.gathin.tvhome.
Removed from the TV: Projectivy, Couchy, test files (/sdcard/s.png, test wallpaper). Removed from the Mac: JDK 17, Android command-line tools + SDK (677 MB), ~/.gradle (604 MB), yt-dlp, the cleanyourtv clone, Projectivy APK, reference images, scratch/temp files, in-progress screenshots.
KEPT on purpose: adb (brew android-platform-tools); ~/.android/adbkey (authorises this Mac with the TV) and ~/.android/debug.keystore (signed the CleanYourTV APK: installing a rebuild over it needs the same key);
vendor/dumbtv (fork: branches main/tvos/guard-target, 10 unpushed commits) with launcher/release.keystore and launcher/build/dumbtv-home.apk; apk/cleanyourtv-launcher.apk; backups/; fire.sh, tiers/, tools/.
To rebuild later: brew install openjdk@17; brew install --cask android-commandlinetools; sdkmanager --sdk_root=/opt/homebrew/share/android-commandlinetools "platforms;android-25" "build-tools;34.0.0"; then bash vendor/dumbtv/launcher/build.sh.
(CleanYourTV also needs platforms;android-34 and a fresh clone of github.com/Gathin23/cleanyourtv at fa1a2f0, then `./gradlew :app:assembleRelease`.)
To use Projectivy again: reinstall it, then set home_target=com.spocky.projengmenu/.ui.home.MainActivity (see above). Not installed now.

## Glass theme for CleanYourTV's launcher (2026-10-28)
Source: Gathin23/cleanyourtv themes/glass (config.json + wallpaper.jpg), adapted: dock_apps are this TV's apps (Netflix, YouTube com.amazon.firetv.youtube, Prime com.amazon.firebat, Apple TV, JioHotstar, hoichoi).
Kept in themes/glass-firetv/ (config.json, wallpaper.jpg). Pushed to /sdcard/Android/data/com.gathin.tvhome/files/ (config.json, wallpaper.jpg, theme_revision), then `am force-stop com.gathin.tvhome` + Home.
Added on top: hidden_apps [com.amazon.firetv.troubleshooting, tv.dumbtv.home] (hidden from view only, both stay installed; dumbtv is the Home hook), dock_glass true, app_library true + library_apps [com.amazon.venezia] (an "Appstore" tile on Home).
The launcher's dock has 4 slots; apps after the 4th flow into the grid row below.
Revert the theme: delete config.json, wallpaper.jpg, theme_revision in that files folder, force-stop com.gathin.tvhome, press Home. Pre-change config saved in backups/dumbtv-conf/cytv-config.before-hide.json.
Not done / not possible with this launcher's settings: dock of recently used apps (no such setting), a weather widget under the clock (launcher has no internet permission), an Appstore *install* button (the tile opens the Appstore app), a Fire-remote "Settings" button (the Lite remote has none).

## Nottilo trial (2026-10-28)
github.com/vuoshino/Nottilo (created 2026-10-27, 1 star, no licence, APK only, self-updating from GitHub). APK v1.0.9 sha256 2324e132...1a3a; kept only in scratch (not in the project).
Its "one command" is `pm grant app.nottilo.launcher android.permission.WRITE_SECURE_SETTINGS` so the app can enable its own accessibility service: the same mechanism as Projectivy (README admits Amazon's home flashes for seconds on Fire OS 7). NOT run: Nottilo was never granted WRITE_SECURE_SETTINGS.
Run through dumbtv's Home hook instead (home_target=app.nottilo.launcher/io.freemytv.HomeActivity): Home from Netflix 3.29, 2.66, 2.84, 2.37 s (mean 2.79), 0 held-start lines.
Audit limits: code is shrunk/renamed so SDK name checks were inconclusive. Hosts seen: api.themoviedb.org, www.omdbapi.com, api.watchmode.com, www.googleapis.com/youtube, api.open-meteo.com, drive.google.com, raw.githubusercontent.com (updates), ko-fi.com, api.binance.com/.us (unexplained), www.raiplay.it, www.netflix.com. Permissions: INTERNET, REQUEST_INSTALL_PACKAGES, WRITE_SECURE_SETTINGS, KILL_BACKGROUND_PROCESSES, READ_EPG_DATA, RECEIVE_BOOT_COMPLETED, accessibility, dream.
Needs the owner's own free TMDB key to show anything. Setup screen starts a LAN web server on port 8765 while open.
Try it:   adb -s <TV_IP>:5555 shell "sed -i 's|^home_target=.*|home_target=app.nottilo.launcher/io.freemytv.HomeActivity|' /sdcard/Android/data/tv.dumbtv.home/files/home.conf"
Back:     adb -s <TV_IP>:5555 shell "sed -i 's|^home_target=.*|home_target=com.gathin.tvhome/.MainActivity|' /sdcard/Android/data/tv.dumbtv.home/files/home.conf"
Remove:   adb -s <TV_IP>:5555 uninstall app.nottilo.launcher
Nottilo: uninstalled at the owner's request (2026-10-28). Home opens CleanYourTV via dumbtv's hook as before.

## Correction: Watch Next probe (2026-10-28)
Earlier note that Watch Next was "empty" on this stick came from `adb shell content query`, which cannot read it (the shell lacks READ_TV_LISTINGS), so it proved nothing.
Open question: do any of Netflix, YouTube, Prime, Apple TV, JioHotstar or hoichoi publish continue-watching rows readable by a sideloaded app? Needs a probe app holding READ_TV_LISTINGS.

## Watch Next probe result (2026-10-28) - VALID, read by an app holding READ_TV_LISTINGS
Probe app tv.probe.wn (read-only, 12 KB, built in scratch, installed on the TV, pm grant READ_TV_LISTINGS). Standard TvProvider on this Fire OS 7 stick DOES hold rows:
watch_next_program: 9 rows, all JioHotstar (in.startv.hotstar): 8 "continue" (type 0, with last_playback_position_millis + duration_millis) and 1 "next episode" (type 1); preview_program: 10 rows (JioHotstar "Top Picks For You" channel, deep links hotstar://in/...); channel: 1.
Posters are https:// (a reader needs INTERNET to show them; CleanYourTV has none). intent_uri deep links open the title in the app.
Not seen (visible to the probe): Netflix, Prime Video, YouTube, Apple TV, hoichoi. Without ACCESS_ALL_EPG_DATA a reader only sees its own rows plus rows marked searchable, so "none visible" is not "none published".

## Continue watching row (2026-10-28)
Fork: vendor/cleanyourtv, branch `continue-watching` on fa1a2f0 (local only, MIT). Build: apk/cleanyourtv-continue.apk (versionName 3.1-continue, versionCode 10, sha256 60f8750d..., same debug key as 3.1, installs over it in either direction).
What: a labelled "CONTINUE WATCHING" section under the dock: poster, title, "S5 E10 - Up next" or "51% watched", progress bar; OK reopens the publishing app (only that app). Needs `pm grant com.gathin.tvhome android.permission.READ_TV_LISTINGS` and `"continue_watching": true` in the theme. Settings: continue_max (4), continue_max_age_days (90), continue_hide_percent (92), continue_posters (true).
Privacy: INTERNET is held for posters only: PosterCache is the only class that opens a connection (OnlyPosterCacheOpensConnectionsTest). https only, 2 MB cap, 5 s timeouts, disk cache 24 files / 24 MB. `continue_posters: false` shows the app icon and makes no request.
Seen on this TV: only JioHotstar publishes; two cards qualify with the defaults.
Whole-branch review (fresh reviewer) found one real bug, fixed in commit "fix: Continue-watching cards leave the grid in reorder mode" (cards were movable and savable in reorder mode when fill_dock is on; control arm: old build keeps cards, fixed build hides them, scan/shots/cw-15, cw-16). Open, not fixed: poster decode bound (a crafted tall PNG could allocate 80-160 MB), reader keeps the first 200 rows unsorted, launchWatch re-resolves the intent (add setPackage), no read timeout on content:// posters, no tests for placeWatch/launchWatch/PosterCache limits.
Gates on the fixed build (scan/cy-verify-continue.txt): PSS 66 MB (limit 70; 53 MB on the earlier build, so it varies), jank 7.6% (limit 10), Home handoff mean 2.41 s (3.25 s on the earlier build; limit 3.3). Control arms on device: permission revoked = no row, no crash; posters off = icon cards, no poster log lines; feature off = no row; rollback to apk/cleanyourtv-launcher.apk (3.1) and back = ok.
Not verified: that a card lands on the exact title inside JioHotstar (its screen cannot be captured); the "READ_TV_LISTINGS is not granted" log line did not appear in logcat in the revoked arm (behaviour was correct); real remote.

## Session 2: hardening, Music & More, tier 4 (2026-10-28)
Fork commits: 73c3341 (reorder fix), ce4066d (hardening: poster decode capped at 2 M pixels via PosterRules.sampleSize + test, Watch Next read newest-first with fallback if the sort is refused, launchWatch setPackage + flags reset (device log shows pkg=in.startv.hotstar), stale refresh ignored). 308 unit tests green. Not done on purpose: content:// poster read timeout (same trust level as the app itself), tests for placeWatch/launchWatch (need Android classes; checked on the device instead).
Theme: com.amazon.audiohome added to hidden_apps (Home tiles only; the App library lists everything by design). Applied tier 4 (14 packages, backup backups/20261028-031113): this also removes Music & More from the library (17 -> 14 apps). Only 2 of the 14 were running (about 12 MB); the gain is ad-sync / Wi-Fi-password-upload / promo components that no longer wake, not speed. Tier 3 (Alexa voice stack) left alone: it broke the voice button when tried.
fire.sh fix: latest_backup picked backups/dumbtv-conf (sorts last) so `apply` skipped everything; now dated folders only.
Health after tier 4, before reboot: Home ok, probe reads 9 Watch Next rows, no crash/ANR. Reboot test: TV came back asking "Allow USB debugging?" (adb unauthorized): needs the owner to accept on screen. Post-reboot checks NOT yet done.
Undo tier 4: ./fire.sh revert backups/20261028-031113
Post-reboot findings (same night): reboot with tier 4 kept the Guard, home_target, disabled set and Home. adb needed one extra `adb connect` after the reboot to re-authorise.
Handoff gate after the reboot FAILED (4.24 s, then 3.47 s settled): swap was ~300 of 393 MB and com.amazon.firebat (Prime Video) sat resident at 91 MB, woken by its own WorkManager job + RTC_WAKEUP alarm. Set RUN_IN_BACKGROUND=ignore for firebat and venezia (Prime still opens). With Prime not resident, 6 clean runs: 2.62 3.13 1.71 3.06 2.88 3.10 = mean 2.75 s (gate 3.3). Evidence, not proof: the sample is small and single runs swing by 1 s. NOT verified: whether Prime is started again at boot despite the app-op (needs another reboot), and whether tier 4 itself had any effect on handoff (no A/B with tier 4 reverted).
Undo app-ops: adb shell cmd appops set <pkg> RUN_IN_BACKGROUND allow

## Weather line (2026-10-28)
Fork commit above. A line under the date: "Kolkata  26° · Overcast". Off by default; the theme turns it on (weather, weather_ip, weather_city/lat/lon = Kolkata fallback). Network: Net.java is the only text-GET path, https only, hosts fixed to api.open-meteo.com, ipwho.is (place from the TV's IP, once a day) and api.themoviedb.org (reserved for recommendations, not used yet); 5 s timeouts, 256 KB cap, no redirects, no cookies. Both services see the TV's public IP; nothing else is sent. Refresh: 30 min after a success, 5 min after a failure, in memory only (nothing written to disk). OnlyPosterCacheOpensConnectionsTest now allows PosterCache and Net.
Found by the control arm, not by the first unit test: ipwho.is returns indented JSON with spaces after colons; the first parser assumed compact JSON and the lookup silently fell back. Test now uses the captured real reply.
Device config currently = themes/glass-firetv/config.json + the experimental floating-dock look (dock_band false, cinematic_art 80, cinematic_white_focus, cinematic_scrim 70), awaiting the owner's reaction; the theme source does NOT contain those four look keys.

## Weather emoji, Home-screen settings, Now Playing, settings redesign (2026-10-28)
- Weather line: emoji by WMO code with moon/cloud at night (is_day), °C/°F switch. Verified on the TV: 27°C shows 81° in F.
- Launcher settings (header gear now opens it: launcher_settings_button true; it has a "TV settings" row): new "Home screen" card with switches for Now playing card, Continue watching row, Weather, Temperature unit, Dock background, Top shelf artwork. They are on-TV choices over the theme (SharedPreferences, keys in Config.HOME_KEYS). Verified through the remote: continue off/on, weather off/on, F. NOT yet exercised through the remote: dock background and top shelf switches (code path identical).
- A theme push resets every on-TV choice (existing launcher behaviour, extended to these keys). `adb push` keeps the file's mtime, so an unchanged file does NOT reset: `touch` it first.
- My own testing left "Apps per row" at 5 by a stray OK press; reset by touching + re-pushing the theme (back to 4). Lesson: drive settings with a screenshot between key bursts.
- Settings look redone: Outfit font, gradient background, four glass cards (Layout, Home screen, Motion and start, Reset and system), cyan focus ring, real switches, accent-coloured values. Screenshots scan/shots/set-1..4, home-reset2.png.
- Now Playing card (header, between the date and the top buttons): art, title, artist, previous / play-pause / next; hides when nothing plays; a paused session stays 2 minutes. Registers only while Home is on screen. Needs a notification-listener grant, because Android lists other apps' media sessions only for such a component: `adb shell cmd notification allow_listener com.gathin.tvhome/com.gathin.tvhome.NowPlayingListener` (undo: disallow_listener). The listener overrides nothing; NowPlayingNeverReadsNotificationsTest (with control arm) forbids any source from touching notifications. NOT granted yet: waiting for the owner's approval. Without the grant the card stays hidden and logs one line (verified, no crash). Spotify's session on this TV is visible in dumpsys (com.spotify.tv.android, state 3).
- Fork commit: see git log (branch continue-watching). 323 unit tests.
Now Playing grant: ENABLED 2026-10-28 with `cmd notification allow_listener com.gathin.tvhome/com.gathin.tvhome.NowPlayingListener` (owner approved). Undo: `adb shell cmd notification disallow_listener com.gathin.tvhome/com.gathin.tvhome.NowPlayingListener`. After the grant the "access is not granted" log line is gone (the sessions call succeeds). The card itself has NOT yet been seen with live playback: Spotify was paused (and its app dead) when tested, so the card correctly stayed hidden; pressing the play key only launched Spotify's UI. Needs a song started by the owner.
Now Playing VERIFIED on live Spotify (2026-10-28, screenshots scan/shots/np-3..np-7): the card shows art, title, artist; UP from the dock focuses Previous; OK on pause shows the play icon and OK again resumes; Next changed the track (title and art updated). The header's date/weather lines now stop short of the card (they ellipsize) via the card's width callback. Not tested live: the Previous button, the card hiding after playback stops or after 2 min paused (unit-tested rule only), and a session that publishes art only as a URI (Spotify sent a bitmap).

## Recommended for you (2026-10-28)
A second group under Continue watching: up to 6 films, each tagged with the streaming app that carries it in India ("JioHotstar · 2004"); OK opens that app (no deep link into the title). Source TMDB. Seeds: up to 3 films from Watch Next, one per series (their TITLES are sent to TMDB search); candidates = TMDB recommendations for the seeds ranked by position + rating, minus anything already in Watch Next, at most 2 per franchise (first two title words), only if flat-rate on an installed app (providers call per candidate); topped up from TMDB discover (popular, vote_count >= 300, rating >= 6.3) per installed app. Cache: files/recs-v2.tsv in the app's private dir, 12 h; Home never waits on the network. Token: `/sdcard/Android/data/com.gathin.tvhome/files/tmdb_token` on the TV only (pushed from a temp file; not in the project or the theme). Net sends the bearer only to api.themoviedb.org. Posters: image.tmdb.org via PosterCache. Config `recommendations` (theme true), a switch in Launcher settings. Control seen: first version returned six Harry Potter sequels, fixed with the franchise cap + one seed per series (test + screenshot rec-1/rec-2).
Not verified: pressing OK on a recommended card; behaviour with the token missing (code path returns null, one log line); TMDB rate limits (about 15 requests per 12 h).

## Aurora screensaver (2026-10-28)
`AuroraDream` (com.gathin.tvhome/.AuroraDream): three soft colour fields (hardware-layer views, only translated/scaled/faded, no per-frame redraw, no images or downloads) drift over near-black in colours by hour (night indigo/teal/violet, morning amber/rose/blue, day blue/aqua/violet, evening ember/magenta/indigo, dimmer after 21:00 and 23:00), with a 132sp thin clock, the date and the weather line (shared WeatherStore, refetched while dreaming). The clock block wanders over 90 s legs against burn-in. Any key wakes. Unit tests: AuroraRulesTest.
TV settings changed (originals in scan/screensaver-before.txt): secure screensaver_components and screensaver_default_component -> com.gathin.tvhome/.AuroraDream (were Amazon's com.amazon.ftv.screensaver, which tier 2 disabled); system screen_off_timeout stays 300000 (screensaver starts after 5 min idle); secure sleep_timeout 1200000 -> 7200000 (TV sleeps after 2 h idle, so about 1 h 55 min of screensaver). Revert: `adb shell settings put secure sleep_timeout 1200000` and put the two component values back.
Verified: the system itself started Aurora (wakefulness Dreaming, dream = AuroraDream) after the idle timer; screenshot scan/shots/au-2.png; the sleep timer puts the TV to sleep (log "Going to sleep due to screen timeout") using a 90 s test value. NOT verified: a full 2-hour run (not waited for), memory/heat over hours, and what woke the TV at 16:54 during the test (log: reason=android.policy:KEY, a key event I did not send; most likely the remote). There is no Fire OS entry point to launch a dream by hand (no Somnambulator): test by shortening screen_off_timeout.

## Featured carousel (2026-10-28)
A card on the right of the band above the dock (the app name stays on the left), turning every 8 s through up to 10 films and shows: recommended (similar to Watch Next films and one show, one series per seed), new (movies of the last 18 months, shows of the last 12, rating >= 6.5 / 7.0) and top rated (movies >= 7.5 with 3000+ votes, shows >= 8.0 with 1500+), interleaved, one title per franchise, only those that stream (flat rate, India) on an installed app. Tag (RECOMMENDED / NEW / TOP RATED), TMDB rating (NOT IMDb), type, year and "On Netflix · JioHotstar" on the card. UP from the dock focuses it, Left/Right turn it by hand (it holds still while focused), OK opens TitleActivity: backdrop, summary, rating and a "Watch on <app>" button per installed app. The button opens the app, not the title (the streaming apps expose no way to open a title from outside; Google offers no availability API, TMDB's provider data is JustWatch's). Cache files/featured-v1.tsv, 12 h; about 24 TMDB requests per refresh; same token file as Recs. Config `featured` (theme true), switch in Launcher settings. Code: FeaturedRules (+tests), Featured, FeaturedCarousel, TitleActivity.
Bug found on the device, not by tests: URLEncoder.encode(String, Charset) is Java 10 and crashed on Android 9 (NoSuchMethodError, the "featured" thread). Fixed with the two-argument-String overload. Host unit tests run on a newer JVM and lint did not flag it: new code that touches java.* APIs needs a run on the TV.
Not verified: the Watch button opening the app (result below if present), behaviour with no installed provider, a long soak, memory impact of ten 372x210 backdrops (about 6 MB).

## Featured as the full-screen Home (2026-10-28), blur and memory
Design: Home opens on the featured title full screen (header on top, the dock only peeks up under frosted glass). DOWN brings the dock up and the picture goes behind it, softly blurred; UP from the dock returns; UP from the featured screen goes to the music controls / settings (picture heavily blurred), DOWN returns. Left/Right browse, OK opens the title page. Config `featured`; the focused app's artwork and the glow are off while it is on.
First version failed on this GPU: stacked full-screen layers (picture + 3 scrims + dim + sky + glow) gave 85-93% janky frames even at idle and Graphics memory 68 MB. Measured states: idle dock-up or header-focused = 1-3 frames per 18 s (fine); the cost was the sharp screen's turn animation and the layers. Then the blur looked blocky (a tiny bitmap stretched with RGB_565 and no real blur) and the owner called blur and animation "trash".
Rebuilt: backdrops are baked once off the main thread (scrims drawn into the bitmap; soft = 384 px wide, Gaussian radius 7; heavy = 128 px, radius 22, via the platform's RenderScript ScriptIntrinsicBlur, the routine blur libraries use on Android 9; box-blur fallback, unit-tested), the turn is a slide of two opaque layers (no blending), blur levels fade one overlay at a time (260 ms), covered layers are hidden, the text block is not drawn off-screen. No live blur: a blur library that blurs views per frame would cost far more on this stick.
Memory: all backdrop bitmaps released in onStop and onTrimMemory (launcher 63 MB while inside Netflix, native heap 2.4 MB), RenderScript exists only while a picture is baked, the wallpaper decode is released while featured is up. Measured: featured screen 117 -> 106 MB, dock up 132 -> 115 MB; the launcher with featured OFF is 87 MB (it was 53-66 MB earlier in the session, before recommendations, now-playing, weather, etc.), featured adds about 5 MB at a fresh start.
Dock swap jank 13.5% -> 4.7%. Idle sharp screen still drops frames during the auto-turn slide (64% of 31 frames in 18 s), not during rest.
Gates (scan/cy-verify-final-session2.txt) FAIL: PSS 99 MB (limit 70, set for the original launcher), janky 10.02% (limit 10), handoff 7.2 s. The handoff is just as slow with featured OFF (5.2-6.1 s mean 5.8): the stick is at "status critical" memory with 320 of 393 MB of swap used; Spotify (playing) holds 112 MB, the test's Netflix 102 MB, the launcher 94 MB. Earlier clean runs were 2.4-3.3 s with Spotify not running. Not yet shown: handoff with Spotify stopped (needs the owner's OK to stop their music).

## Featured fixes, ambient light, close apps (2026-10-28, later)
- Long titles: size steps down (58 sp up to 27 chars, 44 up to 46, 36 beyond) and the summary drops to 2 lines under a 2-line title, so the text block no longer rises into the header (Harry Potter and the Prisoner of Azkaban collided with the clock; FeaturedRulesTest). Dock peek: recomputed on every grid layout (a fresh start laid the grid out after the first computation, so the peek was off screen).
- Stale blur: after a slide the soft/heavy copies still held the previous title (DOWN showed another title's blur). paintBlurs(index) on slide start, slide end and bitmap arrival. Reproduced and re-checked on the TV (bug-1/2, fix-1/2 screenshots).
- Ambient light over the blur: the focused app's colour at 40% (ambientMax 0.40 when featured is on).
- Close apps when I leave them (`close_apps`, switch in Launcher settings; KILL_BACKGROUND_PROCESSES, a normal permission): AppCloser asks Android to close every launchable app except music (package contains "spotify" or "music"), the launcher, dumbtv (the Home hook), Amazon's launcher and com.android.*, 2.5/9/25 s after Home returns. Fire OS archiving does not exist (Android 15 only). Two things hold an app above what an ordinary app may close: a running service (Netflix's NetflixService; fixed by `cmd appops set <pkg> RUN_IN_BACKGROUND ignore`, listed in scan/appops-restricted.txt) and being Android's "previous app" (fixed by BumpActivity: a window-less activity in its own process that finishes at once). Verified on the TV: Netflix, Apple TV, Hotstar closed after Home, Spotify kept playing, no crash. Not closeable: the Appstore (com.amazon.venezia is a protected package).
Mistake worth keeping: I removed BumpActivity after one success and then Hotstar stayed; the earlier success had both mechanisms. Test each mechanism alone before dropping one.

## Home page setting, landscape Home, settings redesign, hi-res art (2026-10-28, late)
- Home page (Launcher settings > Home screen > "Home page", cycles on OK): Recommendations (the full-screen featured screen), Landscape (a generated scene: sky for the hour, sun or moon with stars at night, four mountain ridges that change daily; LandscapeArt, 960x540, about 2 MB, redrawn when the mood or day changes, released when Home leaves the screen), Classic (the wallpaper Home). Stored as the on-TV choice `home_page`; a theme can default it with `featured` / `home_landscape`. Verified on the TV by switching through the settings screen (ls-1.png).
- Settings page rebuilt in the launcher's own look: left menu (Layout, Home screen, Motion and start, Reset and system), one glass panel at a time, the same generated landscape blurred behind it, focus = brighter glass slab with a white rim, switches, accent-coloured values. The panel is clipped to its rounded corners and fades its content at the edges; chips no longer wrap ("100%"). Screenshots st-3, st-6, st-8.
- Featured transitions: DOWN now takes the same two steps as UP (the blur fades first, then the dock slides), so both directions feel alike. The dock blur stays the readable soft one; the header-focus blur is the heavy one. (I briefly made the dock use the heavy blur on a guess about what "same blur" meant: it hid the artwork, reverted.)
- Hourly variety: caches are 1 h; TMDB page 1-3 and the shuffle follow the hour; new titles are applied when the viewer leaves the featured screen (never swapped under them).
- Artwork: TMDB `original` images (up to 4K), fetched through a LARGE PosterCache profile (8 MB on the wire, decoded to a full 1080p in 32-bit colour, mutable), the scrims and the progressive edge blur are baked in place, then the picture is stored as a dithered 16-bit copy and the 32-bit source dropped: no banding, half the memory. Disk cache raised to 48 files / 64 MB (backdrops are bigger).
- Measured: dock transitions 7.3% janky over 12 swaps (was 12%), 90th percentile 10 ms; memory featured 133 MB / dock up 146 MB (was 106 / 115 before the hi-res art; 162 / 174 with 32-bit kept resident). Frame-time breakdown showed the old up-transition was GPU-bound (fill rate), not UI-bound.
- Not verified: an hourly refresh actually changing the titles (needs an hour; unit-tested rules only), the first up-transition after a long time on the dock (a one-off hitch while its texture re-uploads: 93 ms worst frame), settings Motion/System sections after the clip fix (Layout and Home checked).

### 2026-10-28 evening: Apple-style look, smoother motion, memory profile
Inter font and sentence-case labels; glass dock rim; half-tile dock peek; wider milder top blur; titles sized by measured width; one easing, blur and dock slide sequenced both ways; carousel slide clipped to one fill per frame (jank 97.8% -> 24.8% on a fresh-start six-turn run; 99th percentile 48 -> 26 ms); two transition bugs fixed (cancelled fade on the way up, dock snapping). Memory A/B: upstream 68 MB, current all-off 80-84 MB, featured about +60 MB, landscape about +22 MB, weather/continue/recs nearly free. Commit `6da0906` (22 commits on fa1a2f0), APK sha256 `32b9bb5ed335...`. Details: HANDOVER.md section 11.
