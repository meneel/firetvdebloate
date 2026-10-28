# tvOS-style launcher: fork of dumbtv home for Fire TV Stick Lite

Status: draft for user review. Date: 2026-10-28.

## Goal
A Home screen that looks and feels like Apple TV, on a Fire TV Stick Lite (AFTSSS, Fire OS 7.7.1.7 / Android 9,
1 GB RAM, no root). It must keep the fast Home handoff already working (dumbtv `Guard`: alarm PendingIntent +
`min_futurity=0`, measured 2.0-4.95 s, mean ~3.4 s vs ~5 s for Projectivy) and stay ad-free.

Requested elements (user, 2026-10-28): dock with focus lift, top shelf, glass look, wallpapers + screensaver,
recently played titles with resume, content carousel.

## Facts this design rests on (measured on the device unless noted)
- Fire OS ignores `pm set-home-activity`, refuses disabling/force-stopping `com.amazon.tv.launcher`; Home is sent to
  that component explicitly. A background app's launch after Home is held ~5 s (Android `APP_SWITCH_DELAY_TIME`).
  dumbtv `Guard` avoids the hold with an alarm PendingIntent. Not re-derived here.
- dumbtv home: plain Java views, 3,148 lines, MIT. `Home.java` (1,075 lines) builds a `FrameLayout` root with
  wallpaper, shade and tint layers over a `ScrollView` of rows. Helpers: `Ui`, `Tile`, `AfterglowTile`, `FocusColor`
  (brand colour from the focused app), `Grid`, `Config` (home.conf), `Options`. About 25 MB PSS on this stick.
- CleanYourTV's launcher (MIT, builds from source only, no prebuilt APK, minSdk 26) is a source of ideas/code.
- Screenshots of non-DRM screens work over adb (`screencap`); Netflix blocks capture. Playback state is readable
  with `dumpsys media_session`.
- Android 9 has no AGSL shaders (Android 13) and no `RenderEffect` (Android 12). No live blur API.
- The standard Android TV "Watch Next" provider (`content://android.media.tv/watch_next_program`), preview programs
  and channels are all EMPTY on this stick after Netflix activity (result of the 2026-10-28 test; see Risks:
  the test did not confirm a real title was watched).
- dumbtv has no `INTERNET` permission by design.

## Design

### 1. Shape
New layout `layout=tvos` next to `rows` and `grid`. Existing layouts are untouched; leaving `layout=rows` restores
today's behaviour. Work happens in a git fork of `humblemuzzu/dumbtv` (MIT, notice kept). `Guard.java` is not
modified.

### 2. Screen
- Background: black, or the user's wallpaper with the existing adaptive colour.
- Top shelf: focused app name in large type above an ambient glow; glow colour from the existing `FocusColor`.
- Dock: about 6 favourite apps as rounded tiles. Focused tile lifts (about 1.12x scale plus shadow) with
  `ViewPropertyAnimator` (GPU-composited). One floating highlight view glides between tiles, replacing a per-tile ring.
- Down expands to the full grid using the existing `Grid`.

### 3. Glass (within Android 9 limits)
No live blur and no shaders. The dock band is a pre-blurred cached bitmap (blurred once per wallpaper change at
reduced resolution) with a translucent white layer and a hairline border.

### 4. Wallpapers and screensaver
Local images only (existing wallpaper folder). Optional slow pan, off by default. Screensaver (wallpaper slideshow +
clock) is a feasibility spike only: Amazon's screensaver is disabled (tier 2) and it is unverified that Fire OS 7
runs a third-party DreamService. May be cut.

### 5. Recently played and resume
- App-level recents: in scope (dumbtv already orders by recent use).
- Title-level "continue watching" with resume: NOT in v1. The only standard source (Watch Next) is empty here, and
  Amazon's own continue-watching goes through a provider that was not readable. It becomes a phase only if a
  re-test with a verified real viewing (user plays a title for 30 s with the remote while I read the table)
  shows rows. Resume would be an app deep link taken from the row's intent URI.
- Fallback if it never works: the dock shows recent apps; each app's own Continue Watching stays inside the app.

### 6. Content carousel
Optional, off by default, only after phases 1-3 ship. Source: TMDB trending/popular (free key, metadata and posters,
no account). Requires `INTERNET`, so it ships as a separate build flavor; the default build keeps dumbtv's
"cannot send anything anywhere" property. Tapping a title opens the relevant app or a search, not the title (per-app
deep links differ). No add-on/aggregator sources. DECISION NEEDED from the user before this phase.

### 7. Performance budget (hard gates)
Measure with `dumpsys gfxinfo tv.dumbtv.home framestats` and `dumpsys meminfo`. Budget: under about 60 MB PSS; under
10% janky frames while moving focus. Any effect over budget is cut or made an off-by-default toggle. Home handoff is
re-timed from the system log after every build and may not get slower than the current baseline (mean ~3.4 s).

### 8. Build and rollback
- Toolchain: JDK 17 and Android SDK (platform android-25 per `build.sh`, build-tools) via Homebrew/sdkmanager.
  Not installed yet; installing it needs the user's approval of this spec.
- The installed release is signed with a different key, so installing our build needs: back up `home.conf` (done:
  `backups/dumbtv-conf/home.conf.20261028.orig`), `install.sh --undo`, `adb uninstall tv.dumbtv.home`, then
  `install.sh --build`.
- Rollback: `--undo`, uninstall ours, run `install.sh` to restore the release; push saved `home.conf` back.
  Triple-press Home is Amazon's fail-safe to stock Home.

### 9. Phases (each ends with the user looking at the TV)
0. Toolchain + rebuild the UNCHANGED launcher; prove the pipeline and rollback.
1. `layout=tvos`: dock, top shelf, focus lift.
2. Cached-blur glass.
3. Wallpaper motion.
4. Screensaver feasibility spike.
5. Watch Next re-test; implement continue watching only if rows appear.
6. Optional TMDB carousel flavor (needs the user's go-ahead).

## Out of scope
Real glass refraction, Nuvio-style add-ons, weather, any default-build network access, replacing Amazon's launcher
process (protected).

## Risks and unknowns
- The Watch Next test is weak: Netflix opened in its home with auto-playing previews, so it is unconfirmed that a
  real title was watched, and Netflix blocks screenshots, so this was not verified visually.
- 1 GB RAM: glass and focus animation may exceed the budget; gates in section 7 decide.
- The Home hook works through an accessibility service; one report (CleanYourTV device notes, Fire OS 8) saw the
  physical remote's Home fail after a reboot while injected Home passed. Re-test with the real remote each build.
- Current `tile_style=afterglow` did not visibly change the tiles in a screenshot (original banners shown); the
  setting may need the Options screen or a restart. Unresolved, not needed for the fork.

## Correction (2026-10-28, later the same day)
The "Watch Next / preview programs / channels are all EMPTY on this stick" finding above is NOT valid. It came from
`adb shell content query`, and the shell does not hold READ_TV_LISTINGS, so that command prints "No result found"
whether or not any app publishes rows (Gathin23/cleanyourtv docs/watch-next.md says so). Whether any app on this
stick publishes continue-watching rows is UNKNOWN until it is read from an app that holds READ_TV_LISTINGS
(grantable with `pm grant <pkg> android.permission.READ_TV_LISTINGS`). Section 5 ("not in v1") rested on the invalid
probe. Fire OS may also route Home rows through Amazon's own provider (com.amazon.providers.tv) instead of the
standard TvProvider, which would make the standard table empty regardless.
