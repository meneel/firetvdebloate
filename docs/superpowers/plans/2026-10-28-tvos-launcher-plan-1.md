# tvOS Launcher, Plan 1: `layout=tvos` and glass dock

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an Apple-TV-style layout to the dumbtv launcher fork (focus lift, top shelf with ambient glow, cached-blur glass dock) and prove it on the Fire TV Stick Lite within the spec's performance gates.

**Architecture:** A new `layout=tvos` value reuses dumbtv's existing row machinery (it behaves like `rows`, because the code only special-cases `"grid"`). Visuals are layered on: bigger focus lift on `Tile`, a new `TopShelf` view above the apps row, and a `GlassBand` background drawable on the apps row's scroll view. Pure logic (config value, colour maths, box blur) lives in view-free classes so host-side Java tests can pin it. `Guard.java` is never touched.

**Tech Stack:** Plain Java 8 (`--release 8`), Android views, compiled against `android-25` stubs, JDK 17, bare SDK `build.sh`. No libraries, no new permissions.

**Spec:** `docs/superpowers/specs/2026-10-28-tvos-launcher-fork-design.md`

**Scope of this plan:** spec phases 1 and 2 only. Not in this plan, each to get its own plan after this one is on the TV: the "Down expands to the full grid" behaviour (touches `focusSearch` in six places; to be decided after seeing the dock), wallpaper motion (phase 3), screensaver spike (phase 4), Watch Next re-test (phase 5), TMDB carousel flavor (phase 6). Phase 0 (toolchain, unchanged build) is done.

## Global Constraints

- Work only in the fork: `vendor/dumbtv/` on a local git branch `tvos` (MIT licence and notices kept; no push).
- Compile target `android-25` (`MIN_SDK=25`), `--release 8`. No API above level 25 and no `java.*` call Android 7.1 lacks.
- Plain Java, no libraries, no `INTERNET` permission, no new manifest permissions. `build.sh` must still report `3 uses-permission entries`.
- `launcher/src/tv/dumbtv/home/Guard.java` is not modified.
- Default layout stays `rows`; with `layout=rows` or `grid` behaviour and look are unchanged.
- Performance gates (spec section 7): PSS under 60 MB; at most 10% janky frames while moving focus; Home handoff mean not worse than the current baseline (mean ~3.4 s from runs 2.0, 3.5, 4.95, 3.7, ~2.9 s), gate set at 4.0 s to allow for the observed spread.
- Any effect that misses a gate is cut or made an off-by-default config toggle.
- No live blur, no shaders (Android 9). Glass is a cached pre-blurred bitmap plus a translucent layer.
- Rollback must stay possible at every step: `install.sh --undo`, uninstall ours, `install.sh` (release), push saved `home.conf`.

## Review Focus

Failure modes the spec implies but a happy-path run would not exercise, most likely first:

1. `layout=tvos` with `background=black` or no wallpaper: glass must draw flat, with no backdrop and no crash. (Pinned on-device in Task 6 Step 6; `Blur` itself is pinned by host test in Task 3.)
2. The user's current config has `tile_style=afterglow`: lift and Afterglow tiles must work together. (Pinned on-device in Task 4 Step 5.)
3. A focused app with an empty or very long label: `TopShelf` must neither crash nor overflow. (Host test in Task 5 pins the ellipsis helper; on-device in Task 5 Step 6.)
4. Focus on the Options/Settings chips (`focusBackground(null)`): shelf must clear, not keep the previous app's name. (Task 5 Step 6.)
5. Switching layout back to `rows` at runtime: shelf hidden and glass removed without reinstalling. (Task 6 Step 7.)

---

### Task 1: Host test runner and the `tvos` layout value

**Files:**
- Create: `vendor/dumbtv/launcher/tests/run.sh`
- Create: `vendor/dumbtv/launcher/tests/TvosConfigTest.java`
- Modify: `vendor/dumbtv/launcher/src/tv/dumbtv/home/Config.java:65-67`

**Interfaces:**
- Consumes: `Config.LAYOUT` (`Config.Choice` with `key`, `fallback`, `values`, `names`, `name(String)`).
- Produces: `bash launcher/tests/run.sh` (run from `vendor/dumbtv`), which compiles `src` and `tests` and runs every `tests/*Test.java` `main()`; and the layout value `"tvos"` named `"Apple TV style"`.

- [ ] **Step 1: Create the fork branch**

```bash
cd ~/Developer/firetvdebloate/vendor/dumbtv
git switch -c tvos
git status --short
```
Expected: `Switched to a new branch 'tvos'`; status lists only untracked `launcher/build/` and `launcher/release.keystore` (never `git add` these).

- [ ] **Step 2: Write the test runner**

Create `launcher/tests/run.sh`:

```bash
#!/usr/bin/env bash
# Host-side Java checks: compile the launcher and the tests against the android-25 stubs, then run
# every tests/*Test.java main(). No device and no test framework.
set -euo pipefail
cd "$(dirname "$0")/.."
JAVA_HOME=${JAVA_HOME:-/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home}
JAR=${ANDROID_JAR:-/opt/homebrew/share/android-commandlinetools/platforms/android-25/android.jar}
OUT=$(mktemp -d)
"$JAVA_HOME/bin/javac" --release 8 -nowarn -d "$OUT" -cp "$JAR" src/tv/dumbtv/home/*.java tests/*.java 2> >(grep -v '^Note:' >&2)
for f in tests/*Test.java; do
  "$JAVA_HOME/bin/java" -cp "$OUT:$JAR" "tv.dumbtv.home.$(basename "$f" .java)"
done
```

```bash
chmod +x launcher/tests/run.sh
```

