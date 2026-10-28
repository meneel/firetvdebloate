# Continue watching on Home: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Continue watching" row to the CleanYourTV launcher (a fork pinned at `fa1a2f0`): cards with poster, title, episode label and a progress bar, read from the TV's Watch Next provider, opening each title in the app that published it.

**Architecture:** Pure logic (`ContinueRules`, `PosterRules`) is Android-free and unit-tested. `WatchNextReader` reads the provider. `PosterCache` is the only class that opens a connection. `AppAdapter` gets a new `Entry.WATCH` kind inserted right after the dock; `MainActivity` loads rows off the main thread and hands them over. Settings arrive through the launcher's existing `config.xml` + theme `config.json` path.

**Tech Stack:** Java 8 syntax, Android views/RecyclerView as in the launcher, JUnit 4, Gradle 8.9 / AGP 8.5.2, compileSdk 34, minSdk 26.

**Spec:** `docs/superpowers/specs/2026-10-28-continue-watching-design.md`

## Global Constraints

- Work in the fork `vendor/cleanyourtv`, local branch `continue-watching`, based on the pinned commit `fa1a2f00f2b7b12c83b3bc539d91f32f4b1d4dd8`. Never push. MIT notices stay.
- No new libraries, no Kotlin. No regular expressions in the new code (the repo avoids them where ICU differs from the JVM); plain character loops.
- Only `PosterCache.java` may open a network connection (a unit test scans for this). `INTERNET` exists for posters only.
- Posters: https only; `content://` through ContentResolver; everything else refused. URL at most 2048 chars; download at most 2 MB; connect and read timeouts 5 s; decode down-sampled to about the tile size in RGB_565; disk cache at most 24 files and 24 MB.
- `continue_watching` defaults to false. Defaults: `continue_max` 4 (1-8), `continue_max_age_days` 90 (1-365), `continue_hide_percent` 92 (50-100), `continue_posters` true.
- Filtering: type 0 ("continue") needs duration > 0, position > 0, position/duration < hide percent, age <= max age; type 1 ("next") needs only age; every other type dropped; rows missing title, intent_uri or package dropped; newest first, unknown-time rows last; one row per (package, title); titles cut to 60 characters.
- A row's deep link opens only into the app that published it; otherwise fall back to that app's normal launch.
- Every failure (no permission, bad row, bad poster, no network) degrades to "no row" or "card without a poster" and never throws into Home.
- Keep `versionCode` unchanged (10) so `adb install -r` works in both directions; only `versionName` changes.
- Gates on the TV: janky frames at most 10% while navigating; launcher PSS at most 70 MB (now about 61); Home handoff mean at most 3.3 s (now about 2.8 s plus 0.5 s).
- Rollback: `adb install -r apk/cleanyourtv-launcher.apk` (saved v3.1) or `continue_watching` false.

## Review Focus

Failure modes the spec implies but happy-path tests would not exercise, most likely first:

1. `READ_TV_LISTINGS` not granted, or revoked: no row, no crash. (Task 8 Step 7; the reader's SecurityException branch.)
2. A hostile or broken poster URL (http, userinfo, huge, not an image, times out, redirects to http): fallback card, bounded memory, no crash. (Task 2 tests for the URL rules; Task 8 Step 8 on the device shows the fallback card. A real network failure is covered by the tests and code review, not forced on the device.)
3. A row whose deep link resolves to a different app than the row's publisher: must never open that other app. (Task 5 Step 3 `launchWatch`; Task 8 Step 5 checks the normal case on the device. A crafted mismatching row is covered by code review only, since only an app holding WRITE_EPG_DATA can publish one.)
4. The provider returns hundreds of stale, duplicate or half-empty rows: filtered and capped, off the main thread. (Task 1 tests; the reader's row limit.)
5. Settings flip at runtime: `continue_watching` false removes the row and all poster traffic; reorder mode never inserts the row. (Task 5 `placeWatch` guard; Task 8 Step 9.)

---

### Task 0: Branch, toolchain and a baseline test run

**Files:**
- Create: `tools/cy-gradle.sh` (project root `~/Developer/firetvdebloate/tools/`)

**Interfaces:**
- Produces: `tools/cy-gradle.sh <gradle args>`, which runs Gradle in `vendor/cleanyourtv/launcher` with the Homebrew JDK 17 and the Android SDK.

- [ ] **Step 1: Create the branch**

```bash
cd ~/Developer/firetvdebloate/vendor/cleanyourtv
git switch -c continue-watching
git log -1 --format='%H %s' | cut -c1-90
```
Expected: `Switched to a new branch 'continue-watching'` and the line `fa1a2f00f2b7b12c83b3bc539d91f32f4b1d4dd8 Safety: ...`.

- [ ] **Step 2: Install the Android 34 platform (the build tools and platform 25 are already there)**

```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
sdkmanager --sdk_root=/opt/homebrew/share/android-commandlinetools "platforms;android-34" 2>&1 | tr '\r' '\n' | grep -vE '^\[|^$|Loading|Fetch|Computing|Unzipping|Downloading' | tail -2
ls /opt/homebrew/share/android-commandlinetools/platforms
```
Expected: `android-25` and `android-34` listed.

- [ ] **Step 3: Write the Gradle wrapper script**

Create `tools/cy-gradle.sh`:

```bash
#!/usr/bin/env bash
# Runs Gradle in the CleanYourTV fork with the toolchain that brew + sdkmanager installed.
set -euo pipefail
export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools ANDROID_SDK_ROOT=/opt/homebrew/share/android-commandlinetools
cd "$(dirname "$0")/../vendor/cleanyourtv/launcher"
exec ./gradlew --no-daemon "$@"
```

```bash
chmod +x ~/Developer/firetvdebloate/tools/cy-gradle.sh
```

- [ ] **Step 4: Run the existing unit tests to prove the harness**

```bash
cd ~/Developer/firetvdebloate
tools/cy-gradle.sh :app:testDebugUnitTest > scan/cy-baseline-tests.log 2>&1; echo "exit=$?"
tail -5 scan/cy-baseline-tests.log
cat vendor/cleanyourtv/launcher/app/build/test-results/testDebugUnitTest/*.xml | grep -o 'tests="[0-9]*" skipped="[0-9]*" failures="[0-9]*"' | awk -F'"' '{t+=$2; f+=$6} END {print "tests="t" failures="f}'
```
Expected: `exit=0`, `BUILD SUCCESSFUL`, and `tests=<N> failures=0` with N more than 100. Note N in the ledger. This first run downloads Gradle and the Android plugin and may take several minutes.

---

### Task 1: `ContinueRules` (filtering, ordering, labels)

**Files:**
- Create: `vendor/cleanyourtv/launcher/app/src/main/java/com/gathin/tvhome/ContinueRules.java`
- Test: `vendor/cleanyourtv/launcher/app/src/test/java/com/gathin/tvhome/ContinueRulesTest.java`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `ContinueRules.Row(long id, String pkg, String title, String intentUri, String posterUri, int type, int season, int episode, long positionMs, long durationMs, long engagedMs)`
  - `ContinueRules.Card` with fields `key, pkg, title, subtitle, intentUri, posterUri` (Strings) and `float progress` (0..1, or -1 for "up next"), with `equals`/`hashCode`
  - `static List<Card> ContinueRules.select(List<Row> rows, long nowMs, int maxAgeDays, int hidePercent, int max)`
  - `static int ContinueRules.clamp(int value, int min, int max)`
  - constants `TYPE_CONTINUE=0, TYPE_NEXT=1, DEFAULT_MAX=4, MIN_MAX=1, MAX_MAX=8, DEFAULT_AGE_DAYS=90, MIN_AGE_DAYS=1, MAX_AGE_DAYS=365, DEFAULT_HIDE_PERCENT=92, MIN_HIDE_PERCENT=50, MAX_HIDE_PERCENT=100, TITLE_LIMIT=60`

- [ ] **Step 1: Write the failing test**

Create `ContinueRulesTest.java`:

```java
package com.gathin.tvhome;

import org.junit.Test;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

/** Which Continue-watching rows Home shows, in what order, and how a card reads. */
public class ContinueRulesTest {
    private static final long NOW = 1_800_000_000_000L;
    private static final long DAY = 24L * 60 * 60 * 1000;

    private static ContinueRules.Row cont(long id, String title, long pos, long dur, long daysAgo) {
        return new ContinueRules.Row(id, "app.a", title, "app://" + id, "https://img/" + id, ContinueRules.TYPE_CONTINUE,
                0, 0, pos, dur, NOW - daysAgo * DAY);
    }

    private static List<ContinueRules.Card> pick(List<ContinueRules.Row> rows) {
        return ContinueRules.select(rows, NOW, 90, 92, 4);
    }

    private static List<String> titles(List<ContinueRules.Card> cards) {
        List<String> out = new ArrayList<>();
        for (ContinueRules.Card c : cards) out.add(c.title);
        return out;
    }

    @Test
    public void startedTitlesShowWithProgress() {
        List<ContinueRules.Card> cards = pick(Arrays.asList(cont(1, "Film", 50_000, 100_000, 1)));
        assertEquals(1, cards.size());
        assertEquals(0.5f, cards.get(0).progress, 0.0001f);
    }

    @Test
    public void finishedTitlesAreHiddenAtTheLimit() {
        assertEquals(1, pick(Arrays.asList(cont(1, "A", 91_999, 100_000, 1))).size());
        assertEquals(0, pick(Arrays.asList(cont(2, "B", 92_000, 100_000, 1))).size());
    }

    @Test
    public void oldTitlesAreHiddenAfterTheAgeLimit() {
        assertEquals(1, pick(Arrays.asList(cont(1, "A", 10, 100, 90))).size());
        assertEquals(0, pick(Arrays.asList(cont(2, "B", 10, 100, 91))).size());
    }

    @Test
    public void notStartedOrBrokenProgressIsDropped() {
        assertEquals(0, pick(Arrays.asList(cont(1, "A", 0, 100_000, 1))).size());
        assertEquals(0, pick(Arrays.asList(cont(2, "B", 5_000, 0, 1))).size());
        assertEquals(0, pick(Arrays.asList(cont(3, "C", -5, 100, 1))).size());
    }

    @Test
    public void nextEpisodeShowsWithoutABar() {
        ContinueRules.Row next = new ContinueRules.Row(7, "app.a", "Show", "app://7", null, ContinueRules.TYPE_NEXT,
                5, 10, 0, 0, NOW - DAY);
        List<ContinueRules.Card> cards = pick(Arrays.asList(next));
        assertEquals(1, cards.size());
        assertEquals(-1f, cards.get(0).progress, 0f);
        assertEquals("S5 E10", cards.get(0).subtitle);
    }

    @Test
    public void otherTypesAreDropped() {
        ContinueRules.Row fresh = new ContinueRules.Row(1, "app.a", "New", "app://1", null, 2, 0, 0, 0, 0, NOW);
        ContinueRules.Row list = new ContinueRules.Row(2, "app.a", "Listed", "app://2", null, 3, 0, 0, 0, 0, NOW);
        assertEquals(0, pick(Arrays.asList(fresh, list)).size());
    }

    @Test
    public void episodeLabelNeedsBothNumbers() {
        ContinueRules.Row onlyEpisode = new ContinueRules.Row(1, "app.a", "A", "app://1", null, ContinueRules.TYPE_NEXT, 0, 3, 0, 0, NOW);
        ContinueRules.Row negative = new ContinueRules.Row(2, "app.a", "B", "app://2", null, ContinueRules.TYPE_NEXT, -1, -1, 0, 0, NOW - 1);
        List<ContinueRules.Card> cards = pick(Arrays.asList(onlyEpisode, negative));
        assertEquals("", cards.get(0).subtitle);
        assertEquals("", cards.get(1).subtitle);
    }

    @Test
    public void newestFirstAndUnknownTimeLast() {
        ContinueRules.Row unknown = new ContinueRules.Row(3, "app.a", "Unknown", "app://3", null, ContinueRules.TYPE_CONTINUE,
                0, 0, 10, 100, 0);
        List<ContinueRules.Card> cards = pick(Arrays.asList(cont(1, "Older", 10, 100, 20), unknown, cont(2, "Newer", 10, 100, 2)));
        assertEquals(Arrays.asList("Newer", "Older", "Unknown"), titles(cards));
    }

    @Test
    public void equalTimesKeepTheProviderOrder() {
        List<ContinueRules.Card> cards = pick(Arrays.asList(cont(1, "First", 10, 100, 5), cont(2, "Second", 10, 100, 5)));
        assertEquals(Arrays.asList("First", "Second"), titles(cards));
    }

    @Test
    public void oneCardPerPackageAndTitleNewestWins() {
        ContinueRules.Row other = new ContinueRules.Row(9, "app.b", "Same", "app://9", null, ContinueRules.TYPE_CONTINUE,
                0, 0, 10, 100, NOW - 3 * DAY);
        List<ContinueRules.Card> cards = pick(Arrays.asList(cont(1, "Same", 10, 100, 9), cont(2, "Same", 20, 100, 1), other));
        assertEquals(2, cards.size());
        assertEquals("app://2", cards.get(0).intentUri);
        assertEquals("app.b", cards.get(1).pkg);
    }

    @Test
    public void capAndEmptyInputs() {
        List<ContinueRules.Row> six = new ArrayList<>();
        for (int i = 1; i <= 6; i++) six.add(cont(i, "T" + i, 10, 100, i));
        assertEquals(4, ContinueRules.select(six, NOW, 90, 92, 4).size());
        assertEquals(6, ContinueRules.select(six, NOW, 90, 92, 8).size());
        assertEquals(0, ContinueRules.select(six, NOW, 90, 92, 0).size());
        assertEquals(0, ContinueRules.select(null, NOW, 90, 92, 4).size());
        assertEquals(0, ContinueRules.select(Collections.<ContinueRules.Row>emptyList(), NOW, 90, 92, 4).size());
    }

    @Test
    public void rowsMissingFieldsAreDropped() {
        ContinueRules.Row noTitle = new ContinueRules.Row(1, "app.a", "  ", "app://1", null, 0, 0, 0, 10, 100, NOW - DAY);
        ContinueRules.Row noLink = new ContinueRules.Row(2, "app.a", "B", null, null, 0, 0, 0, 10, 100, NOW - DAY);
        ContinueRules.Row noPackage = new ContinueRules.Row(3, null, "C", "app://3", null, 0, 0, 0, 10, 100, NOW - DAY);
        assertEquals(0, pick(Arrays.asList(null, noTitle, noLink, noPackage)).size());
    }

    @Test
    public void longTitlesAreCutWithAnEllipsis() {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < 100; i++) sb.append('x');
        String cut = pick(Arrays.asList(cont(1, sb.toString(), 10, 100, 1))).get(0).title;
        assertEquals(ContinueRules.TITLE_LIMIT, cut.length());
        assertTrue(cut.endsWith("…"));
    }

    @Test
    public void aCutNeverSplitsASurrogatePair() {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < 58; i++) sb.append('a');
        sb.append("😀");   // an emoji, two chars, straddling the cut
        for (int i = 0; i < 20; i++) sb.append('b');
        String cut = pick(Arrays.asList(cont(1, sb.toString(), 10, 100, 1))).get(0).title;
        assertTrue(cut.length() <= ContinueRules.TITLE_LIMIT);
        assertFalse(Character.isHighSurrogate(cut.charAt(cut.length() - 2)));
    }

    @Test
    public void keyNamesPackageAndRow() {
        assertEquals("watch:app.a:42", pick(Arrays.asList(cont(42, "T", 10, 100, 1))).get(0).key);
    }

    @Test
    public void sameRowsGiveEqualCards() {
        List<ContinueRules.Row> rows = Arrays.asList(cont(1, "T", 10, 100, 1));
        assertEquals(pick(rows), pick(rows));
        assertFalse(pick(rows).equals(pick(Arrays.asList(cont(1, "T", 11, 100, 1)))));
    }

    @Test
    public void clampKeepsSettingsInRange() {
        assertEquals(1, ContinueRules.clamp(-3, ContinueRules.MIN_MAX, ContinueRules.MAX_MAX));
        assertEquals(8, ContinueRules.clamp(99, ContinueRules.MIN_MAX, ContinueRules.MAX_MAX));
        assertEquals(4, ContinueRules.clamp(4, ContinueRules.MIN_MAX, ContinueRules.MAX_MAX));
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd ~/Developer/firetvdebloate && tools/cy-gradle.sh :app:testDebugUnitTest --tests 'com.gathin.tvhome.ContinueRulesTest' > /tmp/cw-t1.log 2>&1; echo "exit=$?"; grep -E "error:|cannot find symbol" /tmp/cw-t1.log | head -3
```
Expected: non-zero exit and `cannot find symbol ... ContinueRules`.

- [ ] **Step 3: Write the implementation**

Create `ContinueRules.java`:

```java
package com.gathin.tvhome;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Objects;
import java.util.Set;

/**
 * Which Continue-watching rows Home shows, in what order and how a card reads. No Android and no I/O, so a
 * host test pins it. The rows come from another app's data, so every field is treated as untrusted.
 */
final class ContinueRules {
    static final int TYPE_CONTINUE = 0, TYPE_NEXT = 1;
    static final int DEFAULT_MAX = 4, MIN_MAX = 1, MAX_MAX = 8;
    static final int DEFAULT_AGE_DAYS = 90, MIN_AGE_DAYS = 1, MAX_AGE_DAYS = 365;
    static final int DEFAULT_HIDE_PERCENT = 92, MIN_HIDE_PERCENT = 50, MAX_HIDE_PERCENT = 100;
    static final int TITLE_LIMIT = 60;
    private static final long DAY_MS = 24L * 60 * 60 * 1000;

    private ContinueRules() {
    }

    /** One row as the TV provider holds it. */
    static final class Row {
        final long id;
        final String pkg, title, intentUri, posterUri;
        final int type, season, episode;
        final long positionMs, durationMs, engagedMs;

        Row(long id, String pkg, String title, String intentUri, String posterUri, int type, int season, int episode,
            long positionMs, long durationMs, long engagedMs) {
            this.id = id;
            this.pkg = pkg;
            this.title = title;
            this.intentUri = intentUri;
            this.posterUri = posterUri;
            this.type = type;
            this.season = season;
            this.episode = episode;
            this.positionMs = positionMs;
            this.durationMs = durationMs;
            this.engagedMs = engagedMs;
        }
    }

    /** One card to show. Value equality lets Home skip a rebuild when nothing changed. */
    static final class Card {
        final String key, pkg, title, subtitle, intentUri, posterUri;
        /** 0..1 for a started title; -1 for "up next", which has no bar. */
        final float progress;

        Card(String key, String pkg, String title, String subtitle, String intentUri, String posterUri, float progress) {
            this.key = key;
            this.pkg = pkg;
            this.title = title;
            this.subtitle = subtitle;
            this.intentUri = intentUri;
            this.posterUri = posterUri;
            this.progress = progress;
        }

        @Override
        public boolean equals(Object o) {
            if (!(o instanceof Card)) return false;
            Card c = (Card) o;
            return key.equals(c.key) && pkg.equals(c.pkg) && title.equals(c.title) && subtitle.equals(c.subtitle)
                    && intentUri.equals(c.intentUri) && Objects.equals(posterUri, c.posterUri)
                    && Float.compare(progress, c.progress) == 0;
        }

        @Override
        public int hashCode() {
            return Objects.hash(key, pkg, title, subtitle, intentUri, posterUri, progress);
        }
    }

    static int clamp(int value, int min, int max) {
        return Math.max(min, Math.min(max, value));
    }

    /** The cards to show: filtered, newest first, one per (package, title), at most {@code max}. */
    static List<Card> select(List<Row> rows, long nowMs, int maxAgeDays, int hidePercent, int max) {
        if (rows == null || max < 1) return Collections.emptyList();
        long maxAgeMs = (long) maxAgeDays * DAY_MS;
        List<Row> kept = new ArrayList<>();
        for (Row r : rows) {
            if (r == null || blank(r.title) || blank(r.intentUri) || blank(r.pkg)) continue;
            if (r.engagedMs > 0 && nowMs - r.engagedMs > maxAgeMs) continue;
            if (r.type == TYPE_CONTINUE) {
                if (r.durationMs <= 0 || r.positionMs <= 0) continue;
                if (r.positionMs * 100 >= (long) hidePercent * r.durationMs) continue;
            } else if (r.type != TYPE_NEXT) {
                continue;
            }
            kept.add(r);
        }
        // Newest first; a row with no time is last. The sort is stable, so ties keep the provider's order.
        Collections.sort(kept, (a, b) -> {
            boolean ka = a.engagedMs > 0, kb = b.engagedMs > 0;
            if (ka != kb) return ka ? -1 : 1;
            return ka ? Long.compare(b.engagedMs, a.engagedMs) : 0;
        });
        Set<String> seen = new HashSet<>();
        List<Card> out = new ArrayList<>();
        for (Row r : kept) {
            String title = cut(r.title, TITLE_LIMIT);
            if (!seen.add(r.pkg + "\n" + title)) continue;
            String subtitle = r.season > 0 && r.episode > 0 ? "S" + r.season + " E" + r.episode : "";
            float progress = r.type == TYPE_CONTINUE ? (float) r.positionMs / (float) r.durationMs : -1f;
            out.add(new Card("watch:" + r.pkg + ":" + r.id, r.pkg, title, subtitle, r.intentUri, r.posterUri, progress));
            if (out.size() >= max) break;
        }
        return out;
    }

    private static boolean blank(String s) {
        return s == null || s.trim().isEmpty();
    }

    /** Trims, and cuts to {@code limit} characters ending in an ellipsis, never between the halves of an emoji. */
    private static String cut(String s, int limit) {
        String t = s.trim();
        if (t.length() <= limit) return t;
        int end = limit - 1;
        if (end > 0 && Character.isHighSurrogate(t.charAt(end - 1))) end--;
        return t.substring(0, end) + "…";
    }
}
```

- [ ] **Step 4: Run the tests**

```bash
cd ~/Developer/firetvdebloate && tools/cy-gradle.sh :app:testDebugUnitTest --tests 'com.gathin.tvhome.ContinueRulesTest' > /tmp/cw-t1.log 2>&1; echo "exit=$?"; tail -4 /tmp/cw-t1.log
grep -o 'tests="[0-9]*" skipped="[0-9]*" failures="[0-9]*"' vendor/cleanyourtv/launcher/app/build/test-results/testDebugUnitTest/TEST-com.gathin.tvhome.ContinueRulesTest.xml
```
Expected: `exit=0`, `BUILD SUCCESSFUL`, `tests="16" skipped="0" failures="0"`.

- [ ] **Step 5: Commit**

```bash
cd ~/Developer/firetvdebloate/vendor/cleanyourtv
git add launcher/app/src/main/java/com/gathin/tvhome/ContinueRules.java launcher/app/src/test/java/com/gathin/tvhome/ContinueRulesTest.java
git commit -q -m "feat: ContinueRules filters and orders Continue-watching rows

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
git log --oneline -1
```

---

### Task 2: `PosterRules` (URL rules, cache key, eviction) and the "only PosterCache opens connections" guard

**Files:**
- Create: `vendor/cleanyourtv/launcher/app/src/main/java/com/gathin/tvhome/PosterRules.java`
- Test: `vendor/cleanyourtv/launcher/app/src/test/java/com/gathin/tvhome/PosterRulesTest.java`
- Test: `vendor/cleanyourtv/launcher/app/src/test/java/com/gathin/tvhome/OnlyPosterCacheOpensConnectionsTest.java`

**Interfaces:**
- Consumes: nothing.
- Produces: `PosterRules.kind(String uri) -> int` (`NONE=0`, `NETWORK=1`, `CONTENT=2`); `PosterRules.key(String uri) -> String` (64 lower-case hex of SHA-256); `PosterRules.Cached(String name, long size, long modified)`; `PosterRules.evict(List<Cached>, int maxFiles, long maxBytes) -> List<String>` (names to delete, oldest first); constants `MAX_URI=2048`.

- [ ] **Step 1: Write the failing tests**

Create `PosterRulesTest.java`:

```java
package com.gathin.tvhome;

import org.junit.Test;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

/** Which poster addresses may be fetched, how they are cached and evicted. */
public class PosterRulesTest {
    @Test
    public void httpsWithAHostIsNetwork() {
        assertEquals(PosterRules.NETWORK, PosterRules.kind("https://img.example.com/p/1.jpg"));
        assertEquals(PosterRules.NETWORK, PosterRules.kind("HTTPS://Img.Example.com/p?x=1#y"));
        assertEquals(PosterRules.NETWORK, PosterRules.kind("https://img.example.com"));
    }

    @Test
    public void plainHttpAndOtherSchemesAreRefused() {
        assertEquals(PosterRules.NONE, PosterRules.kind("http://img.example.com/1.jpg"));
        assertEquals(PosterRules.NONE, PosterRules.kind("file:///sdcard/x.jpg"));
        assertEquals(PosterRules.NONE, PosterRules.kind("android.resource://app.a/1"));
        assertEquals(PosterRules.NONE, PosterRules.kind("ftp://host/x"));
        assertEquals(PosterRules.NONE, PosterRules.kind("javascript:alert(1)"));
    }

    @Test
    public void userInfoEmptyHostAndControlCharactersAreRefused() {
        assertEquals(PosterRules.NONE, PosterRules.kind("https://user:pw@host/x.jpg"));
        assertEquals(PosterRules.NONE, PosterRules.kind("https://host@evil.example/x.jpg"));
        assertEquals(PosterRules.NONE, PosterRules.kind("https:///x.jpg"));
        assertEquals(PosterRules.NONE, PosterRules.kind("https://?x"));
        assertEquals(PosterRules.NONE, PosterRules.kind("https://host/a b.jpg"));
        assertEquals(PosterRules.NONE, PosterRules.kind("https://host/a\nb.jpg"));
    }

    @Test
    public void nullEmptyAndTooLongAreRefused() {
        assertEquals(PosterRules.NONE, PosterRules.kind(null));
        assertEquals(PosterRules.NONE, PosterRules.kind(""));
        StringBuilder sb = new StringBuilder("https://host/");
        while (sb.length() <= PosterRules.MAX_URI) sb.append('a');
        assertEquals(PosterRules.NONE, PosterRules.kind(sb.toString()));
        assertEquals(PosterRules.NETWORK, PosterRules.kind(sb.substring(0, PosterRules.MAX_URI)));
    }

    @Test
    public void contentUrisAreAllowedButNeedAnAuthority() {
        assertEquals(PosterRules.CONTENT, PosterRules.kind("content://app.a.provider/posters/1"));
        assertEquals(PosterRules.NONE, PosterRules.kind("content://"));
    }

    @Test
    public void keyIsStableHexAndDiffersPerAddress() {
        String a = PosterRules.key("https://host/a.jpg");
        assertEquals(64, a.length());
        for (char c : a.toCharArray()) assertTrue("hex digit: " + c, Character.digit(c, 16) >= 0 && !Character.isUpperCase(c));
        assertEquals(a, PosterRules.key("https://host/a.jpg"));
        assertFalse(a.equals(PosterRules.key("https://host/b.jpg")));
    }

    private static List<PosterRules.Cached> files(long... sizeAndModified) {
        List<PosterRules.Cached> out = new ArrayList<>();
        for (int i = 0; i < sizeAndModified.length; i += 2) {
            out.add(new PosterRules.Cached("f" + (i / 2), sizeAndModified[i], sizeAndModified[i + 1]));
        }
        return out;
    }

    @Test
    public void nothingIsEvictedWithinTheLimits() {
        assertEquals(Collections.<String>emptyList(), PosterRules.evict(files(10, 1, 10, 2), 2, 100));
    }

    @Test
    public void oldestGoFirstWhenThereAreTooManyFiles() {
        // modified times: f0=30, f1=10, f2=20 -> oldest is f1, then f2
        assertEquals(Arrays.asList("f1"), PosterRules.evict(files(5, 30, 5, 10, 5, 20), 2, 1000));
        assertEquals(Arrays.asList("f1", "f2"), PosterRules.evict(files(5, 30, 5, 10, 5, 20), 1, 1000));
    }

    @Test
    public void oldestGoFirstWhenTheTotalSizeIsTooBig() {
        assertEquals(Arrays.asList("f1"), PosterRules.evict(files(60, 30, 50, 10, 40, 20), 10, 100));
        assertEquals(Arrays.asList("f1", "f2"), PosterRules.evict(files(60, 30, 50, 10, 40, 20), 10, 60));
    }
}
```

Create `OnlyPosterCacheOpensConnectionsTest.java`:

```java
package com.gathin.tvhome;

import org.junit.Test;

import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.List;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

/** The launcher holds INTERNET for posters only: no class but PosterCache may open a connection. */
public class OnlyPosterCacheOpensConnectionsTest {
    private static final String[] NEEDLES = {"openConnection(", "HttpURLConnection", "HttpsURLConnection",
        "new Socket(", "SocketFactory", "OkHttp", "DefaultHttpClient"};

    static void scan(File f, List<String> offenders) throws IOException {
        if (f.isDirectory()) {
            File[] kids = f.listFiles();
            if (kids != null) for (File kid : kids) scan(kid, offenders);
            return;
        }
        if (!f.getName().endsWith(".java") || f.getName().equals("PosterCache.java")) return;
        String text = new String(Files.readAllBytes(f.toPath()), StandardCharsets.UTF_8);
        for (String needle : NEEDLES) if (text.contains(needle)) offenders.add(f.getName() + ": " + needle);
    }

    @Test
    public void noOtherSourceOpensAConnection() throws IOException {
        File src = new File("src/main/java");
        assertTrue("run from the app module", src.isDirectory());
        List<String> offenders = new ArrayList<>();
        scan(src, offenders);
        assertEquals("only PosterCache may open connections: " + offenders, 0, offenders.size());
    }

    /** Control arm: the scan must fire on a file that does open a connection. */
    @Test
    public void theScanFindsAConnection() throws IOException {
        File dir = Files.createTempDirectory("scan").toFile();
        File bad = new File(dir, "Sneaky.java");
        Files.write(bad.toPath(), "class Sneaky { void f() throws Exception { new java.net.URL(\"https://x\").openConnection(); } }"
                .getBytes(StandardCharsets.UTF_8));
        List<String> offenders = new ArrayList<>();
        scan(dir, offenders);
        assertEquals(1, offenders.size());
        assertTrue(offenders.get(0).startsWith("Sneaky.java"));
        bad.delete();
        dir.delete();
    }
}
```

- [ ] **Step 2: Run them to verify the right failures**

```bash
cd ~/Developer/firetvdebloate && tools/cy-gradle.sh :app:testDebugUnitTest --tests 'com.gathin.tvhome.PosterRulesTest' --tests 'com.gathin.tvhome.OnlyPosterCacheOpensConnectionsTest' > /tmp/cw-t2.log 2>&1; echo "exit=$?"; grep -E "cannot find symbol" /tmp/cw-t2.log | head -2
```
Expected: non-zero exit, `cannot find symbol ... PosterRules`. (The scan test would pass on its own now, since nothing opens a connection yet; its control-arm test is what proves the scan can fire. They compile together, so both are red until Step 3.)

- [ ] **Step 3: Write the implementation**

Create `PosterRules.java`:

```java
package com.gathin.tvhome;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;

/**
 * Which poster addresses may be fetched, and the cache's key and eviction maths. No Android and no I/O, so a
 * host test pins it. Poster addresses come from other apps' data, so they are untrusted: plain character loops,
 * no regular expressions.
 */
final class PosterRules {
    static final int NONE = 0, NETWORK = 1, CONTENT = 2;
    static final int MAX_URI = 2048;

    private PosterRules() {
    }

    /** NETWORK for an https address with a host and no user info, CONTENT for a content:// address, else NONE. */
    static int kind(String uri) {
        if (uri == null || uri.isEmpty() || uri.length() > MAX_URI) return NONE;
        for (int i = 0; i < uri.length(); i++) {
            if (uri.charAt(i) <= ' ') return NONE;
        }
        String lower = uri.toLowerCase(Locale.ROOT);
        if (lower.startsWith("https://")) {
            String rest = uri.substring(8);
            int end = rest.length();
            for (int i = 0; i < rest.length(); i++) {
                char c = rest.charAt(i);
                if (c == '/' || c == '?' || c == '#') {
                    end = i;
                    break;
                }
            }
            String authority = rest.substring(0, end);
            if (authority.isEmpty() || authority.indexOf('@') >= 0) return NONE;
            return NETWORK;
        }
        if (lower.startsWith("content://")) return uri.length() > "content://".length() ? CONTENT : NONE;
        return NONE;
    }

    /** SHA-256 of the address as 64 lower-case hex characters: the cache file's name. */
    static String key(String uri) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(uri.getBytes(StandardCharsets.UTF_8));
            StringBuilder sb = new StringBuilder(64);
            for (byte b : digest) {
                sb.append(Character.forDigit((b >> 4) & 0xF, 16)).append(Character.forDigit(b & 0xF, 16));
            }
            return sb.toString();
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }

    /** One file in the poster cache. */
    static final class Cached {
        final String name;
        final long size, modified;

        Cached(String name, long size, long modified) {
            this.name = name;
            this.size = size;
            this.modified = modified;
        }
    }

    /** The names to delete, oldest first, until at most {@code maxFiles} files and {@code maxBytes} bytes remain. */
    static List<String> evict(List<Cached> files, int maxFiles, long maxBytes) {
        List<Cached> sorted = new ArrayList<>(files);
        Collections.sort(sorted, (a, b) -> Long.compare(a.modified, b.modified));
        long total = 0;
        for (Cached c : sorted) total += c.size;
        int count = sorted.size();
        List<String> drop = new ArrayList<>();
        for (Cached c : sorted) {
            if (count <= maxFiles && total <= maxBytes) break;
            drop.add(c.name);
            count--;
            total -= c.size;
        }
        return drop;
    }
}
```

- [ ] **Step 4: Run the tests and the whole suite**

```bash
cd ~/Developer/firetvdebloate && tools/cy-gradle.sh :app:testDebugUnitTest > /tmp/cw-t2.log 2>&1; echo "exit=$?"; tail -3 /tmp/cw-t2.log
for t in PosterRulesTest OnlyPosterCacheOpensConnectionsTest ContinueRulesTest; do printf "%s: " $t; grep -o 'tests="[0-9]*" skipped="[0-9]*" failures="[0-9]*"' vendor/cleanyourtv/launcher/app/build/test-results/testDebugUnitTest/TEST-com.gathin.tvhome.$t.xml; done
```
Expected: `exit=0`, `PosterRulesTest: tests="9" ... failures="0"`, `OnlyPosterCacheOpensConnectionsTest: tests="2" ... failures="0"`, `ContinueRulesTest: tests="16" ... failures="0"`, whole suite green.

- [ ] **Step 5: Commit**

```bash
cd ~/Developer/firetvdebloate/vendor/cleanyourtv
git add launcher/app/src/main/java/com/gathin/tvhome/PosterRules.java launcher/app/src/test/java/com/gathin/tvhome/PosterRulesTest.java launcher/app/src/test/java/com/gathin/tvhome/OnlyPosterCacheOpensConnectionsTest.java
git commit -q -m "feat: PosterRules (URL rules, cache key, eviction) and a guard that only PosterCache opens connections

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
git log --oneline -1
```

---

### Task 3: Settings, permissions and the version name

**Files:**
- Modify: `vendor/cleanyourtv/launcher/app/src/main/res/values/config.xml`
- Modify: `vendor/cleanyourtv/launcher/app/src/main/java/com/gathin/tvhome/Config.java`
- Modify: `vendor/cleanyourtv/launcher/app/src/main/AndroidManifest.xml`
- Modify: `vendor/cleanyourtv/launcher/app/build.gradle` (`versionName` only)
- Modify: `vendor/cleanyourtv/themes/README.md` (document the keys)

**Interfaces:**
- Consumes: `ContinueRules.MIN_MAX/MAX_MAX/MIN_AGE_DAYS/MAX_AGE_DAYS/MIN_HIDE_PERCENT/MAX_HIDE_PERCENT` (Task 1).
- Produces: `Config` fields `boolean continueWatching`, `int continueMax`, `int continueMaxAgeDays`, `int continueHidePercent`, `boolean continuePosters`, read from config.xml and overridable by a theme's `config.json` keys of the same names with the underscores (`continue_watching` etc.).

No host test is possible for `Config.load` (it needs a Context); the clamp limits are pinned by `ContinueRulesTest.clampKeepsSettingsInRange`, and the wiring is pinned by the device checks in Task 8. The build in Step 6 is the compile check.

- [ ] **Step 1: Add the config.xml defaults**

```bash
cd ~/Developer/firetvdebloate/vendor/cleanyourtv/launcher/app/src/main
python3 -I - <<'EOF'
p = 'res/values/config.xml'
s = open(p).read()
anchor = '    <bool name="dock_glass">false</bool>\n'
assert s.count(anchor) == 1
block = anchor + '''
    <!-- A "Continue watching" row right under the dock: titles other apps publish to the TV's Watch Next list, newest
         first, with a poster and a progress bar. Needs READ_TV_LISTINGS, granted with
         `pm grant com.gathin.tvhome android.permission.READ_TV_LISTINGS`. Off by default. Can also be set with
         "continue_watching": true in a theme's config.json. -->
    <bool name="continue_watching">false</bool>
    <!-- Cards in the row (1 to 8). -->
    <integer name="continue_max">4</integer>
    <!-- Hide rows last watched more than this many days ago (1 to 365). -->
    <integer name="continue_max_age_days">90</integer>
    <!-- Hide rows watched at least this far, in percent (50 to 100). -->
    <integer name="continue_hide_percent">92</integer>
    <!-- Download posters over https (the launcher's only network use). false shows the app's icon instead and makes
         no network request. -->
    <bool name="continue_posters">true</bool>
'''
open(p, 'w').write(s.replace(anchor, block))
print("config.xml ok")
EOF
```
Expected: prints `config.xml ok`.

- [ ] **Step 2: Wire the five settings into `Config.java`**

First list every place the neighbouring `inputsConnectedOnly` and `dockGlass` settings are wired, so the anchors below can be checked by eye:

```bash
cd ~/Developer/firetvdebloate/vendor/cleanyourtv/launcher/app/src/main/java/com/gathin/tvhome
grep -n "inputsConnectedOnly\|boolean dockGlass\|\"dock_glass\"" Config.java | cut -c1-150
```
Expected: lines for the field, the constructor parameter ending `boolean inputsConnectedOnly) {`, the assignment `this.inputsConnectedOnly = inputsConnectedOnly;`, the `load` default, the overlay line and the `new Config(` call ending `inputsConnectedOnly);`.

Then edit (every anchor must match exactly once, or the script stops without writing):

```bash
python3 -I - <<'EOF'
p = 'Config.java'
s = open(p).read()

def once(old, new):
    global s
    assert s.count(old) == 1, ("anchor not found exactly once", old[:70])
    s = s.replace(old, new)

once('    final boolean dockGlass;\n',
     '    final boolean dockGlass;\n'
     '    /** The Continue-watching row (config.xml continue_*, or a theme): shown, its card count, age and progress limits, posters. */\n'
     '    final boolean continueWatching;\n'
     '    final int continueMax, continueMaxAgeDays, continueHidePercent;\n'
     '    final boolean continuePosters;\n')
once('boolean inputsConnectedOnly) {',
     'boolean inputsConnectedOnly,\n'
     '                   boolean continueWatching, int continueMax, int continueMaxAgeDays, int continueHidePercent,\n'
     '                   boolean continuePosters) {')
once('        this.inputsConnectedOnly = inputsConnectedOnly;\n',
     '        this.inputsConnectedOnly = inputsConnectedOnly;\n'
     '        this.continueWatching = continueWatching;\n'
     '        this.continueMax = continueMax;\n'
     '        this.continueMaxAgeDays = continueMaxAgeDays;\n'
     '        this.continueHidePercent = continueHidePercent;\n'
     '        this.continuePosters = continuePosters;\n')
once('        boolean dockGlass = res.getBoolean(R.bool.dock_glass);\n',
     '        boolean dockGlass = res.getBoolean(R.bool.dock_glass);\n'
     '        boolean continueWatching = res.getBoolean(R.bool.continue_watching);\n'
     '        int continueMax = res.getInteger(R.integer.continue_max);\n'
     '        int continueMaxAgeDays = res.getInteger(R.integer.continue_max_age_days);\n'
     '        int continueHidePercent = res.getInteger(R.integer.continue_hide_percent);\n'
     '        boolean continuePosters = res.getBoolean(R.bool.continue_posters);\n')
once('            dockGlass = bool(json, "dock_glass", dockGlass);\n',
     '            dockGlass = bool(json, "dock_glass", dockGlass);\n'
     '            continueWatching = bool(json, "continue_watching", continueWatching);\n'
     '            continueMax = integer(json, "continue_max", continueMax, ContinueRules.MIN_MAX, ContinueRules.MAX_MAX);\n'
     '            continueMaxAgeDays = integer(json, "continue_max_age_days", continueMaxAgeDays,\n'
     '                    ContinueRules.MIN_AGE_DAYS, ContinueRules.MAX_AGE_DAYS);\n'
     '            continueHidePercent = integer(json, "continue_hide_percent", continueHidePercent,\n'
     '                    ContinueRules.MIN_HIDE_PERCENT, ContinueRules.MAX_HIDE_PERCENT);\n'
     '            continuePosters = bool(json, "continue_posters", continuePosters);\n')
once('locale, powerOnHomeAlways, inputsConnectedOnly);',
     'locale, powerOnHomeAlways, inputsConnectedOnly,\n'
     '                continueWatching, ContinueRules.clamp(continueMax, ContinueRules.MIN_MAX, ContinueRules.MAX_MAX),\n'
     '                ContinueRules.clamp(continueMaxAgeDays, ContinueRules.MIN_AGE_DAYS, ContinueRules.MAX_AGE_DAYS),\n'
     '                ContinueRules.clamp(continueHidePercent, ContinueRules.MIN_HIDE_PERCENT, ContinueRules.MAX_HIDE_PERCENT),\n'
     '                continuePosters);')
open(p, 'w').write(s)
print("Config.java ok")
EOF
```
Expected: prints `Config.java ok`. (A config.xml value outside the limits is clamped by the last edit; the theme path clamps through `integer(...)`.)

- [ ] **Step 3: Declare the two permissions**

```bash
cd ~/Developer/firetvdebloate/vendor/cleanyourtv/launcher/app/src/main
python3 -I - <<'EOF'
p = 'AndroidManifest.xml'
s = open(p).read()
anchor = '    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />\n'
assert s.count(anchor) == 1
block = anchor + '''    <!-- Continue watching: reads the rows other apps publish to the TV's Watch Next list. A runtime permission,
         granted with `pm grant com.gathin.tvhome android.permission.READ_TV_LISTINGS`; without it there is no row. -->
    <uses-permission android:name="android.permission.READ_TV_LISTINGS" />
    <!-- Posters for the Continue-watching row, and nothing else: PosterCache is the only class that opens a
         connection (OnlyPosterCacheOpensConnectionsTest). https only; continue_posters false makes no request. -->
    <uses-permission android:name="android.permission.INTERNET" />
'''
open(p, 'w').write(s.replace(anchor, block))
print("manifest ok")
EOF
```
Expected: prints `manifest ok`.

- [ ] **Step 4: Name the fork's version, and keep the version code**

```bash
cd ~/Developer/firetvdebloate/vendor/cleanyourtv/launcher/app
grep -n "versionCode\|versionName" build.gradle
python3 -I - <<'EOF'
p = 'build.gradle'
s = open(p).read()
assert s.count('versionName "3.1"') == 1, "versionName line not as expected: edit by hand"
open(p, 'w').write(s.replace('versionName "3.1"', 'versionName "3.1-continue"'))
print("versionName ok")
EOF
```
Expected: the grep shows `versionCode 10` and `versionName "3.1"`; the script prints `versionName ok`. (If the grep shows different quoting, stop and set the name by hand; do not touch `versionCode`.)

- [ ] **Step 5: Document the keys in the themes table**

```bash
cd ~/Developer/firetvdebloate/vendor/cleanyourtv/themes
python3 -I - <<'EOF'
p = 'README.md'
lines = open(p).read().split('\n')
idx = [i for i, l in enumerate(lines) if l.startswith('| `dock_glass` |')]
assert len(idx) == 1, "dock_glass row not found exactly once"
rows = [
 '| `continue_watching` | bool | A Continue-watching row right under the dock: titles other apps publish to the TV\'s Watch Next list, newest first, with a poster and a progress bar. Needs `READ_TV_LISTINGS` (`pm grant com.gathin.tvhome android.permission.READ_TV_LISTINGS`). `false` by default |',
 '| `continue_max` | 1 to 8 | Cards in that row (4 by default) |',
 '| `continue_max_age_days` | 1 to 365 | Hide rows last watched longer ago than this (90 by default) |',
 '| `continue_hide_percent` | 50 to 100 | Hide rows watched at least this far (92 by default) |',
 '| `continue_posters` | bool | Download posters over https, the launcher\'s only network use; `false` shows the app\'s icon and makes no request (`true` by default) |',
]
lines[idx[0] + 1:idx[0] + 1] = rows
open(p, 'w').write('\n'.join(lines))
print("themes README ok")
EOF
```
Expected: prints `themes README ok`.

- [ ] **Step 6: Compile and run the whole unit-test suite**

```bash
cd ~/Developer/firetvdebloate && tools/cy-gradle.sh :app:testDebugUnitTest > /tmp/cw-t3.log 2>&1; echo "exit=$?"; grep -E "error:|BUILD" /tmp/cw-t3.log | head -5
```
Expected: `exit=0`, `BUILD SUCCESSFUL`. A compile error here means an anchor edit in Step 2 went wrong; fix and rerun before committing.

- [ ] **Step 7: Commit**

```bash
cd ~/Developer/firetvdebloate/vendor/cleanyourtv
git add launcher/app/src/main/res/values/config.xml launcher/app/src/main/java/com/gathin/tvhome/Config.java launcher/app/src/main/AndroidManifest.xml launcher/app/build.gradle launcher/themes/README.md 2>/dev/null || git add -A launcher themes
git commit -q -m "feat: continue_* settings, READ_TV_LISTINGS and INTERNET permissions, version name 3.1-continue

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
git status --short | head -3; git log --oneline -1
```
Expected: clean status and the new commit. (`themes/README.md` is at the repo root `themes/`, not under `launcher/`; the fallback `git add -A launcher themes` covers it.)

---

### Task 4: `WatchNextReader`

**Files:**
- Create: `vendor/cleanyourtv/launcher/app/src/main/java/com/gathin/tvhome/WatchNextReader.java`

**Interfaces:**
- Consumes: `ContinueRules.Row`, `ContinueRules.select(...)`, `ContinueRules.Card` (Task 1).
- Produces: `static List<ContinueRules.Card> WatchNextReader.read(Context ctx, long nowMs, int maxAgeDays, int hidePercent, int max)`: never throws; empty on no permission or any failure.

No host test: it needs a ContentResolver. The filtering it feeds is covered by Task 1; the permission-missing branch is checked on the device in Task 8 Step 7. The build is the compile check.

- [ ] **Step 1: Write the reader**

Create `WatchNextReader.java`:

```java
package com.gathin.tvhome;

import android.content.Context;
import android.database.Cursor;
import android.net.Uri;
import android.util.Log;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * Reads the Continue-watching rows other apps publish to the TV provider (docs/watch-next.md). Needs the
 * READ_TV_LISTINGS permission; without it, or on any failure, the answer is an empty list and Home shows no row.
 * A query with a selection needs a privilege a sideloaded app lacks, so the whole table is read and ContinueRules
 * does the filtering. Nothing from a row is logged.
 */
final class WatchNextReader {
    private static final String TAG = "TvHomeWatch";
    private static final Uri WATCH_NEXT = Uri.parse("content://android.media.tv/watch_next_program");
    /** A provider can hold hundreds of stale rows; read no more than this. */
    private static final int ROW_LIMIT = 200;

    private WatchNextReader() {
    }

    static List<ContinueRules.Card> read(Context ctx, long nowMs, int maxAgeDays, int hidePercent, int max) {
        List<ContinueRules.Row> rows = new ArrayList<>();
        try (Cursor c = ctx.getContentResolver().query(WATCH_NEXT, null, null, null, null)) {
            if (c == null) return Collections.emptyList();
            int id = c.getColumnIndex("_id");
            int pkg = c.getColumnIndex("package_name");
            int title = c.getColumnIndex("title");
            int intent = c.getColumnIndex("intent_uri");
            int poster = c.getColumnIndex("poster_art_uri");
            int type = c.getColumnIndex("watch_next_type");
            int season = c.getColumnIndex("season_display_number");
            int episode = c.getColumnIndex("episode_display_number");
            int position = c.getColumnIndex("last_playback_position_millis");
            int duration = c.getColumnIndex("duration_millis");
            int engaged = c.getColumnIndex("last_engagement_time_utc_millis");
            int seen = 0;
            while (c.moveToNext() && seen++ < ROW_LIMIT) {
                try {
                    rows.add(new ContinueRules.Row(number(c, id), text(c, pkg), text(c, title), text(c, intent),
                            text(c, poster), (int) number(c, type), (int) number(c, season), (int) number(c, episode),
                            number(c, position), number(c, duration), number(c, engaged)));
                } catch (RuntimeException e) {
                    Log.w(TAG, "skipped a row: " + e);
                }
            }
        } catch (SecurityException e) {
            Log.i(TAG, "READ_TV_LISTINGS is not granted: no Continue watching row");
            return Collections.emptyList();
        } catch (RuntimeException e) {
            Log.w(TAG, "could not read Watch Next: " + e);
            return Collections.emptyList();
        }
        return ContinueRules.select(rows, nowMs, maxAgeDays, hidePercent, max);
    }

    private static String text(Cursor c, int column) {
        return column < 0 || c.isNull(column) ? null : c.getString(column);
    }

    /** A number column, or 0 when it is missing, null or not numeric (season and episode are text columns). */
    private static long number(Cursor c, int column) {
        return column < 0 || c.isNull(column) ? 0L : c.getLong(column);
    }
}
```

- [ ] **Step 2: Compile and run the suite**

```bash
cd ~/Developer/firetvdebloate && tools/cy-gradle.sh :app:testDebugUnitTest > /tmp/cw-t4.log 2>&1; echo "exit=$?"; grep -E "error:|BUILD" /tmp/cw-t4.log | head -4
```
Expected: `exit=0`, `BUILD SUCCESSFUL`.

- [ ] **Step 3: Commit**

```bash
cd ~/Developer/firetvdebloate/vendor/cleanyourtv
git add launcher/app/src/main/java/com/gathin/tvhome/WatchNextReader.java
git commit -q -m "feat: WatchNextReader reads Continue-watching rows from the TV provider

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
git log --oneline -1
```

---

### Task 5: `Entry.WATCH` tiles in `AppAdapter` (layout, binding, click)

**Files:**
- Create: `vendor/cleanyourtv/launcher/app/src/main/res/drawable/watch_scrim.xml`
- Modify: `vendor/cleanyourtv/launcher/app/src/main/res/layout/item_app.xml`
- Modify: `vendor/cleanyourtv/launcher/app/src/main/java/com/gathin/tvhome/AppAdapter.java`

**Interfaces:**
- Consumes: `ContinueRules.Card` (Task 1); `Config.continueWatching`, `Config.continuePosters` (Task 3); `PosterCache.load(Context, String, int, int, PosterCache.Callback)` (Task 6, written next: this task compiles only once Task 6's file exists, so Task 6 Step 1 comes first at execution; see the ordering note at the top of Task 6).
- Produces: `AppAdapter.setWatch(List<ContinueRules.Card>)`, `AppAdapter.isWatchAt(int position) -> boolean`, `Entry.WATCH`; tiles placed right after the dock entries, drawn with the existing tile size, focus and glow.

**Ordering note:** Task 5's `bindWatch` calls `PosterCache.load`, so write and compile Task 6's `PosterCache.java` first (Task 6 Steps 1-2), then do this task, then finish Task 6 (Steps 3-4). The numbers keep the review gates in order; the commits can be in either order.

- [ ] **Step 1: Add the scrim and extend the tile layout**

Create `res/drawable/watch_scrim.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android">
    <gradient android:angle="90" android:startColor="#CC000000" android:endColor="#00000000" />
</shape>
```

Edit `res/layout/item_app.xml` (both anchors must match once):

```bash
cd ~/Developer/firetvdebloate/vendor/cleanyourtv/launcher/app/src/main/res/layout
python3 -I - <<'EOF'
p = 'item_app.xml'
s = open(p).read()
a1 = '        <TextView\n            android:id="@+id/label"'
assert s.count(a1) == 1
scrim = '''        <View
            android:id="@+id/scrim"
            android:layout_width="match_parent"
            android:layout_height="48dp"
            android:layout_gravity="bottom"
            android:background="@drawable/watch_scrim"
            android:visibility="gone" />

'''
s = s.replace(a1, scrim + a1)
a2 = '            android:fontFamily="@string/font_body"\n            android:visibility="gone" />\n    </FrameLayout>'
assert s.count(a2) == 1
bars = '''            android:fontFamily="@string/font_body"
            android:visibility="gone" />

        <View
            android:id="@+id/progress_track"
            android:layout_width="match_parent"
            android:layout_height="4dp"
            android:layout_gravity="bottom"
            android:background="#59FFFFFF"
            android:visibility="gone" />

        <View
            android:id="@+id/progress"
            android:layout_width="0dp"
            android:layout_height="4dp"
            android:layout_gravity="bottom|start"
            android:background="#FFFFFFFF"
            android:visibility="gone" />
    </FrameLayout>'''
s = s.replace(a2, bars)
open(p, 'w').write(s)
print("item_app.xml ok")
EOF
```
Expected: prints `item_app.xml ok`.

- [ ] **Step 2: Entry kind, fields and the view holder**

```bash
cd ~/Developer/firetvdebloate/vendor/cleanyourtv/launcher/app/src/main/java/com/gathin/tvhome
python3 -I - <<'EOF'
p = 'AppAdapter.java'
s = open(p).read()

def once(old, new):
    global s
    assert s.count(old) == 1, ("anchor not found exactly once", old[:70])
    s = s.replace(old, new)

once('static final int APP = 0, HOME_SETTINGS = 1, CARD = 2, EMPTY = 3;',
     'static final int APP = 0, HOME_SETTINGS = 1, CARD = 2, EMPTY = 3, WATCH = 4;')
once('        int[] backdrop;\n',
     '        int[] backdrop;\n'
     '        /** A WATCH tile: the row it shows, its poster once loaded, and where the poster load stands. */\n'
     '        ContinueRules.Card card;\n'
     '        Drawable poster;\n'
     '        /** 0 not asked for yet, 1 loading, 2 loaded, 3 failed. */\n'
     '        int posterState;\n')
once('        final TextView label;\n        final TextView name;\n',
     '        final TextView label;\n        final TextView name;\n'
     '        /** A WATCH tile\'s bottom scrim and progress bar; hidden for every other tile. */\n'
     '        final View scrim, progressTrack, progress;\n')
once('            label = v.findViewById(R.id.label);\n',
     '            label = v.findViewById(R.id.label);\n'
     '            scrim = v.findViewById(R.id.scrim);\n'
     '            progressTrack = v.findViewById(R.id.progress_track);\n'
     '            progress = v.findViewById(R.id.progress);\n')
open(p, 'w').write(s)
print("entry + holder ok")
EOF
```
Expected: prints `entry + holder ok`.

- [ ] **Step 3: Fields, constructor, placement in `reload()`, and the new methods**

```bash
cd ~/Developer/firetvdebloate/vendor/cleanyourtv/launcher/app/src/main/java/com/gathin/tvhome
python3 -I - <<'EOF'
p = 'AppAdapter.java'
s = open(p).read()

def once(old, new):
    global s
    assert s.count(old) == 1, ("anchor not found exactly once", old[:70])
    s = s.replace(old, new)

once('    private int docked, emptySlots;\n',
     '    private int docked, emptySlots;\n'
     '    /** The Continue-watching row: switched on by config, the cards last handed over, and their tiles by key. */\n'
     '    private final boolean watchOn, postersOn;\n'
     '    private List<ContinueRules.Card> watchCards = Collections.emptyList();\n'
     '    private final Map<String, Entry> watchEntries = new java.util.HashMap<>();\n')
once('        this.uniformTiles = cfg.uniformTiles;\n',
     '        this.uniformTiles = cfg.uniformTiles;\n'
     '        this.watchOn = cfg.continueWatching;\n'
     '        this.postersOn = cfg.continuePosters;\n')
once('        items.clear();\n        items.addAll(fresh);\n        notifyDataSetChanged();\n    }',
     '        items.clear();\n        items.addAll(fresh);\n        placeWatch();\n        notifyDataSetChanged();\n    }')

methods = '''    /** Replaces the Continue-watching tiles, which sit right after the dock. Null or empty removes them. */
    void setWatch(List<ContinueRules.Card> cards) {
        watchCards = cards == null ? Collections.<ContinueRules.Card>emptyList() : new ArrayList<>(cards);
        placeWatch();
        notifyDataSetChanged();
    }

    boolean isWatchAt(int position) {
        return position >= 0 && position < items.size() && items.get(position).kind == Entry.WATCH;
    }

    /**
     * Puts the Continue-watching tiles into {@code items} right after the dock entries. Nothing is added when the
     * row is off, there is no grid below the dock, or reorder mode is on (a row belongs to its app, not to Home).
     */
    private void placeWatch() {
        for (int i = items.size() - 1; i >= 0; i--) {
            if (items.get(i).kind == Entry.WATCH) items.remove(i);
        }
        if (!watchOn || !dockRow || singleRow || reordering) return;
        int at = Math.min(items.size(), docked + emptySlots);
        java.util.Set<String> live = new java.util.HashSet<>();
        for (ContinueRules.Card c : watchCards) {
            Entry e = watchEntry(c);
            if (e == null) continue;
            live.add(c.key);
            items.add(at++, e);
        }
        watchEntries.keySet().retainAll(live);
    }

    /** The tile for a card, reusing the earlier one (and its loaded poster) when the card did not change. */
    private Entry watchEntry(ContinueRules.Card c) {
        Entry old = watchEntries.get(c.key);
        if (old != null && c.equals(old.card)) return old;
        Drawable icon;
        try {
            icon = ctx.getPackageManager().getApplicationIcon(c.pkg);
        } catch (android.content.pm.PackageManager.NameNotFoundException ex) {
            return null;   // the app that published it is gone
        }
        String caption = c.subtitle.isEmpty() ? null : c.subtitle;
        Entry e = new Entry(Entry.WATCH, c.title, new ComponentName(c.pkg, "watch/" + c.key), null, icon, caption, 0);
        e.card = c;
        watchEntries.put(c.key, e);
        return e;
    }

    /** A Continue-watching tile: the poster (the app's icon until it loads), the title, and a progress bar. */
    private void bindWatch(Holder h, Entry e) {
        ContinueRules.Card c = e.card;
        ViewGroup.LayoutParams size = h.card.getLayoutParams();
        h.scrim.setVisibility(View.VISIBLE);
        h.label.setText(c.title);
        h.label.setVisibility(View.VISIBLE);
        if (e.poster != null) {
            h.banner.setImageDrawable(e.poster);
            h.banner.setVisibility(View.VISIBLE);
            h.icon.setVisibility(View.GONE);
        } else {
            h.banner.setImageDrawable(null);
            h.banner.setVisibility(View.GONE);
            h.icon.setImageDrawable(e.icon);
            h.icon.setVisibility(View.VISIBLE);
            if (postersOn && e.posterState == 0 && c.posterUri != null) {
                e.posterState = 1;
                PosterCache.load(ctx, c.posterUri, size.width, size.height, bitmap -> {
                    e.posterState = bitmap != null ? 2 : 3;
                    if (bitmap != null) e.poster = new android.graphics.drawable.BitmapDrawable(ctx.getResources(), bitmap);
                    int pos = items.indexOf(e);
                    if (pos >= 0) notifyItemChanged(pos);
                });
            }
        }
        if (c.progress >= 0f) {
            ViewGroup.LayoutParams bar = h.progress.getLayoutParams();
            bar.width = Math.max(1, Math.round(size.width * Math.min(1f, c.progress)));
            h.progress.setLayoutParams(bar);
            h.progressTrack.setVisibility(View.VISIBLE);
            h.progress.setVisibility(View.VISIBLE);
        }
    }

    /**
     * Opens the row's deep link, but only into the app that published it: a row cannot send Home to another
     * app. A link that does not resolve to that app falls back to the app's own normal launch.
     */
    private void launchWatch(Entry e) {
        ContinueRules.Card c = e.card;
        android.content.pm.PackageManager pm = ctx.getPackageManager();
        Intent i = null;
        try {
            Intent link = Intent.parseUri(c.intentUri, Intent.URI_INTENT_SCHEME);
            link.setSelector(null);
            link.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            ResolveInfo ri = pm.resolveActivity(link, 0);
            if (ri != null && ri.activityInfo != null && c.pkg.equals(ri.activityInfo.packageName)) i = link;
        } catch (java.net.URISyntaxException | RuntimeException ex) {
            // fall through to the app's own launch
        }
        if (i == null) {
            i = pm.getLeanbackLaunchIntentForPackage(c.pkg);
            if (i == null) i = pm.getLaunchIntentForPackage(c.pkg);
            if (i != null) i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        }
        try {
            if (i == null) throw new ActivityNotFoundException();
            ctx.startActivity(i);
            if (cinematic) LastOpened.record(ctx, c.pkg);
        } catch (Exception ex) {
            Toast.makeText(ctx, ctx.getString(R.string.cant_open, e.label), Toast.LENGTH_SHORT).show();
        }
    }

'''
anchor = "    /** Opens the tile's activity by explicit component, with no extras: a card can name nothing else. */\n"
once(anchor, methods + anchor)
open(p, 'w').write(s)
print("adapter methods ok")
EOF
```
Expected: prints `adapter methods ok`.

- [ ] **Step 4: Bind and click wiring**

```bash
cd ~/Developer/firetvdebloate/vendor/cleanyourtv/launcher/app/src/main/java/com/gathin/tvhome
python3 -I - <<'EOF'
p = 'AppAdapter.java'
s = open(p).read()

def once(old, new):
    global s
    assert s.count(old) == 1, ("anchor not found exactly once", old[:70])
    s = s.replace(old, new)

# every other tile hides the Continue-watching views a recycled holder may still show
once('        h.card.setVisibility(View.VISIBLE);\n        h.card.setFocusable(true);\n        h.name.setText(e.name);\n',
     '        h.card.setVisibility(View.VISIBLE);\n        h.card.setFocusable(true);\n'
     '        h.scrim.setVisibility(View.GONE);\n'
     '        h.progressTrack.setVisibility(View.GONE);\n'
     '        h.progress.setVisibility(View.GONE);\n'
     '        h.name.setText(e.name);\n')
once('        if (e.banner != null) {\n            h.banner.setImageDrawable(e.banner);\n',
     '        if (e.kind == Entry.WATCH) {\n            bindWatch(h, e);\n'
     '        } else if (e.banner != null) {\n            h.banner.setImageDrawable(e.banner);\n')
once('        h.card.setOnLongClickListener(v -> {\n            if (tileMenu) {\n',
     '        h.card.setOnLongClickListener(v -> {\n'
     '            if (e.kind == Entry.WATCH) return true;   // a row belongs to its app, not to Home\n'
     '            if (tileMenu) {\n')
once('    private void launch(Entry e) {\n        if (e.kind == Entry.HOME_SETTINGS) {\n',
     '    private void launch(Entry e) {\n'
     '        if (e.kind == Entry.WATCH) {\n            launchWatch(e);\n            return;\n        }\n'
     '        if (e.kind == Entry.HOME_SETTINGS) {\n')
open(p, 'w').write(s)
print("bind + click ok")
EOF
```
Expected: prints `bind + click ok`.

- [ ] **Step 5: Compile and run the suite (needs `PosterCache.java` from Task 6 Step 1)**

```bash
cd ~/Developer/firetvdebloate && tools/cy-gradle.sh :app:testDebugUnitTest > /tmp/cw-t5.log 2>&1; echo "exit=$?"; grep -E "error:|BUILD" /tmp/cw-t5.log | head -6
```
Expected: `exit=0`, `BUILD SUCCESSFUL`. If you see `cannot find symbol ... PosterCache`, do Task 6 Step 1 first.

- [ ] **Step 6: Commit**

```bash
cd ~/Developer/firetvdebloate/vendor/cleanyourtv
git add launcher/app/src/main/res/drawable/watch_scrim.xml launcher/app/src/main/res/layout/item_app.xml launcher/app/src/main/java/com/gathin/tvhome/AppAdapter.java
git commit -q -m "feat: Continue-watching tiles in the adapter, placed right after the dock

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
git log --oneline -1
```

---

### Task 6: `PosterCache` (the only code that touches the network)

**Files:**
- Create: `vendor/cleanyourtv/launcher/app/src/main/java/com/gathin/tvhome/PosterCache.java`

**Interfaces:**
- Consumes: `PosterRules.kind/key/evict/Cached` (Task 2).
- Produces: `PosterCache.load(Context ctx, String uri, int width, int height, PosterCache.Callback cb)`; `interface PosterCache.Callback { void done(Bitmap bitmap); }`, always called on the main thread, with null on any failure.

Do Steps 1-2 before Task 5 Step 5 (see the ordering note in Task 5).

- [ ] **Step 1: Write the cache**

Create `PosterCache.java`:

```java
package com.gathin.tvhome;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Poster pictures for the Continue-watching row. This is the ONLY class that opens a network connection
 * (OnlyPosterCacheOpensConnectionsTest), and the launcher holds INTERNET for nothing else.
 *
 * Rules (docs: specs/2026-10-28-continue-watching-design.md): https only, or content:// through ContentResolver;
 * at most 2 MB; 5 s timeouts; only images; decoded down-sampled to about the tile size in RGB_565; no cookies,
 * no account, a neutral User-Agent; a disk cache of at most 24 files and 24 MB, oldest evicted. One worker
 * thread. Every failure ends as a null bitmap; nothing is thrown to the caller.
 */
final class PosterCache {
    interface Callback {
        /** Called on the main thread; null when the poster could not be had. */
        void done(Bitmap bitmap);
    }

    private static final String TAG = "TvHomePoster";
    private static final int CONNECT_MS = 5000, READ_MS = 5000, MAX_BYTES = 2 * 1024 * 1024;
    private static final int CACHE_FILES = 24;
    private static final long CACHE_BYTES = 24L * 1024 * 1024;
    private static final long MAX_PIXELS = 40L * 1000 * 1000;
    private static final ExecutorService IO = Executors.newSingleThreadExecutor();
    private static final Handler UI = new Handler(Looper.getMainLooper());

    private PosterCache() {
    }

    static void load(Context ctx, String uri, int width, int height, Callback cb) {
        final int kind = PosterRules.kind(uri);
        if (kind == PosterRules.NONE) {
            cb.done(null);
            return;
        }
        final Context app = ctx.getApplicationContext();
        IO.execute(() -> {
            Bitmap bitmap = null;
            try {
                bitmap = fetch(app, uri, kind, width, height);
            } catch (Exception | OutOfMemoryError e) {
                Log.w(TAG, "a poster could not be loaded: " + e);
            }
            final Bitmap result = bitmap;
            UI.post(() -> cb.done(result));
        });
    }

    private static Bitmap fetch(Context ctx, String uri, int kind, int width, int height) throws IOException {
        byte[] data;
        if (kind == PosterRules.CONTENT) {
            try (InputStream in = ctx.getContentResolver().openInputStream(Uri.parse(uri))) {
                data = readBounded(in);
            }
        } else {
            File dir = new File(ctx.getCacheDir(), "posters");
            File file = new File(dir, PosterRules.key(uri));
            if (file.isFile()) {
                file.setLastModified(System.currentTimeMillis());
                try (InputStream in = new FileInputStream(file)) {
                    data = readBounded(in);
                }
            } else {
                data = download(uri);
                if (data != null) store(dir, file, data);
            }
        }
        return data == null ? null : decode(data, width, height);
    }

    /** The bytes of an https address, or null: not a 200, not an image, too big, or any network trouble. */
    private static byte[] download(String uri) throws IOException {
        HttpURLConnection conn = null;
        try {
            conn = (HttpURLConnection) new URL(uri).openConnection();
            conn.setConnectTimeout(CONNECT_MS);
            conn.setReadTimeout(READ_MS);
            conn.setUseCaches(false);
            conn.setInstanceFollowRedirects(true);   // the platform never follows a redirect to another scheme
            conn.setRequestProperty("User-Agent", "tvhome");
            conn.setRequestProperty("Accept", "image/*");
            if (conn.getResponseCode() != 200) return null;
            String type = conn.getContentType();
            if (type == null || !type.toLowerCase(Locale.ROOT).startsWith("image/")) return null;
            if (conn.getContentLengthLong() > MAX_BYTES) return null;
            try (InputStream in = conn.getInputStream()) {
                return readBounded(in);
            }
        } finally {
            if (conn != null) conn.disconnect();
        }
    }

    /** All of the stream, or null when it is empty-handed or longer than the poster limit. */
    private static byte[] readBounded(InputStream in) throws IOException {
        if (in == null) return null;
        ByteArrayOutputStream out = new ByteArrayOutputStream(32 * 1024);
        byte[] buf = new byte[8192];
        int n;
        while ((n = in.read(buf)) > 0) {
            if (out.size() + n > MAX_BYTES) return null;
            out.write(buf, 0, n);
        }
        return out.size() == 0 ? null : out.toByteArray();
    }

    private static void store(File dir, File file, byte[] data) {
        try {
            if (!dir.isDirectory() && !dir.mkdirs()) return;
            File tmp = new File(dir, file.getName() + ".tmp");
            try (FileOutputStream out = new FileOutputStream(tmp)) {
                out.write(data);
            }
            if (!tmp.renameTo(file)) tmp.delete();
            prune(dir);
        } catch (IOException | RuntimeException e) {
            Log.w(TAG, "a poster could not be cached: " + e);
        }
    }

    private static void prune(File dir) {
        File[] all = dir.listFiles();
        if (all == null) return;
        List<PosterRules.Cached> cached = new ArrayList<>();
        for (File f : all) {
            if (f.isFile() && !f.getName().endsWith(".tmp")) {
                cached.add(new PosterRules.Cached(f.getName(), f.length(), f.lastModified()));
            }
        }
        for (String name : PosterRules.evict(cached, CACHE_FILES, CACHE_BYTES)) new File(dir, name).delete();
    }

    private static Bitmap decode(byte[] data, int width, int height) {
        BitmapFactory.Options o = new BitmapFactory.Options();
        o.inJustDecodeBounds = true;
        BitmapFactory.decodeByteArray(data, 0, data.length, o);
        if (o.outWidth <= 0 || o.outHeight <= 0 || (long) o.outWidth * o.outHeight > MAX_PIXELS) return null;
        int sample = 1;
        while (width > 0 && height > 0 && o.outWidth / (sample * 2) >= width && o.outHeight / (sample * 2) >= height) {
            sample *= 2;
        }
        o.inJustDecodeBounds = false;
        o.inSampleSize = sample;
        o.inPreferredConfig = Bitmap.Config.RGB_565;
        return BitmapFactory.decodeByteArray(data, 0, data.length, o);
    }
}
```

- [ ] **Step 2: Compile (the adapter edits of Task 5 may not exist yet; that is fine)**

```bash
cd ~/Developer/firetvdebloate && tools/cy-gradle.sh :app:compileDebugJavaWithJavac > /tmp/cw-t6.log 2>&1; echo "exit=$?"; grep -E "error:|BUILD" /tmp/cw-t6.log | head -5
```
Expected: `exit=0`, `BUILD SUCCESSFUL`.

- [ ] **Step 3: Run the whole suite (the "only PosterCache" scan must stay green with the new file)**

```bash
cd ~/Developer/firetvdebloate && tools/cy-gradle.sh :app:testDebugUnitTest > /tmp/cw-t6.log 2>&1; echo "exit=$?"; tail -3 /tmp/cw-t6.log
grep -o 'tests="[0-9]*" skipped="[0-9]*" failures="[0-9]*"' vendor/cleanyourtv/launcher/app/build/test-results/testDebugUnitTest/TEST-com.gathin.tvhome.OnlyPosterCacheOpensConnectionsTest.xml
```
Expected: `exit=0`; `tests="2" skipped="0" failures="0"` (PosterCache.java is the exempt file, so the scan still finds no other offender).

- [ ] **Step 4: Commit**

```bash
cd ~/Developer/firetvdebloate/vendor/cleanyourtv
git add launcher/app/src/main/java/com/gathin/tvhome/PosterCache.java
git commit -q -m "feat: PosterCache, the only code that opens a connection (https posters, bounded, cached)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
git log --oneline -1
```

---

### Task 7: `MainActivity` loads the rows and guards the tile menu

**Files:**
- Modify: `vendor/cleanyourtv/launcher/app/src/main/java/com/gathin/tvhome/MainActivity.java`

**Interfaces:**
- Consumes: `Config.continueWatching/continueMax/continueMaxAgeDays/continueHidePercent` (Task 3), `WatchNextReader.read` (Task 4), `AppAdapter.setWatch/isWatchAt` (Task 5).
- Produces: the row appears (when enabled and permitted), refreshes on every resume, and a long-press on a Continue-watching tile does nothing.

No host test (Activity wiring). Verified on the device in Task 8; the build and suite are the compile check.

- [ ] **Step 1: Fields, config copy, refresh method, resume hook, long-press guard**

```bash
cd ~/Developer/firetvdebloate/vendor/cleanyourtv/launcher/app/src/main/java/com/gathin/tvhome
python3 -I - <<'EOF'
p = 'MainActivity.java'
s = open(p).read()

def once(old, new):
    global s
    assert s.count(old) == 1, ("anchor not found exactly once", old[:70])
    s = s.replace(old, new)

once('    private boolean dockRow;\n',
     '    private boolean dockRow;\n'
     '    private boolean continueWatching;\n'
     '    private int continueMax, continueMaxAgeDays, continueHidePercent;\n'
     '    /** The Continue-watching cards Home shows now; the row is rebuilt only when a read gives different ones. */\n'
     '    private List<ContinueRules.Card> shownWatch = java.util.Collections.emptyList();\n')
once('        dockRow = cfg.dockRow;\n',
     '        dockRow = cfg.dockRow;\n'
     '        continueWatching = cfg.continueWatching;\n'
     '        continueMax = cfg.continueMax;\n'
     '        continueMaxAgeDays = cfg.continueMaxAgeDays;\n'
     '        continueHidePercent = cfg.continueHidePercent;\n')
once('    protected void onResume() {\n        super.onResume();\n',
     '    protected void onResume() {\n        super.onResume();\n        refreshWatch();\n')
once('    private void reloadApps(boolean animate) {',
     '''    /** Reads the Continue-watching rows off the main thread; Home changes only when the cards differ. */
    private void refreshWatch() {
        if (!continueWatching) return;
        final long now = System.currentTimeMillis();
        new Thread(() -> {
            final List<ContinueRules.Card> cards =
                    WatchNextReader.read(this, now, continueMaxAgeDays, continueHidePercent, continueMax);
            runOnUiThread(() -> {
                if (isDestroyed() || cards.equals(shownWatch)) return;
                shownWatch = cards;
                if (adapter != null) adapter.setWatch(cards);
            });
        }, "watch-next").start();
    }

    private void reloadApps(boolean animate) {''')
once('        if (reordering) return;\n        String key = adapter.keyAt(position);\n',
     '        if (reordering || adapter.isWatchAt(position)) return;\n        String key = adapter.keyAt(position);\n')
open(p, 'w').write(s)
print("MainActivity ok")
EOF
```
Expected: prints `MainActivity ok`. (If an anchor reports "not found exactly once", read the lines around it with `sed -n` and adapt that single anchor; do not loosen the check.)

- [ ] **Step 2: Compile and run the whole suite**

```bash
cd ~/Developer/firetvdebloate && tools/cy-gradle.sh :app:testDebugUnitTest > /tmp/cw-t7.log 2>&1; echo "exit=$?"; grep -E "error:|BUILD" /tmp/cw-t7.log | head -5
```
Expected: `exit=0`, `BUILD SUCCESSFUL`.

- [ ] **Step 3: Commit**

```bash
cd ~/Developer/firetvdebloate/vendor/cleanyourtv
git add launcher/app/src/main/java/com/gathin/tvhome/MainActivity.java
git commit -q -m "feat: Home reads Continue-watching rows on resume and ignores long-press on them

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
git log --oneline -8
```
Expected: the commits of Tasks 1-7 on branch `continue-watching`.

---

### Task 8: Build, install on the TV, verify, and measure the gates

**Files:**
- Create: `tools/cy-verify.sh` (project root)
- Modify: `themes/glass-firetv/config.json` (project root: turn the feature on)

**Interfaces:**
- Consumes: the fork build; the saved original `apk/cleanyourtv-launcher.apk`; the probe app `tv.probe.wn` still installed on the TV.
- Produces: `bash tools/cy-verify.sh` printing PSS, janky frames, handoff times and PASS/FAIL per gate.

- [ ] **Step 1: Write the gate script**

Create `tools/cy-verify.sh`:

```bash
#!/usr/bin/env bash
# Gates for the CleanYourTV launcher on the connected TV: memory, janky frames, Home handoff.
set -euo pipefail
SER=${ADB_SERIAL:-<TV_IP>:5555}
PKG=com.gathin.tvhome
HERE=$(cd "$(dirname "$0")" && pwd)
A() { adb -s "$SER" shell "$@" </dev/null | tr -d '\r'; }
fail=0
gate() { # name value limit (pass when value <= limit)
  if python3 -I -c "import sys; sys.exit(0 if float('$2') <= float('$3') else 1)"; then
    echo "PASS $1: $2 <= $3"
  else
    echo "FAIL $1: $2 > $3"; fail=1
  fi
}

A input keyevent KEYCODE_HOME; sleep 8
echo "== memory"
pss=$(A dumpsys meminfo $PKG | awk '$1=="TOTAL" {print $2; exit}')
echo "PSS_KB=$pss"
gate "PSS (KB)" "${pss:-999999}" "${PSS_MAX:-70000}"

echo "== jank while navigating"
A dumpsys gfxinfo $PKG reset >/dev/null
for _ in $(seq 1 15); do A input keyevent KEYCODE_DPAD_RIGHT; sleep 0.25; done
for _ in $(seq 1 15); do A input keyevent KEYCODE_DPAD_LEFT; sleep 0.25; done
for _ in $(seq 1 6); do A input keyevent KEYCODE_DPAD_DOWN; sleep 0.3; done
for _ in $(seq 1 6); do A input keyevent KEYCODE_DPAD_UP; sleep 0.3; done
info=$(A dumpsys gfxinfo $PKG)
echo "$info" | grep -E "Total frames rendered|Janky frames"
pct=$(echo "$info" | sed -n 's/.*Janky frames: [0-9]* (\([0-9.]*\)%).*/\1/p' | head -1)
gate "janky frames (%)" "${pct:-100}" 10

echo "== Home handoff (4 runs, system log)"
times=""
for n in 1 2 3 4; do
  A am start -n com.netflix.ninja/.MainActivity >/dev/null; sleep 9
  adb -s "$SER" logcat -c </dev/null; A input keyevent KEYCODE_HOME; sleep 8
  line=$(adb -s "$SER" logcat -d -v time </dev/null | python3 -I "$HERE/handoff-time.py" $PKG)
  t=${line%%s*}
  echo "run$n: $line"; times="$times ${t:-99}"
done
mean=$(python3 -I -c "v=[float(x) for x in '$times'.split() if x.replace('.','',1).isdigit()]; print(round(sum(v)/len(v), 2) if v else 99)")
echo "mean=$mean"
gate "Home handoff mean (s)" "$mean" "${HANDOFF_MAX:-3.3}"
exit $fail
```

```bash
chmod +x ~/Developer/firetvdebloate/tools/cy-verify.sh
```

- [ ] **Step 2: Build the release APK and check what it asks for**

```bash
cd ~/Developer/firetvdebloate && tools/cy-gradle.sh :app:assembleRelease > /tmp/cw-t8.log 2>&1; echo "exit=$?"; tail -3 /tmp/cw-t8.log
APK=vendor/cleanyourtv/launcher/app/build/outputs/apk/release/app-release.apk
BT=/opt/homebrew/share/android-commandlinetools/build-tools/34.0.0
$BT/aapt2 dump badging $APK | grep -E "^package" | cut -c1-120
$BT/aapt2 dump permissions $APK | grep uses-permission | sed "s/.*name='//; s/'.*//" | tr '\n' ' '; echo
ls -l $APK | awk '{print $5, $9}'
```
Expected: `exit=0`, `BUILD SUCCESSFUL`; `versionCode='10' versionName='3.1-continue'`; permissions include `READ_TV_LISTINGS` and `INTERNET` besides the five from before; size a little above 545 KB.

- [ ] **Step 3: Install over the current build, grant the permission, turn the feature on**

```bash
cd ~/Developer/firetvdebloate
SER=<TV_IP>:5555; D=/sdcard/Android/data/com.gathin.tvhome/files
APK=vendor/cleanyourtv/launcher/app/build/outputs/apk/release/app-release.apk
python3 -I - <<'EOF'
import json
p = 'themes/glass-firetv/config.json'
c = json.load(open(p))
c['continue_watching'] = True
json.dump(c, open(p, 'w'), indent=2); open(p, 'a').write('\n')
print(sorted(k for k in c if k.startswith('continue')))
EOF
adb -s $SER install -r $APK </dev/null 2>&1 | tail -1
adb -s $SER shell pm grant com.gathin.tvhome android.permission.READ_TV_LISTINGS </dev/null; echo "grant exit=$?"
adb -s $SER push themes/glass-firetv/config.json $D/config.json </dev/null | tail -1
adb -s $SER shell am force-stop com.gathin.tvhome </dev/null
adb -s $SER shell input keyevent KEYCODE_HOME </dev/null; sleep 10
echo "front: $(adb -s $SER shell dumpsys window </dev/null | grep -m1 mCurrentFocus | grep -oE '[a-z.]+/[A-Za-z_.0-9]+' | head -1)  fatal: $(adb -s $SER logcat -d </dev/null | grep -c 'FATAL EXCEPTION')"
```
Expected: `['continue_watching']`, `Success`, `grant exit=0`, the launcher in front, `fatal: 0`.

- [ ] **Step 4: Look at the row and cross-check it against the probe**

```bash
cd ~/Developer/firetvdebloate
SER=<TV_IP>:5555
adb -s $SER shell screencap -p /sdcard/s.png </dev/null; adb -s $SER pull /sdcard/s.png scan/shots/cw-1-home.png </dev/null >/dev/null
for i in 1 2; do adb -s $SER shell input keyevent KEYCODE_DPAD_DOWN </dev/null; sleep 2; done
adb -s $SER shell screencap -p /sdcard/s.png </dev/null; adb -s $SER pull /sdcard/s.png scan/shots/cw-2-row.png </dev/null >/dev/null; adb -s $SER shell rm -f /sdcard/s.png </dev/null
adb -s $SER logcat -c </dev/null; adb -s $SER shell am start -n tv.probe.wn/.Probe </dev/null >/dev/null; sleep 4
adb -s $SER logcat -d -s PROBE:I </dev/null | tr -d '\r' | grep "^.*watch_next_program |" | sed 's/^.*PROBE *: //' | cut -c1-200 | head -10
```
Then read `scan/shots/cw-1-home.png` and `cw-2-row.png`. Expected on the screen with the defaults (90 days, 92%): **two cards** right under the dock: **How I Met Your Mother** ("S5 E10", no progress bar) and **Harry Potter And The Sorcerer's Stone** (a bar at about 50%), because every other row is either older than 90 days or at least 92% watched. The probe's printed rows must agree on those titles and positions. Record the result honestly; if the row is missing, check `adb logcat -d -s TvHomeWatch TvHomePoster` first.

- [ ] **Step 5: A card opens the right title**

```bash
SER=<TV_IP>:5555
A() { adb -s $SER shell "$@" </dev/null | tr -d '\r'; }
# focus is on the row from the previous step; press OK on the focused card
A input keyevent KEYCODE_DPAD_CENTER; sleep 8
echo "front after OK: $(A dumpsys window | grep -m1 mCurrentFocus | grep -oE '[a-z.]+/[A-Za-z_.0-9]+' | head -1)"
A input keyevent KEYCODE_HOME; sleep 7
echo "back on: $(A dumpsys window | grep -m1 mCurrentFocus | grep -oE '[a-z.]+/[A-Za-z_.0-9]+' | head -1)"
```
Expected: the front window after OK belongs to `in.startv.hotstar` (the card's publisher; the deep link may land on the app's home or the title page), and Home returns to `com.gathin.tvhome`. Pressing OK launches that streaming app on the TV; the owner is watching.

- [ ] **Step 6: Gates**

```bash
cd ~/Developer/firetvdebloate && bash tools/cy-verify.sh 2>&1 | grep -vE "^Warning|Failed to write" | tee scan/cy-verify-continue.txt
```
Expected: three PASS lines (PSS at most 70000 KB, janky at most 10%, handoff mean at most 3.3 s). Any FAIL: look at which stage is slow (a reader or poster decode on the main thread would show as jank), fix it, and rerun this step.

- [ ] **Step 7: Control arm, permission revoked**

```bash
SER=<TV_IP>:5555
A() { adb -s $SER shell "$@" </dev/null | tr -d '\r'; }
A pm revoke com.gathin.tvhome android.permission.READ_TV_LISTINGS
adb -s $SER logcat -c </dev/null
A am force-stop com.gathin.tvhome; A input keyevent KEYCODE_HOME; sleep 10
echo "front: $(A dumpsys window | grep -m1 mCurrentFocus | grep -oE '[a-z.]+/[A-Za-z_.0-9]+' | head -1)  fatal: $(adb -s $SER logcat -d </dev/null | grep -c 'FATAL EXCEPTION')"
adb -s $SER logcat -d -s TvHomeWatch:I </dev/null | tr -d '\r' | tail -2
A screencap -p /sdcard/s.png; adb -s $SER pull /sdcard/s.png ~/Developer/firetvdebloate/scan/shots/cw-3-revoked.png </dev/null >/dev/null; A rm -f /sdcard/s.png
A pm grant com.gathin.tvhome android.permission.READ_TV_LISTINGS; echo "re-granted exit=$?"
```
Expected: launcher in front, `fatal: 0`, the log line `READ_TV_LISTINGS is not granted: no Continue watching row`, and the screenshot shows the dock and grid with **no** Continue-watching row.

- [ ] **Step 8: Control arm, posters off**

```bash
cd ~/Developer/firetvdebloate
SER=<TV_IP>:5555; D=/sdcard/Android/data/com.gathin.tvhome/files
A() { adb -s $SER shell "$@" </dev/null | tr -d '\r'; }
python3 -I - <<'EOF'
import json
c = json.load(open('themes/glass-firetv/config.json')); c['continue_posters'] = False
json.dump(c, open('/tmp/cw-noposters.json', 'w'), indent=2)
EOF
adb -s $SER push /tmp/cw-noposters.json $D/config.json </dev/null | tail -1
A am force-stop com.gathin.tvhome; A input keyevent KEYCODE_HOME; sleep 10
for i in 1 2; do A input keyevent KEYCODE_DPAD_DOWN; sleep 2; done
A screencap -p /sdcard/s.png; adb -s $SER pull /sdcard/s.png scan/shots/cw-4-noposters.png </dev/null >/dev/null; A rm -f /sdcard/s.png
echo "fatal: $(adb -s $SER logcat -d </dev/null | grep -c 'FATAL EXCEPTION')"
adb -s $SER push themes/glass-firetv/config.json $D/config.json </dev/null | tail -1; rm -f /tmp/cw-noposters.json
```
Expected: the row's cards show the publishing app's icon on a dark tile with the title and the bar (no posters), `fatal: 0`; the last push puts the real theme back. Not forced on the device: a real network failure or a hostile address (those are covered by the unit tests of `PosterRules` and by code review of `PosterCache`); note that in the ledger.

- [ ] **Step 9: Switch the feature off at runtime**

```bash
cd ~/Developer/firetvdebloate
SER=<TV_IP>:5555; D=/sdcard/Android/data/com.gathin.tvhome/files
A() { adb -s $SER shell "$@" </dev/null | tr -d '\r'; }
python3 -I - <<'EOF'
import json
c = json.load(open('themes/glass-firetv/config.json')); c['continue_watching'] = False
json.dump(c, open('/tmp/cw-off.json', 'w'), indent=2)
EOF
adb -s $SER push /tmp/cw-off.json $D/config.json </dev/null | tail -1
A am force-stop com.gathin.tvhome; A input keyevent KEYCODE_HOME; sleep 10
A screencap -p /sdcard/s.png; adb -s $SER pull /sdcard/s.png scan/shots/cw-5-off.png </dev/null >/dev/null; A rm -f /sdcard/s.png
echo "fatal: $(adb -s $SER logcat -d </dev/null | grep -c 'FATAL EXCEPTION')"
adb -s $SER push themes/glass-firetv/config.json $D/config.json </dev/null | tail -1; rm -f /tmp/cw-off.json
A am force-stop com.gathin.tvhome; A input keyevent KEYCODE_HOME; sleep 8
```
Expected: with the feature off, the screenshot shows the dock and grid with no row; `fatal: 0`; the final push turns it back on and Home shows the row again.

- [ ] **Step 10: Check the rollback path once**

```bash
cd ~/Developer/firetvdebloate
SER=<TV_IP>:5555
A() { adb -s $SER shell "$@" </dev/null | tr -d '\r'; }
adb -s $SER install -r apk/cleanyourtv-launcher.apk </dev/null 2>&1 | tail -1
A am force-stop com.gathin.tvhome; A input keyevent KEYCODE_HOME; sleep 9
echo "after rollback: front=$(A dumpsys window | grep -m1 mCurrentFocus | grep -oE '[a-z.]+/[A-Za-z_.0-9]+' | head -1) version=$(A dumpsys package com.gathin.tvhome | grep -m1 versionName)"
adb -s $SER install -r vendor/cleanyourtv/launcher/app/build/outputs/apk/release/app-release.apk </dev/null 2>&1 | tail -1
A am force-stop com.gathin.tvhome; A input keyevent KEYCODE_HOME; sleep 9
echo "back on the fork: version=$(A dumpsys package com.gathin.tvhome | grep -m1 versionName) granted=$(A dumpsys package com.gathin.tvhome | grep -c 'READ_TV_LISTINGS: granted=true')"
```
Expected: `Success` both times; after the rollback `versionName=3.1` and Home works; after reinstalling the fork `versionName=3.1-continue` and the permission still granted (re-grant with `pm grant` if it shows 0). The theme files on the TV are untouched by both installs.

- [ ] **Step 11: Commit the project-side files**

The fork has no uncommitted source changes here. Record the theme change in the project README in Task 9. Nothing to commit in the fork.

---

### Task 9: Record the result and clean up

**Files:**
- Modify: `README.md` (project root)
- Create: `apk/cleanyourtv-continue.apk` and `apk/cleanyourtv-continue.apk.sha256` (copies of the built fork)

- [ ] **Step 1: Keep the built APK and write the README section**

```bash
cd ~/Developer/firetvdebloate
cp vendor/cleanyourtv/launcher/app/build/outputs/apk/release/app-release.apk apk/cleanyourtv-continue.apk
shasum -a 256 apk/cleanyourtv-continue.apk | cut -c1-64 | tee apk/cleanyourtv-continue.apk.sha256
cat >> README.md <<'EOF'

## Continue watching row (2026-10-28)
Fork: vendor/cleanyourtv, branch `continue-watching` on fa1a2f0 (local only, MIT). Build: apk/cleanyourtv-continue.apk (versionName 3.1-continue, versionCode 10, same debug key as 3.1, so it installs over it in either direction).
What: a row under the dock of titles other apps publish to the TV's Watch Next list: poster, title, "S1 E2", progress bar; OK reopens the title in the app that published it (only that app; otherwise that app's normal launch).
Needs: `adb shell pm grant com.gathin.tvhome android.permission.READ_TV_LISTINGS` and `"continue_watching": true` in the theme (themes/glass-firetv/config.json). Settings: continue_max (4), continue_max_age_days (90), continue_hide_percent (92), continue_posters (true).
Privacy: the launcher now holds INTERNET, for posters only: PosterCache is the only class that opens a connection (OnlyPosterCacheOpensConnectionsTest scans for it); https only, 2 MB cap, 5 s timeouts, no cookies/identifiers, disk cache 24 files / 24 MB. `continue_posters: false` makes no request.
Seen on this TV: only JioHotstar publishes (9 Watch Next rows); with the defaults two cards qualify (an "up next" and one 50% title) because the rest are older than 90 days or at least 92% watched. Raise continue_max_age_days to see older ones.
Fallback: `adb install -r apk/cleanyourtv-launcher.apk` (the saved v3.1), or set continue_watching false.
Gates (tools/cy-verify.sh): see scan/cy-verify-continue.txt.
EOF
echo ok
```

- [ ] **Step 2: Remove the probe app and the build tools again**

```bash
SER=<TV_IP>:5555
echo "probe: $(adb -s $SER uninstall tv.probe.wn </dev/null | tr -d '\r')"
brew uninstall openjdk@17 2>&1 | tail -1; brew uninstall --cask android-commandlinetools 2>&1 | tail -1
rm -rf /opt/homebrew/share/android-commandlinetools ~/.gradle
ls -d /opt/homebrew/share/android-commandlinetools ~/.gradle 2>&1 | head -2
ls ~/.android/adbkey ~/.android/debug.keystore ~/Developer/firetvdebloate/vendor/cleanyourtv/.git ~/Developer/firetvdebloate/vendor/dumbtv/launcher/release.keystore | tr '\n' ' '; echo
```
Expected: `probe: Success`, the two toolchain paths gone ("No such file"), and the keys and both forks still present. Keep `~/.android` (`adbkey` authorises this Mac with the TV; `debug.keystore` signs the launcher), both forks, `backups/` and `apk/`.

---

## Self-Review

**Spec coverage** (spec section against task)
- Parts and filtering: `ContinueRules` (Task 1), `WatchNextReader` (Task 4), `PosterCache` (Task 6), adapter integration (Task 5), Activity wiring (Task 7).
- Card look: poster or icon fallback, title, subtitle in `Entry.name`, progress bar, scrim (Task 5 Steps 1, 3).
- Opening a card, with the "same app only" check and fall-backs (Task 5 `launchWatch`).
- Posters and the internet rules, including the scan test and the off switch (Tasks 2, 3, 6, 8 Step 8).
- Settings table and defaults (Task 3); permissions on the TV (Task 3 Step 3, Task 8 Step 3).
- Failure behaviour: reader catch blocks (Task 4), loader catches (Task 6), reorder/single-row guards (Task 5 `placeWatch`).
- Testing and gates: Tasks 1, 2, 8. Build and rollback: Tasks 3, 8 Step 10. Cleanup: Task 9.

**Placeholder scan:** no "TBD"/"similar to"; every code step shows the code. The one deliberate fallback is Task 7's note to adapt a single anchor if the file differs, with the check kept strict.

**Type consistency:** `ContinueRules.Row/Card/select/clamp` and the constants (Task 1) are used with the same names in `Config` (Task 3), `WatchNextReader` (Task 4), `AppAdapter` and `MainActivity` (Tasks 5, 7). `PosterRules.kind/key/evict/Cached` (Task 2) match `PosterCache` (Task 6). `PosterCache.load(Context, String, int, int, Callback)` and `Callback.done(Bitmap)` match the lambda in `bindWatch`. `AppAdapter.setWatch/isWatchAt` match `MainActivity`. `Entry.WATCH` fields `card/poster/posterState` match their uses.

**Review Focus:** each of the five lines has a named step: (1) Task 8 Step 7; (2) Task 2 tests and Task 8 Step 8 (the network-failure path itself is covered by tests and code review, not forced on the device); (3) Task 5 `launchWatch` and Task 8 Step 5 (the positive case on the device; a deliberately mismatched deep link is covered by code review only, since only an app holding `WRITE_EPG_DATA` can publish a crafted row); (4) Task 1 tests and the reader's row limit; (5) Task 8 Step 9 and the `placeWatch` guard.

**Known risks to watch at execution:** `notifyDataSetChanged()` in `setWatch` may reset the focus if the row changes while the owner is navigating (it runs only when the cards differ); Task 3's anchors depend on the exact text of a large `Config` constructor, so each edit asserts its anchor appears once; the first Gradle run downloads several hundred MB.
