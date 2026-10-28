# Continue watching on Home (CleanYourTV launcher fork)

Status: draft for user review. Date: 2026-10-28.

## Goal
From Home, resume what the owner recently watched: a row of cards right under the dock, newest first, each with a
poster, the title (with "S1 E2" for episodes), and a thin progress bar. OK reopens the title in the app that
published it. Works on the owner's Fire TV Stick Lite (AFTSSS, Fire OS 7 / Android 9, 1 GB RAM) with the
CleanYourTV launcher already installed (com.gathin.tvhome 3.1, opened by dumbtv's Home hook).

Chosen by the owner (2026-10-28): titles + progress bar + posters.

## Facts this design rests on
- Measured, valid: a read-only probe app holding READ_TV_LISTINGS (tv.probe.wn, see README) read the standard
  TvProvider on this stick: watch_next_program 9 rows, all JioHotstar (8 "continue" with position and duration, 1
  "next episode"), preview_program 10 rows, channel 1. Rows carry package_name, title, season/episode numbers,
  watch_next_type, last_playback_position_millis, duration_millis, last_engagement_time_utc_millis,
  poster_art_uri (https), intent_uri (a deep link such as hotstar://in/...).
- Not seen by the probe: Netflix, Prime Video, YouTube, Apple TV, hoichoi. Without ACCESS_ALL_EPG_DATA a reader sees
  only its own rows plus rows marked searchable, so "not seen" is not "not published". Unknown until the owner
  plays something in each and the probe is re-run.
- The earlier "empty" finding came from `adb shell content query`, which cannot read the table; it is retracted.
- Rows linger: the oldest sample is from June; several sit at 93-94% of their length. A reader must filter.
- The launcher builds Home from one RecyclerView grid. AppAdapter keeps `items` of `Entry` (kinds APP,
  HOME_SETTINGS, CARD, EMPTY), assembled around AppAdapter.java:300-342; the dock is the first COLUMNS entries
  (docked count), then the grid.
- The built launcher declares no INTERNET and no READ_TV_LISTINGS today. Every module input is parsed inside its own
  try, a bad one is dropped with a log line, never a crash (Cards.java convention).
- Poster URIs are mostly https (a reader needs the network); some apps use content:// from their own provider.

## Design

### 1. Parts
- `ContinueRules` (pure Java, no Android): `select(rows, nowMs, maxAgeDays, hidePercent, max)` returns the rows to
  show, in order. No I/O. Host-testable.
- `WatchNextReader`: queries content://android.media.tv/watch_next_program with no selection (a selection needs a
  privilege a sideloaded app lacks) and no projection restrictions, maps cursor rows to `ContinueRules.Row`, drops
  malformed rows. SecurityException (permission not granted) or any failure returns an empty list.
- `PosterCache`: the only class that opens a network connection. Loads and caches posters.
- `AppAdapter`: a new `Entry.WATCH` kind, placed right after the dock entries and before the alphabetical grid, drawn
  with the existing tile size, focus zoom and glow.
- `MainActivity`: loads rows off the main thread on resume, hands them to the adapter, handles the click.

### 2. Filtering and order (ContinueRules)
- Keep `watch_next_type` 0 ("continue") only when duration > 0, position > 0, position/duration < `hidePercent`
  (default 92%) and age <= `maxAgeDays` (default 90).
- Keep type 1 ("next episode") when age <= `maxAgeDays`; it has no progress and shows as "Up next" without a bar.
- Drop every other type (new, watchlist) and any row missing a title or an intent_uri.
- A row with no engagement time has unknown age: kept, sorted after rows with a time.
- Order: engagement time, newest first; stable for ties. At most `max` rows (default 4, one row of the grid).
- At most one row per (package, title); the newest wins.
- Titles are cut to 60 characters. Season/episode shown only when both are present and positive.

### 3. Showing a card
- Tile content: the poster (CENTER_CROP over the tile), a dark gradient at the bottom, the title, "S1 E2" when
  known, and a 4 dp progress bar when a bar applies. While loading or when the poster fails (offline, bad URL,
  non-image) the card shows the publishing app's icon on a dark fill with the same title and bar.
- Focused: the existing tile focus. The line under the focused tile is `Title - S1 E2` (Entry.name).
- Ambient glow: the publishing app's colour, sampled the way the launcher already samples icons.
- WATCH entries are not reorderable, hideable or savable in the app order; they have a unique key
  `watch:<package>:<row id>` so saved order ignores them.

### 4. Opening a card
- Parse intent_uri with `Intent.parseUri(uri, Intent.URI_INTENT_SCHEME)`, add FLAG_ACTIVITY_NEW_TASK.
- Safety: the resolved activity's package must equal the row's package_name. If it does not, or the intent does not
  resolve, fall back to the app's normal launch intent; if that is absent too, do nothing.
- `LastOpened.record(ctx, pkg)` as for any app opened from Home.
- A deep link may open the app at a profile picker or the title page rather than mid-episode; that is the app's
  behaviour, not ours.

### 5. Posters and the internet permission
- Manifest adds `INTERNET` and `READ_TV_LISTINGS`. `INTERNET` is for posters only.
- `PosterCache` rules: https only (http, file and anything else refused); `content://` opened through ContentResolver
  with no network; `android.resource://` ignored. URL at most 2048 characters. Only for cards actually shown.
  Connect and read timeouts 5 s; at most 2 MB downloaded; decoded down-sampled to about the tile size, RGB_565.
  No cookies, no account, no custom identifiers; a neutral User-Agent. Disk cache in the launcher's cache dir keyed by
  the SHA-256 of the URL, at most 24 files and 24 MB, oldest evicted. One worker thread.
- The hosts come from data other apps publish, so only the same service the owner already uses sees the TV's IP.
- Android's default for targetSdk 34 blocks cleartext, which backs the https-only rule.
- This ends the launcher's "no INTERNET permission" property. The guarantee is by code: no class except
  PosterCache opens a connection (checked by a test that scans the sources for `HttpURLConnection`/`URL.openConnection`).
- Off switch: `continue_watching` false removes the row and stops all poster traffic. The original v3.1 APK stays
  the one-command fallback.

### 6. Settings (config.xml defaults, overridable in a theme's config.json)
| Key | Default | Meaning |
|---|---|---|
| `continue_watching` | false | Show the row. The owner's theme sets it to true. |
| `continue_max` | 4 | Cards in the row (1-8). |
| `continue_max_age_days` | 90 | Hide older rows. |
| `continue_hide_percent` | 92 | Hide rows watched at least this far. |
| `continue_posters` | true | Download posters; false shows the app icon fallback and makes no network request. |

### 7. Permissions on the TV
`READ_TV_LISTINGS` is a runtime permission; the owner (via me) grants it with
`adb shell pm grant com.gathin.tvhome android.permission.READ_TV_LISTINGS`. Without it the row does not appear and
nothing else changes. The launcher does not ask on screen.

### 8. Failure behaviour
No permission, no rows, a malformed row, a failed poster, no network, a full cache: each degrades to "no row" or
"card without a poster". None may throw out of the reader or the loader into Home. Rows load off the main thread;
the adapter changes only when the visible list differs from the last one (no flicker on every resume).

## Testing and gates
- Host unit tests (JUnit, in launcher/app/src/test like ThemeFilesTest): ContinueRules (type filter, 92% and age
  limits, episode label, ordering and tie order, per-title de-duplication, unknown-time rows, cap, title cut,
  malformed rows), PosterCache URL checks (https only, length, content:// allowed, others refused) and cache-key
  stability, and the "only PosterCache opens connections" source scan.
- Device checks: (a) the row shows the probe's JioHotstar rows with the same titles and bars as the probe printed;
  (b) revoke READ_TV_LISTINGS: no row, no crash; (c) block posters (continue_posters=false, then an unreachable
  URL): fallback cards; (d) click opens the right title; (e) Home handoff and smoothness gates re-measured against the
  current launcher: janky frames at most 10% while navigating, PSS at most 70 MB (now about 61 MB), Home handoff mean
  not slower than today's about 2.8 s + 0.5 s.
- Cross-check by re-running the probe: the launcher must show what the probe reads.

## Build and rollback
- Fork branch of the pinned commit (Gathin23/cleanyourtv fa1a2f0), vendor/cleanyourtv, local only, MIT notice kept.
- Build as before (JDK 17, Gradle 8.9, AGP 8.5.2, platform 34); installed over the current build with
  `adb install -r`: same package, same debug signing key, same versionCode (so downgrade back also works); the theme
  files and hidden-app list on the TV are untouched.
- Rollback: `adb install -r apk/cleanyourtv-launcher.apk` (the saved v3.1), or set continue_watching false.
- After this work, remove the probe app, the build tools and Gradle's cache again.

## Out of scope
Recommendation and preview rows; the watchlist; removing or editing rows (apps own them); showing apps that publish
nothing (Netflix etc., until proven); a recently-used-apps dock; weather; any other network feature.

## Risks and unknowns
- Only JioHotstar is proven to publish. If the owner mostly watches elsewhere, the row may be short or empty.
- Deep links are app-specific and may land on a profile picker.
- Adding INTERNET changes the launcher's privacy posture; mitigated by the code rules above, not enforceable by Android.
- MainActivity (3,595 lines) and AppAdapter (979) are large and were read only at the integration points; the plan
  starts by reading the assembly code (AppAdapter ~290-345) and the bind/click paths before editing.
- Upstream moves daily; the fork stays on the pinned commit and does not follow it.