- [ ] **Step 3: Run it to confirm the baseline passes**

Run: `bash launcher/tests/run.sh`
Expected: three lines, `FocusColorTest passed`, `MeterTest passed`, `RecentTest passed`.

- [ ] **Step 4: Write the failing test**

Create `launcher/tests/TvosConfigTest.java`:

```java
package tv.dumbtv.home;

import java.util.Arrays;

/** The tvos layout is a Config choice and the default layout is unchanged. */
public final class TvosConfigTest {
    private static void check(boolean ok, String name) {
        if (!ok) throw new AssertionError(name);
    }

    public static void main(String[] args) {
        check("rows".equals(Config.LAYOUT.fallback), "default layout unchanged");
        check(Arrays.asList(Config.LAYOUT.values).contains("tvos"), "tvos is a layout");
        check("Apple TV style".equals(Config.LAYOUT.name("tvos")), "tvos has a name");
        check(Config.LAYOUT.values.length == Config.LAYOUT.names.length, "every layout has a name");
        System.out.println("TvosConfigTest passed");
    }
}
```

- [ ] **Step 5: Run it to verify it fails**

Run: `bash launcher/tests/run.sh`
Expected: the three existing tests pass, then FAIL: `Exception in thread "main" java.lang.AssertionError: tvos is a layout` and a non-zero exit.

- [ ] **Step 6: Add the layout value**

In `launcher/src/tv/dumbtv/home/Config.java`, replace:

```java
    static final Choice LAYOUT = new Choice("layout", "Layout", "rows",
            new String[] {"rows", "grid"},
            new String[] {"Rows", "Grid"});
```
with:

```java
    static final Choice LAYOUT = new Choice("layout", "Layout", "rows",
            new String[] {"rows", "grid", "tvos"},
            new String[] {"Rows", "Grid", "Apple TV style"});
```

- [ ] **Step 7: Run all tests**

Run: `bash launcher/tests/run.sh`
Expected: four `... passed` lines including `TvosConfigTest passed`.

- [ ] **Step 8: Commit**

```bash
git add launcher/tests/run.sh launcher/tests/TvosConfigTest.java launcher/src/tv/dumbtv/home/Config.java
git commit -m "feat: add layout=tvos choice and a host test runner

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: `TvosStyle` constants and colour helper

**Files:**
- Create: `vendor/dumbtv/launcher/src/tv/dumbtv/home/TvosStyle.java`
- Test: `vendor/dumbtv/launcher/tests/TvosStyleTest.java`

**Interfaces:**
- Consumes: nothing.
- Produces: `TvosStyle.active(String layout) -> boolean`; `TvosStyle.glow(int argb) -> int` (the colour at 40% opacity, rgb preserved); `TvosStyle.FOCUS_SCALE` (`float`, 1.12f); `TvosStyle.LIFT_DP` (`float`, 14f).

- [ ] **Step 1: Write the failing test**

Create `launcher/tests/TvosStyleTest.java`:

```java
package tv.dumbtv.home;

/** Pins the Apple TV style numbers and the shelf glow colour maths. */
public final class TvosStyleTest {
    private static void check(boolean ok, String name) {
        if (!ok) throw new AssertionError(name);
    }

