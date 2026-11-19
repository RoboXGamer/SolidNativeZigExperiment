# Clock/driver integrated acceptance

The implementation in PR #402 is qualified by the native follow-up in
`4fc8b8c`. This completes #344 and #345 and their parent #343. The wider Windows
host (#346), HMR roadmap (#364), Rune work (#376) and general allocation budget
gates (#377) keep their own acceptance criteria.

## Native lifecycle and admission

`pnpm test:clock:acceptance` runs an actual Vite producer, Windows watcher,
QuickJS runtime, Solid renderer and named-pipe controller. Component refresh
disposes its old timer, installs one replacement, cancels held pointer input
and rejects the retired graph's numeric target. The unrelated entry timer still
fires once. A full graph reload retires both rearmed owners without rewinding
app time. Restarting the native VM rejects the previous runtime generation.
Solid's existing component-refresh contract resets replaced local signals;
this test does not introduce private-state serialization.

The driver edge fixture covers transformed hit testing; clipped/occluded target
refusal; select pointer and keyboard actions; popover admission and Escape;
removal and same-ID reparenting between press and release; resolving the moved
node at its current geometry; focus-loss held-key/pointer cleanup; stale wake
injection; zero-size resize rejection before mutation; capture after layout and
at a fixed motion pose; read-only inspection without layout/paint; minimized
capture refusal; and normal close.

Capture checks use real child windows in DPI-aware and DPI-unaware thread
contexts, without changing desktop settings. At app time 120 ms, native opacity
is 0.5 in both modes. On this machine, 800x600 and 1200x700 framebuffers report
scale 1.25 (logical 640x480 / 960x560) and 1 (logical 800x600 / 1200x700),
respectively. PNG IHDR dimensions agree with GPU-readback receipts. This proves
the driver pixel/logical-unit contract across those contexts. Physical
multi-monitor DPI migration and physical presentation belong to Windows host
qualification, not this driver acceptance.

An actual idle-run regression exposed a lost one-shot wake: a coarse
`GetTickCount64` comparison could reject a delivery and leave no wake armed.
The worker now uses the performance counter and rearms an early OS delivery;
generation checking still rejects an obsolete delivery. QuickJS remains on the
UI thread.

Raw results:

- [HMR/clock ownership](evidence/clock-hmr-acceptance.json)
- [Debug admission/capture](evidence/driver-edges-Debug.json)
- [ReleaseSafe admission/capture](evidence/driver-edges-ReleaseSafe.json)
- [Ordinary ReleaseSafe no-endpoint/visible-window gate](evidence/driver-release-gate.json)

## Development entrypoint

The user-reported `pnpm dev --example tictactoe` failure was a separate build
path issue: the session manifest supplies an absolute bundle path, but Zig
0.17's `b.path()` accepts only build-root-relative paths. `6f2deed` selects the
absolute lazy-path form for absolute inputs and keeps the relative build path
for ordinary/portable callers.

`pnpm test:dev:native` now launches the actual command, requires the native HMR
`presented` receipt, observes a visible window for five seconds and closes only
that test-owned window normally. This test is part of `test:hmr:native`; the
earlier full integration run and this added entrypoint regression were run
separately. The controlled-driver HMR fixtures remain separate evidence.
[Raw dev launch result](evidence/dev-tictactoe-launch.json).

## Matched complete-host workloads

`pnpm profile:clock:host` builds the same current Windows host with the pipe
driver compiled out and compiled in/listening. Both explicit profile builds
enable identical native/VM accounting and controlled-time data. No controller
traffic occurs during this comparison. The ordinary product build enables
neither profile automation nor allocation probes.

Each optimization has two interleaved repeats per variant, concurrency one,
identical bundled fixture, preferences, viewport and 128 repeated scene rows.
The runner compares scene hashes, app time, paint/layout counts, inspection
bytes and dimensions. Hashes are retained as decimal strings without JS integer
rounding. Measured stages are:

| Stage | Work | App time at end | Paints/layouts |
| --- | --- | ---: | ---: |
| Cold | VM/app/window/text/tree/renderer startup and first frame | 0 ms | 1/1 |
| Unchanged input | 120 pointer moves outside controls | 0 ms | 0/0 |
| Paint | 50 signal/timer paint updates | 50 ms | 50/0 |
| Layout | 50 signal/timer width updates | 100 ms | 50/50 |
| Inspection | 20 bounded 64-node native projection pages | 100 ms | 0/0 |
| Idle | 200 ms real event wait with frozen app clock | 100 ms | 0/0 |

[Debug raw measurements](evidence/clock-full-host-Debug.json) and
[ReleaseSafe raw measurements](evidence/clock-full-host-ReleaseSafe.json) include
every repeat's real wall/CPU nanoseconds, native and QuickJS allocation/free
counts, live/high-water bytes and counts, callback roots, work counts,
inspection bytes, viewport and fixed driver storage. Allocator counts and peaks
are cumulative process-lifetime snapshots at stage boundaries; stage allocation
counts are differences from the preceding snapshot. Both runtimes report zero
tracked native/VM bytes at teardown. Timing is real process time, independent of
virtual app time. The fixtures require zero callback roots after the timers end.

This A/B isolates optional driver overhead in the complete current host. The
historical JS-Map-versus-Zig scheduler comparison remains the separately scoped
[timer microbenchmark](clock-driver.md#validation-and-measurement). Neither
comparison establishes a whole-app historical speedup or a total-process
memory reduction. Requested allocator bytes exclude allocator headers, OS
rounding and C/OS/GPU owners that bypass the wrappers. Fixed driver storage is
reported separately. Hidden local OpenGL windows, fonts, locale and time zone
are those of this machine; CPU affinity/background load are not pinned. The
results are local observations, not a latency budget or statistical performance
claim.

Debug measurements were collected on the working tree based on `1cccf1c` while
the follow-up was developed; ReleaseSafe records the committed implementation
base. The raw reports retain source/dirty status and bundle/executable SHA-256
fingerprints. Historical measurements keep their earlier provenance.

## Regression commands

The qualification includes:

```text
pnpm test
pnpm test:dev:native
zig build test test-native test-runtime -Ddriver=true --summary all
zig build test-runtime -Ddriver=true -Doptimize=ReleaseSafe --summary all
node tools/test-clock-driver.mjs
node tools/test-clock-driver.mjs --release
node tools/test-frame-scheduling.mjs
pnpm test:clock:acceptance
node tools/test-driver-edges.mjs --release
node tools/test-driver-gate.mjs
node tools/profile-clock-host.mjs --debug
pnpm profile:clock:host
```

Native suites that install `zig-out/bin/windows.exe` run serially: Windows
refuses replacing that executable while another suite owns a running process.
The ReleaseSafe driver and disabled gate use separate install prefixes.

## Recorded full-host timing ranges

Every range below contains the two measured repeats; milliseconds, real clocks.
Complete allocation/retention/work counters for each sample are in the raw JSON.

| Build | Stage | Driver out wall / CPU ms | Driver on wall / CPU ms |
| --- | --- | ---: | ---: |
| Debug | cold | 1788.523–1789.307 / 1625.000–1625.000 | 1827.225–1843.447 / 1656.250–1781.250 |
| Debug | noop | 499.766–532.331 / 500.000–531.250 | 519.419–548.512 / 515.625–546.875 |
| Debug | paint | 9773.861–9860.273 / 9515.625–10359.375 | 9692.667–10150.042 / 10062.500–10078.125 |
| Debug | layout | 23672.592–28645.020 / 23062.500–27687.500 | 28069.195–28107.486 / 26953.125–27375.000 |
| Debug | inspection | 381.161–386.804 / 343.750–375.000 | 351.600–375.741 / 312.500–359.375 |
| Debug | idle | 212.388–214.890 / 15.625–15.625 | 206.228–206.980 / 15.625–15.625 |
| ReleaseSafe | cold | 992.658–1121.081 / 953.125–953.125 | 965.297–968.580 / 937.500–968.750 |
| ReleaseSafe | noop | 34.810–36.267 / 31.250–46.875 | 35.324–35.559 / 31.250–31.250 |
| ReleaseSafe | paint | 822.318–825.126 / 593.750–750.000 | 828.701–833.936 / 609.375–718.750 |
| ReleaseSafe | layout | 1433.443–1434.004 / 1656.250–1656.250 | 1419.703–1441.512 / 1625.000–1640.625 |
| ReleaseSafe | inspection | 7.006–7.040 / 0.000–15.625 | 6.715–6.791 / 15.625–15.625 |
| ReleaseSafe | idle | 201.173–201.512 / 0.000–0.000 | 200.384–200.795 / 0.000–0.000 |

[Current per-app driver command/idle measurements](evidence/clock-driver-current.json)
retain the current Debug/ReleaseSafe samples, including failure counts and the
final cursor/fatal-job paths. Older snapshots stay historical.