    public static void main(String[] args) {
        check(TvosStyle.active("tvos"), "tvos is active");
        check(!TvosStyle.active("rows"), "rows is not active");
        check(!TvosStyle.active("grid"), "grid is not active");
        check(!TvosStyle.active(null), "null layout is not active");
        check(TvosStyle.glow(0xFF2050E0) == 0x662050E0, "glow is 40% opacity and keeps rgb");
        check(TvosStyle.glow(0x00112233) == 0x66112233, "glow ignores the incoming alpha");
        check(TvosStyle.FOCUS_SCALE > 1.08f, "lift is stronger than the stock focus scale");
        check(TvosStyle.LIFT_DP > 0f, "lift rises off the dock");
        System.out.println("TvosStyleTest passed");
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash launcher/tests/run.sh`
Expected: FAIL at compile time: `cannot find symbol ... class TvosStyle`.

- [ ] **Step 3: Write the minimal implementation**

Create `launcher/src/tv/dumbtv/home/TvosStyle.java`:

```java
package tv.dumbtv.home;

/** Numbers and colour maths for the Apple TV style layout, free of views so a host test can pin them. */
final class TvosStyle {
    static final String LAYOUT = "tvos";
    /** The focused dock tile grows this much; the stock layouts use Tile's own 1.08. */
    static final float FOCUS_SCALE = 1.12f;
    /** The focused dock tile rises this many dp off the dock, which is what casts its shadow. */
    static final float LIFT_DP = 14f;
    private static final int GLOW_ALPHA = 0x66;

    private TvosStyle() {}

    static boolean active(String layout) {
        return LAYOUT.equals(layout);
    }

    /** The shelf glow: the app's colour at 40% opacity, whatever alpha it came with. */
    static int glow(int color) {
        return GLOW_ALPHA << 24 | color & 0xFFFFFF;
    }
}
```

- [ ] **Step 4: Run all tests**

Run: `bash launcher/tests/run.sh`
Expected: five `... passed` lines including `TvosStyleTest passed`.

- [ ] **Step 5: Commit**

```bash
git add launcher/src/tv/dumbtv/home/TvosStyle.java launcher/tests/TvosStyleTest.java
git commit -m "feat: add TvosStyle constants and glow colour helper

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `Blur` (cached-backdrop box blur)

**Files:**
- Create: `vendor/dumbtv/launcher/src/tv/dumbtv/home/Blur.java`
- Test: `vendor/dumbtv/launcher/tests/BlurTest.java`

**Interfaces:**
- Consumes: nothing.
- Produces: `Blur.box(int[] argb, int w, int h, int radius) -> void`. Blurs in place, window `2*radius+1`, edges clamped, every ARGB channel, rows then columns. `radius <= 0` is a no-op.

- [ ] **Step 1: Write the failing test**

Create `launcher/tests/BlurTest.java`:

```java
package tv.dumbtv.home;

import java.util.Arrays;

/** Box blur keeps flat areas flat, softens edges, keeps alpha, and leaves radius 0 alone. */
public final class BlurTest {
    private static void check(boolean ok, String name) {
        if (!ok) throw new AssertionError(name);
    }

    public static void main(String[] args) {
        int[] flat = new int[64];
        Arrays.fill(flat, 0xFF336699);
        Blur.box(flat, 8, 8, 2);
        for (int p : flat) check(p == 0xFF336699, "a flat image stays flat");

        // 8x1 strip: four black pixels then four white ones, radius 1 (window of 3).
        int[] edge = new int[8];
        for (int i = 0; i < 8; i++) edge[i] = i < 4 ? 0xFF000000 : 0xFFFFFFFF;
        Blur.box(edge, 8, 1, 1);
        check((edge[2] >> 16 & 255) == 0, "far from the edge stays black");
        check((edge[3] >> 16 & 255) == 85, "one white neighbour in three is 85");
        check((edge[4] >> 16 & 255) == 170, "two white in three is 170");
        check((edge[7] >> 16 & 255) == 255, "far side stays white");
        check((edge[3] >>> 24) == 255, "alpha is kept");

        int[] untouched = {0xFF000000, 0xFFFFFFFF};
        Blur.box(untouched, 2, 1, 0);
        check(untouched[0] == 0xFF000000 && untouched[1] == 0xFFFFFFFF, "radius 0 is a no-op");
        System.out.println("BlurTest passed");
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash launcher/tests/run.sh`
Expected: FAIL at compile time: `cannot find symbol ... class Blur`.

- [ ] **Step 3: Write the minimal implementation**

Create `launcher/src/tv/dumbtv/home/Blur.java`:

```java
package tv.dumbtv.home;

/** A small box blur for the glass backdrop. Android 9 has no live blur, so this runs once per wallpaper. */
final class Blur {
    private Blur() {}

    /** Blurs {@code px} (ARGB, w x h) in place: window of 2*radius+1, edges clamped, rows then columns. */
    static void box(int[] px, int w, int h, int radius) {
        if (radius <= 0) return;
        int[] line = new int[Math.max(w, h)];
        for (int y = 0; y < h; y++) pass(px, y * w, 1, w, radius, line);
        for (int x = 0; x < w; x++) pass(px, x, w, h, radius, line);
    }

    private static void pass(int[] px, int start, int step, int n, int r, int[] out) {
        int window = 2 * r + 1;
        for (int shift = 0; shift < 32; shift += 8) {
            long sum = 0;
            for (int k = -r; k <= r; k++) sum += channel(px[start + clamp(k, n) * step], shift);
            for (int i = 0; i < n; i++) {
                out[i] = (int) (sum / window);
                sum += channel(px[start + clamp(i + r + 1, n) * step], shift)
                        - channel(px[start + clamp(i - r, n) * step], shift);
            }
            for (int i = 0; i < n; i++) {
                int p = start + i * step;
                px[p] = px[p] & ~(0xFF << shift) | (out[i] & 0xFF) << shift;
            }
        }
    }

    private static int channel(int pixel, int shift) {
        return pixel >>> shift & 0xFF;
    }

    private static int clamp(int i, int n) {
        return i < 0 ? 0 : i >= n ? n - 1 : i;
    }
}
```

- [ ] **Step 4: Run all tests**

Run: `bash launcher/tests/run.sh`
Expected: six `... passed` lines including `BlurTest passed`.

- [ ] **Step 5: Commit**

```bash
git add launcher/src/tv/dumbtv/home/Blur.java launcher/tests/BlurTest.java
git commit -m "feat: add Blur, a cached-backdrop box blur

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Focus lift on `Tile`

**Files:**
- Modify: `vendor/dumbtv/launcher/src/tv/dumbtv/home/Tile.java` (constructor and `onFocusChanged`)

**Interfaces:**
- Consumes: `TvosStyle.active(String)`, `TvosStyle.FOCUS_SCALE`, `TvosStyle.LIFT_DP`, `Config.get(Context).get(Config.LAYOUT)`, `Ui.dp(Context, float)`.
- Produces: in `layout=tvos`, app tiles scale to 1.12 and rise 14 dp (shadow) on focus; every other layout and input tiles behave exactly as before.

This task has no host test: it is drawing behaviour. It is pinned on the device in Step 5, and the build in Step 4 is the compile check.

- [ ] **Step 1: Add the imports**

In `Tile.java`, add alongside the existing imports (skip any already present):

```java
import android.graphics.Outline;
import android.view.ViewOutlineProvider;
import android.view.ViewPropertyAnimator;
```

- [ ] **Step 2: Add the field and constructor setup**

Add the field next to `private boolean moving;`:

```java
    private final boolean lift;
```

In the constructor, directly after the `afterglow = ...` assignment, add:

```java
        lift = app && TvosStyle.active(Config.get(c).get(Config.LAYOUT));
        if (lift) {
            // The shadow follows this outline; Tile draws itself, so it has no background to take it from.
            setOutlineProvider(new ViewOutlineProvider() {
                @Override
                public void getOutline(View v, Outline outline) {
                    outline.setRoundRect(0, 0, cardW, cardH, radius);
                }
            });
        }
```
(`radius` is assigned later in the constructor; the provider only reads it when the view is drawn, after construction. Declared `final`, so the lambda-free anonymous class reading it is legal because it runs after assignment. If javac reports "variable radius might not have been initialized", move this `if (lift) {...}` block to just after the line `radius = Ui.dp(c, 10);`.)

- [ ] **Step 3: Replace `onFocusChanged`**

Replace the body of `onFocusChanged` (keep the signature and the `super` call and the final `invalidate()`):

```java
    @Override
    protected void onFocusChanged(boolean focused, int direction, Rect previous) {
        super.onFocusChanged(focused, direction, previous);
        animate().cancel();
        if (focused) {
            float scale = lift ? TvosStyle.FOCUS_SCALE : FOCUS_SCALE;
            ViewPropertyAnimator a = animate().scaleX(scale).scaleY(scale).setDuration(110);
            if (lift) a.translationZ(Ui.dp(getContext(), TvosStyle.LIFT_DP));
            a.start();
        } else {
            setScaleX(1f);
            setScaleY(1f);
            setTranslationZ(0f);
        }
        invalidate();
    }
```

- [ ] **Step 4: Run host tests and build**

```bash
cd ~/Developer/firetvdebloate/vendor/dumbtv
bash launcher/tests/run.sh && bash launcher/build.sh
```
Expected: all tests pass; build ends `built build/dumbtv-home.apk ... 3 uses-permission entries`.

- [ ] **Step 5: Commit (device check happens in Task 7)**

```bash
git add launcher/src/tv/dumbtv/home/Tile.java
git commit -m "feat: lift and shadow the focused dock tile in the tvos layout

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```
Note for Task 7: with the user's `tile_style=afterglow` config this tile must still draw (Review Focus 2).

---

### Task 5: `TopShelf` view and wiring

**Files:**
- Create: `vendor/dumbtv/launcher/src/tv/dumbtv/home/TopShelf.java`
- Test: `vendor/dumbtv/launcher/tests/TopShelfTest.java`
- Modify: `vendor/dumbtv/launcher/src/tv/dumbtv/home/Home.java` (fields; `build()`; `render(Row)`; `focusBackground`)

**Interfaces:**
- Consumes: `TvosStyle.glow(int)`, `TvosStyle.active(String)`, `FocusColor.FALLBACK`, `Catalog.label(Config, Item) -> CharSequence`, `Ui.dp`, `Ui.TEXT`, `Ui.LIGHT`.
- Produces: `TopShelf(Context)` extends `View`; `show(CharSequence title, int color)` (cheap when unchanged); `static String clip(String title, int max)` (null-safe, ends in an ellipsis when cut); Home field `shelf`.

- [ ] **Step 1: Write the failing test**

Create `launcher/tests/TopShelfTest.java`:

```java
package tv.dumbtv.home;

/** The shelf title helper never returns null and never exceeds its limit. */
public final class TopShelfTest {
    private static void check(boolean ok, String name) {
        if (!ok) throw new AssertionError(name);
    }

    public static void main(String[] args) {
        check("".equals(TopShelf.clip(null, 20)), "null title is empty");
        check("".equals(TopShelf.clip("", 20)), "empty title is empty");
        check("Netflix".equals(TopShelf.clip("Netflix", 20)), "short title is kept");
        String longName = "A very long application name that would run off the screen";
        String clipped = TopShelf.clip(longName, 20);
        check(clipped.length() == 20, "long title is cut to the limit");
        check(clipped.endsWith("\u2026"), "long title ends with an ellipsis");
        System.out.println("TopShelfTest passed");
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash launcher/tests/run.sh`
Expected: FAIL at compile time: `cannot find symbol ... class TopShelf`.

- [ ] **Step 3: Write `TopShelf`**

Create `launcher/src/tv/dumbtv/home/TopShelf.java`:

```java
package tv.dumbtv.home;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.RadialGradient;
import android.graphics.Shader;
import android.text.TextPaint;
import android.view.View;

/** The strip above the dock: the focused app's name in large type over a glow in its colour. */
final class TopShelf extends View {
    private static final int NAME_LIMIT = 36;

    private final int height, edge;
    private final Paint glow = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final TextPaint name = new TextPaint(Paint.ANTI_ALIAS_FLAG);
    private String title = "";
    private int color = FocusColor.FALLBACK;

    TopShelf(Context c) {
        super(c);
        height = Ui.dp(c, 150);
        edge = Ui.dp(c, 56);
        name.setColor(Ui.TEXT);
        name.setTypeface(Ui.LIGHT);
        name.setTextSize(Ui.dp(c, 44));
    }

    /** Keeps the title to {@code max} characters, ending in an ellipsis when it is cut. */
    static String clip(String title, int max) {
        if (title == null) return "";
        return title.length() <= max ? title : title.substring(0, max - 1) + "\u2026";
    }

    void show(CharSequence label, int tint) {
        String next = clip(label == null ? null : label.toString(), NAME_LIMIT);
        if (next.equals(title) && tint == color) return;
        title = next;
        color = tint;
        rebuild();
        invalidate();
    }

    private void rebuild() {
        int w = getWidth();
        if (w == 0) return;
        glow.setShader(new RadialGradient(w * 0.28f, height * 0.9f, w * 0.6f,
                TvosStyle.glow(color), 0x00000000, Shader.TileMode.CLAMP));
    }

    @Override
    protected void onMeasure(int widthSpec, int heightSpec) {
        setMeasuredDimension(MeasureSpec.getSize(widthSpec), height);
    }

    @Override
    protected void onSizeChanged(int w, int h, int oldW, int oldH) {
        rebuild();
    }

    @Override
    protected void onDraw(Canvas canvas) {
        canvas.drawRect(0, 0, getWidth(), height, glow);
        canvas.drawText(title, edge, height * 0.62f, name);
    }
}
```
(Ellipsis here is by character count, so very wide glyphs could still run long; at 44 sp and 36 characters on a 1920 px screen that stays inside the width. Accepted limit; a pixel-accurate `TextUtils.ellipsize` is the upgrade if a real label overflows.)

- [ ] **Step 4: Run all tests**

Run: `bash launcher/tests/run.sh`
Expected: seven `... passed` lines including `TopShelfTest passed`.

- [ ] **Step 5: Wire it into `Home.java`**

(a) Fields: after `private View tint;` add:

```java
    private TopShelf shelf;
```

(b) `build()`: directly after `column.addView(head, new LinearLayout.LayoutParams(MATCH, WRAP));` add:

```java
        shelf = new TopShelf(this);
        shelf.setVisibility(View.GONE);
        column.addView(shelf, new LinearLayout.LayoutParams(MATCH, WRAP));
```

(c) `render(Row)`: directly after `row.setVisible(!shown.isEmpty());` add:

```java
        shelf.setVisibility(TvosStyle.active(cfg.get(Config.LAYOUT)) ? View.VISIBLE : View.GONE);
```

(d) `focusBackground`: the shelf needs the focused app's colour even when `background` is not adaptive, so the colour request moves out of the adaptive-only path. Replace this block:

```java
    private void focusBackground(Item it) {
        String mode = cfg.get(Config.BACKGROUND);
        if (!resumed || !"adaptive".equals(mode) && !"adaptive-tint".equals(mode)) return;
        if ("adaptive-tint".equals(mode) && !tintWallpaper) return;
        if (it != null && it.info != null && it.backgroundColor == 0 && !it.colorRequested
                && (it.banner != null || it.icon != null)) {
            it.colorRequested = true;
            colorIo.execute(() -> {
                int color = FocusColor.from(it.banner != null ? it.banner : it.icon);
                ui.post(() -> {
                    it.backgroundColor = color;
                    if (focusedItem() == it) focusBackground(it);
                });
            });
        }
        int color = it == null || it.backgroundColor == 0 ? FocusColor.FALLBACK : it.backgroundColor;
```
with:

```java
    /** Works out the focused item's colour once; the shelf and the adaptive background both read it. */
    private void requestBackgroundColor(Item it) {
        if (it != null && it.info != null && it.backgroundColor == 0 && !it.colorRequested
                && (it.banner != null || it.icon != null)) {
            it.colorRequested = true;
            colorIo.execute(() -> {
                int color = FocusColor.from(it.banner != null ? it.banner : it.icon);
                ui.post(() -> {
                    it.backgroundColor = color;
                    if (focusedItem() == it) focusBackground(it);
                });
            });
        }
    }

    private void focusBackground(Item it) {
        requestBackgroundColor(it);
        shelf.show(it == null ? "" : Catalog.label(cfg, it),
                it == null || it.backgroundColor == 0 ? FocusColor.FALLBACK : it.backgroundColor);
        String mode = cfg.get(Config.BACKGROUND);
        if (!resumed || !"adaptive".equals(mode) && !"adaptive-tint".equals(mode)) return;
        if ("adaptive-tint".equals(mode) && !tintWallpaper) return;
        int color = it == null || it.backgroundColor == 0 ? FocusColor.FALLBACK : it.backgroundColor;
```

- [ ] **Step 6: Build**

```bash
cd ~/Developer/firetvdebloate/vendor/dumbtv
bash launcher/tests/run.sh && bash launcher/build.sh
```
Expected: all tests pass; `built ... 3 uses-permission entries`. (Device checks for Review Focus 3 and 4 happen in Task 7 Step 5.)

- [ ] **Step 7: Commit**

```bash
git add launcher/src/tv/dumbtv/home/TopShelf.java launcher/tests/TopShelfTest.java launcher/src/tv/dumbtv/home/Home.java
git commit -m "feat: add the top shelf above the dock in the tvos layout

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 6: `GlassBand` and wiring

**Files:**
- Create: `vendor/dumbtv/launcher/src/tv/dumbtv/home/GlassBand.java`
- Modify: `vendor/dumbtv/launcher/src/tv/dumbtv/home/Home.java` (fields; `build()`; `render(Row)`; `background()`)

**Interfaces:**
- Consumes: `Blur.box(int[], int, int, int)`, `TvosStyle.active(String)`, `Row.scroll` (the `HorizontalScrollView` of the apps row), the wallpaper `Bitmap` set in `background()`.
- Produces: `GlassBand(View owner)` extends `Drawable`; `setBackdrop(Bitmap source)` (null clears it). Drawn as the apps row's background only when the layout is tvos.

Drawing code has no host test (it needs Android); the pure part (`Blur`) is already pinned in Task 3. This task is pinned on the device in Task 7.

- [ ] **Step 1: Write `GlassBand`**

Create `launcher/src/tv/dumbtv/home/GlassBand.java`:

```java
package tv.dumbtv.home;

import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.ColorFilter;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.PixelFormat;
import android.graphics.Rect;
import android.graphics.RectF;
import android.graphics.drawable.Drawable;
import android.view.View;

/**
 * The dock's glass: a small pre-blurred copy of the wallpaper, stretched over the screen and cut to
 * a rounded band, under a translucent white layer and a hairline edge. With no wallpaper it is the
 * translucent layer alone. Nothing is blurred per frame.
 */
final class GlassBand extends Drawable {
    private static final int SMALL_W = 96, SMALL_H = 54, BLUR_RADIUS = 3;

    private final View owner;
    private final float inset, radius;
    private final Paint flat = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint edge = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint photo = new Paint(Paint.FILTER_BITMAP_FLAG);
    private final RectF box = new RectF(), screen = new RectF();
    private final Path clip = new Path();
    private final int[] where = new int[2];
    private Bitmap backdrop;

    GlassBand(View owner) {
        this.owner = owner;
        inset = Ui.dp(owner.getContext(), 40);
        radius = Ui.dp(owner.getContext(), 28);
        flat.setColor(0x24FFFFFF);
        edge.setStyle(Paint.Style.STROKE);
        edge.setStrokeWidth(Ui.dp(owner.getContext(), 1));
        edge.setColor(0x38FFFFFF);
    }

    /** Takes the wallpaper (any size), keeps a blurred 96x54 copy of it; null removes the backdrop. */
    void setBackdrop(Bitmap source) {
        if (source == null) {
            backdrop = null;
        } else {
            Bitmap small = Bitmap.createScaledBitmap(source, SMALL_W, SMALL_H, true);
            int[] px = new int[SMALL_W * SMALL_H];
            small.getPixels(px, 0, SMALL_W, 0, 0, SMALL_W, SMALL_H);
            if (small != source) small.recycle();
            Blur.box(px, SMALL_W, SMALL_H, BLUR_RADIUS);
            backdrop = Bitmap.createBitmap(px, SMALL_W, SMALL_H, Bitmap.Config.ARGB_8888);
        }
        invalidateSelf();
    }

    @Override
    public void draw(Canvas canvas) {
        Rect b = getBounds();
        box.set(b.left + inset, b.top, b.right - inset, b.bottom);
        clip.reset();
        clip.addRoundRect(box, radius, radius, Path.Direction.CW);
        canvas.save();
        canvas.clipPath(clip);
        if (backdrop != null) {
            // ponytail: assumes the wallpaper fills the screen without cropping; a CENTER_CROP
            // wallpaper of another aspect ratio shifts the blur slightly. Fix by cropping first.
            owner.getLocationOnScreen(where);
            int sw = owner.getResources().getDisplayMetrics().widthPixels;
            int sh = owner.getResources().getDisplayMetrics().heightPixels;
            screen.set(-where[0], -where[1], -where[0] + sw, -where[1] + sh);
            canvas.drawBitmap(backdrop, null, screen, photo);
        }
        canvas.drawRoundRect(box, radius, radius, flat);
        canvas.restore();
        canvas.drawRoundRect(box, radius, radius, edge);
    }

    @Override
    public void setAlpha(int alpha) {}

    @Override
    public void setColorFilter(ColorFilter filter) {}

    @Override
    public int getOpacity() {
        return PixelFormat.TRANSLUCENT;
    }
}
```
(`canvas.drawBitmap(Bitmap, Rect src, RectF dst, Paint)` is the overload used; passing a null `src` draws the whole bitmap.)

- [ ] **Step 2: Wire it into `Home.java`**

(a) Fields: after `private TopShelf shelf;` add:

```java
    private GlassBand band;
```

(b) `build()`: directly after `inputs = new Row(Catalog.INPUTS, "Inputs", column);` add:

```java
        band = new GlassBand(apps.scroll);
```

(c) `render(Row)`: directly after the `shelf.setVisibility(...)` line added in Task 5, add:

```java
        if (Catalog.APPS.equals(row.kind)) {
            row.scroll.setBackground(TvosStyle.active(cfg.get(Config.LAYOUT)) ? band : null);
        }
```

(d) `background()`: replace

```java
        if (file == null) {
            wall.setImageDrawable(null);
            return;
        }
```
with:

```java
        if (file == null) {
            wall.setImageDrawable(null);
            band.setBackdrop(null);
            return;
        }
```
and replace

```java
                if (key.equals(wallKey)) wall.setImageBitmap(b);
```
with:

```java
                if (key.equals(wallKey)) {
                    wall.setImageBitmap(b);
                    band.setBackdrop(b);
                }
```

- [ ] **Step 3: Run host tests and build**

```bash
cd ~/Developer/firetvdebloate/vendor/dumbtv
bash launcher/tests/run.sh && bash launcher/build.sh
```
Expected: all seven tests pass; `built ... 3 uses-permission entries`.

- [ ] **Step 4: Commit**

```bash
git add launcher/src/tv/dumbtv/home/GlassBand.java launcher/src/tv/dumbtv/home/Home.java
git commit -m "feat: add the cached-blur glass band behind the dock in the tvos layout

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Install on the TV, measure the gates, and sign off

**Files:**
- Create: `tools/tvos-verify.sh` (project root `~/Developer/firetvdebloate/tools/`, outside the fork)
- Modify: `README.md` (project root): record the result and rollback steps.

**Interfaces:**
- Consumes: the `tvos` branch build `vendor/dumbtv/launcher/build/dumbtv-home.apk`; saved config `backups/dumbtv-conf/home.conf.20261028.orig`.
- Produces: `bash tools/tvos-verify.sh` prints `PSS_KB`, janky-frame percentage, handoff times, and `PASS`/`FAIL` for each gate; exit code 1 if any gate fails.

- [ ] **Step 1: Write the verification script**

Create `tools/tvos-verify.sh`:

```bash
#!/usr/bin/env bash
# Measures the spec's three gates on the connected TV: memory, janky frames, Home handoff.
set -euo pipefail
SER=${ADB_SERIAL:-<TV_IP>:5555}
PKG=tv.dumbtv.home
A() { adb -s "$SER" shell "$@" </dev/null | tr -d '\r'; }
fail=0
gate() { # name value limit  (pass when value <= limit)
  if python3 -I -c "import sys; sys.exit(0 if float('$2') <= float('$3') else 1)"; then
    echo "PASS $1: $2 <= $3"
  else
    echo "FAIL $1: $2 > $3"; fail=1
  fi
}

A am start -a android.intent.action.MAIN -c android.intent.category.HOME >/dev/null; sleep 5

echo "== memory"
pss=$(A dumpsys meminfo $PKG | awk '$1=="TOTAL" {print $2; exit}')
echo "PSS_KB=$pss"
gate "PSS (KB)" "${pss:-999999}" 60000

echo "== jank while moving focus"
A dumpsys gfxinfo $PKG reset >/dev/null
for _ in $(seq 1 20); do A input keyevent KEYCODE_DPAD_RIGHT; sleep 0.25; done
for _ in $(seq 1 20); do A input keyevent KEYCODE_DPAD_LEFT; sleep 0.25; done
info=$(A dumpsys gfxinfo $PKG)
echo "$info" | grep -E "Total frames rendered|Janky frames"
pct=$(echo "$info" | sed -n 's/.*Janky frames: [0-9]* (\([0-9.]*\)%).*/\1/p' | head -1)
gate "janky frames (%)" "${pct:-100}" 10

echo "== Home handoff (4 runs, system log)"
times=""
for n in 1 2 3 4; do
  A am start -a android.intent.action.MAIN -c android.intent.category.LEANBACK_SETTINGS >/dev/null; sleep 6
  adb -s "$SER" logcat -c </dev/null; A input keyevent KEYCODE_HOME; sleep 7
  t=$(adb -s "$SER" logcat -d -v time </dev/null | python3 -I -c '
import re, sys
def sec(s):
    h, m, r = s.split(":"); return int(h) * 3600 + int(m) * 60 + float(r)
home = disp = None
for line in sys.stdin:
    m = re.search(r"(\d\d:\d\d:\d\d\.\d+)", line)
    if not m: continue
    if home is None and "START u0" in line and "category.HOME" in line and "amazon.tv.launcher" in line: home = sec(m.group(1))
    if disp is None and "Displayed tv.dumbtv.home" in line: disp = sec(m.group(1))
print(round(disp - home, 2) if home and disp else "")')
  echo "run$n: ${t:-n/a}s"; times="$times ${t:-99}"
done
mean=$(python3 -I -c "v=[float(x) for x in '$times'.split()]; print(round(sum(v)/len(v), 2))")
echo "mean=$mean"
gate "Home handoff mean (s)" "$mean" 4.0

exit $fail
```

```bash
chmod +x tools/tvos-verify.sh
```

- [ ] **Step 2: Save the current config and the release as the fallback**

```bash
cd ~/Developer/firetvdebloate
adb -s <TV_IP>:5555 shell cat /sdcard/Android/data/tv.dumbtv.home/files/home.conf </dev/null | tr -d '\r' > backups/dumbtv-conf/home.conf.pre-fork
cat backups/dumbtv-conf/home.conf.pre-fork
```
Expected: the current four-to-seven line config (this is the file to push back on rollback).

- [ ] **Step 3: Baseline the release build with the same script**

```bash
bash tools/tvos-verify.sh | tee scan/verify-baseline-release.txt
```
Expected: runs to the end (gates may pass or fail; this is the comparison number, with `layout=rows`).

- [ ] **Step 4: Install the fork build**

```bash
export ADB_SERIAL=<TV_IP>:5555
bash vendor/dumbtv/launcher/install.sh --undo
adb -s $ADB_SERIAL uninstall tv.dumbtv.home
bash vendor/dumbtv/launcher/install.sh --build
adb -s $ADB_SERIAL push backups/dumbtv-conf/home.conf.pre-fork /sdcard/Android/data/tv.dumbtv.home/files/home.conf
```
Expected: `installed tv.dumbtv.home`, `accessibility: tv.dumbtv.home/tv.dumbtv.home.Guard`, front window `tv.dumbtv.home/tv.dumbtv.home.Home`. (The uninstall deleted the old config, which is why it is pushed back.) If the push is refused because the folder does not exist yet, open the launcher once (press Home), then push again.

- [ ] **Step 5: Turn on the layout and check by eye and by screenshot**

```bash
python3 -I - <<'EOF'
import subprocess
SER='<TV_IP>:5555'; F='/sdcard/Android/data/tv.dumbtv.home/files/home.conf'
cur=subprocess.run(['adb','-s',SER,'shell','cat',F],capture_output=True,text=True,stdin=subprocess.DEVNULL).stdout.replace('\r','')
out=[l for l in cur.splitlines() if l.split('=',1)[0].strip() not in ('layout',)]
out.append('layout=tvos')
open('/tmp/home.conf.tvos','w').write('\n'.join(out)+'\n')
EOF
adb -s <TV_IP>:5555 push /tmp/home.conf.tvos /sdcard/Android/data/tv.dumbtv.home/files/home.conf
adb -s <TV_IP>:5555 shell input keyevent KEYCODE_HOME
sleep 5
adb -s <TV_IP>:5555 shell screencap -p /sdcard/s.png
adb -s <TV_IP>:5555 pull /sdcard/s.png scan/shots/tvos-1.png
```
Then read `scan/shots/tvos-1.png` and check: (1) the shelf shows the focused app's name over a glow, (2) a rounded glass band sits behind the apps row, (3) the focused tile is larger and casts a shadow, (4) with `tile_style=afterglow` still in the config the tiles still draw (Review Focus 2). Move focus right with `adb shell input keyevent KEYCODE_DPAD_RIGHT`, screenshot again as `tvos-2.png`, and onto the Options chip (`KEYCODE_DPAD_UP`) as `tvos-3.png`: the shelf title must clear on the chip (Review Focus 4). An app with a very long label, if one is installed, covers Review Focus 3.

Record each defect found as a fix commit on branch `tvos`, rebuild (`install.sh --build`), and repeat this step.

- [ ] **Step 6: Flat glass (no wallpaper)**

```bash
adb -s <TV_IP>:5555 shell "sed -i 's/^background=.*/background=black/' /sdcard/Android/data/tv.dumbtv.home/files/home.conf"
adb -s <TV_IP>:5555 shell input keyevent KEYCODE_HOME; sleep 5
adb -s <TV_IP>:5555 shell screencap -p /sdcard/s.png && adb -s <TV_IP>:5555 pull /sdcard/s.png scan/shots/tvos-black.png
```
Expected: the band is still drawn (translucent, hairline edge), no crash (Review Focus 1). Check `adb logcat -d | grep -E "FATAL|AndroidRuntime"` returns nothing for `tv.dumbtv.home`.

- [ ] **Step 7: Layout switch back and forth (Review Focus 5)**

```bash
adb -s <TV_IP>:5555 shell "sed -i 's/^layout=.*/layout=rows/' /sdcard/Android/data/tv.dumbtv.home/files/home.conf"
adb -s <TV_IP>:5555 shell input keyevent KEYCODE_HOME; sleep 5
adb -s <TV_IP>:5555 shell screencap -p /sdcard/s.png && adb -s <TV_IP>:5555 pull /sdcard/s.png scan/shots/rows-after.png
```
Expected: shelf and glass gone, the stock rows look as before. Switch back with `sed -i 's/^layout=.*/layout=tvos/'`, press Home, confirm they return.

- [ ] **Step 8: Run the gates**

```bash
bash tools/tvos-verify.sh | tee scan/verify-tvos.txt
```
Expected: three `PASS` lines (PSS <= 60000 KB, janky <= 10%, handoff mean <= 4.0 s). Any `FAIL`: cut or toggle the effect that causes it (shelf glow: replace the gradient with a flat tint; glass: set the band to flat only by skipping `setBackdrop`; lift: drop the shadow by removing the outline provider) and re-run this step. Compare with `scan/verify-baseline-release.txt`.

- [ ] **Step 9: Real-remote check (user)**

Ask the user to press Home from an app with the real remote several times, including after a reboot of the TV, and to judge the look. This is the check that injected key events cannot replace.

- [ ] **Step 10: Record the result and the rollback**

Append to `README.md`:

```markdown

## tvOS fork, plan 1 result (fill in dates and numbers from scan/verify-tvos.txt)
Branch `tvos` in vendor/dumbtv. Installed via `install.sh --build` after removing the release.
Gates: PSS <KB>, janky <pct>%, handoff mean <s>s (baseline release: see scan/verify-baseline-release.txt).
ROLLBACK to the release launcher:
  export ADB_SERIAL=<TV_IP>:5555
  bash vendor/dumbtv/launcher/install.sh --undo
  adb -s $ADB_SERIAL uninstall tv.dumbtv.home
  bash vendor/dumbtv/launcher/install.sh        # downloads release 1.6 and checks its sha256
  adb -s $ADB_SERIAL push backups/dumbtv-conf/home.conf.pre-fork /sdcard/Android/data/tv.dumbtv.home/files/home.conf
```

```bash
git -C vendor/dumbtv log --oneline -8
```
Expected: the commits from Tasks 1-6 on branch `tvos`.

---

## Self-Review

**Spec coverage** (spec sections against tasks)
- 1 Shape (`layout=tvos`, fork, `Guard` untouched): Tasks 1, constraint on `Guard.java`.
- 2 Screen: dock lift Task 4; top shelf Task 5; floating highlight and "Down expands to the full grid": **not in this plan**, deliberately (scope note: they touch `focusSearch` in six places and should be decided after seeing the dock on the TV). The dock itself is the existing apps row.
- 3 Glass: Tasks 3 and 6.
- 4 Wallpapers/screensaver: out of this plan (phases 3-4).
- 5 Recently played/resume: out (phase 5; gated on a Watch Next re-test).
- 6 Carousel: out (phase 6; needs the user's go-ahead).
- 7 Performance budget: Task 7 Steps 3, 8.
- 8 Build and rollback: Task 7 Steps 2, 4, 10.
- 9 Phases: this plan is phases 1-2 plus the on-device sign-off.

**Placeholder scan:** none; every code step has code. The README block in Task 7 Step 10 has bracketed fill-ins for numbers that only exist after measuring, which is the one deliberate blank.

**Type consistency:** `TvosStyle.active/glow/FOCUS_SCALE/LIFT_DP` (Task 2) are used identically in Tasks 4, 5, 6. `Blur.box(int[], int, int, int)` (Task 3) is called with those arguments in `GlassBand` (Task 6). `TopShelf.show(CharSequence, int)` and `TopShelf.clip(String, int)` (Task 5) match the call in `focusBackground` and the test. `GlassBand(View)` and `setBackdrop(Bitmap)` (Task 6) match the `Home.java` wiring. The Task 5 Interfaces block originally mentioned a `fit(...)` helper; the actual helper is `clip(String, int)`, which is what the test and code use.

**Review Focus:** each of the five lines has a named step that pins it (Tasks 3, 4, 5 and 6 as listed above, all exercised in Task 7 Steps 5-7).

**Known risk to watch at execution:** Task 4's anonymous `ViewOutlineProvider` reads `radius`, a `final` field assigned later in the constructor; the Step 2 note gives the fix if javac objects. Task 5(d) moves the colour request out of the adaptive-only path, so every focused item now has its colour computed once, which is a small behaviour change for `layout=rows` too (one background decode per app, cached on the item).
