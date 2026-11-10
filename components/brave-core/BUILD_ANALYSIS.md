# Brave Core build analysis

## Measured baseline

The first successful GitHub Actions build completed on November 10, 2026: [workflow run](https://github.com/iSimStore/simstore-builds/actions/runs/42737521117), [versioned Release](https://github.com/iSimStore/simstore-builds/releases/tag/brave-core/v1.98.64). It built three XCFrameworks for arm64 iOS Simulator from the source and toolchain pins recorded in the recipe and published their provenance in `build-info.json`.

The runner was `xcode-27`, image `20261104.0337.1`, with three virtual Apple M1 CPUs and 7 GiB RAM. Compilation used two local Siso jobs, one GN action slot, and one link slot. Remote execution and build caches were disabled. The measurements below describe one cold build, not guaranteed performance on future runners or upstream versions.

| Phase | Measured duration |
| --- | ---: |
| Source and dependency preparation | 35 min 11 s |
| Core generation and compilation command | 4 h 38 min 24 s |
| Complete macOS build job, including setup, packaging, and uploads | 5 h 16 min 34 s |
| Separate publishing job | 23 s |

The macOS job had only 43 min 26 s left before the six-hour GitHub-hosted job limit. Approximately 14% longer execution would exhaust that margin. [GitHub documents the limit per job](https://docs.github.com/en/actions/reference/limits), so multiple jobs can collectively take longer than six hours.

Siso reported 27,173 steps: 25,983 local executions and 1,190 operations without execution, plus 18,916 skipped steps. The total displayed during a build changes as Siso resolves the graph; task counts are not proportional to elapsed time. Compiler tasks dominate the execution count. The three final XCFrameworks are not balanced units of work: `BraveCore` contains the main browser engine, while `NalaAssets` and `PartitionAllocSupport` are much smaller targets.

## Storage and memory

| Measurement | Observed value |
| --- | ---: |
| APFS container capacity | 179.51 GiB |
| Available space before removing Android SDK | 36.07 GiB |
| Available space after removing Android SDK | 49.61 GiB |
| Lowest sampled available space during the build | 4.32 GiB |
| Published `brave-core.tar.bz2` | 89,755,519 bytes, approximately 85.60 MiB |
| Maximum RSS reported by `time -l` for the Core command | 2.18 GiB |

Disk, memory, process counts, and the largest processes were sampled every ten seconds and retained in the diagnostics artifact. Available filesystem space fell by approximately 45.29 GiB after cleanup; this includes filesystem activity beyond the recipe and is not a direct measurement of the workspace's allocated size. Sampling may miss shorter peaks. The RSS figure is not the combined peak memory of every process on the runner.

The small published archive contains finished frameworks, generated build configuration, and the upstream license. It does not contain source checkouts, Git objects, toolchains, package stores, generated intermediates, or compiler object files. A build checkpoint would therefore be much larger than the Release archive. The earlier 30 GiB free-space planning estimate would not accommodate this measured recipe.

## Splitting the work across jobs

### Sequential continuation

Job A prepares the environment and builds a selected subset of dependency targets. It then archives a consistent checkpoint. Job B restores that checkpoint on another runner and completes compilation, linking, validation, and packaging. Artifacts can [transfer files between jobs](https://docs.github.com/en/actions/tutorials/store-and-share-data).

This reduces the longest individual job and provides protection against the six-hour limit. Total workflow time increases because of checkpoint compression, transfer, extraction, and any repeated environment preparation. Individual jobs of roughly three to four hours are a planning target, not a measured result.

The checkpoint must preserve the required object files, generated files, dependency information, Siso state, and relevant file metadata. Source revisions, patches, compiler and SDK versions, GN arguments, and filesystem paths must remain compatible. Recreating inputs with different timestamps or regenerating the build graph can invalidate reuse; this must be tested rather than assumed. A checkpoint containing only finished frameworks cannot resume a partial compilation.

Choose a dependency-target boundary so that Job A finishes normally and writes consistent build state. Terminating an arbitrary build at a wall-clock deadline can leave interrupted actions and requires separate recovery testing.

Moving preparation alone into another job transfers approximately 35 minutes of work. The remaining Core command still takes about 4 h 38 min before checkpoint restoration and packaging overhead, so that change buys headroom but does not divide the main compilation in half.

### Parallel partitions

After shared prerequisites are prepared, two jobs can build different groups of Core targets or object files, followed by a job that assembles the results and performs final linking and packaging. This can reduce total workflow time as well as the longest job.

Partitions must follow the dependency graph and measured task costs. Shared prerequisites may otherwise be built twice, and generated inputs or host tools can introduce dependencies between proposed groups. Splitting by the three final framework names would leave nearly all work in the `BraveCore` job.

Combining independently built output directories also requires care: Siso dependency and filesystem state cannot be assumed to merge by overwriting one directory with another. The final build must recognize both partitions as reusable rather than compile one again. A compatible action cache or an explicitly validated assembly strategy may be needed. Serial prerequisites, final linking, repeated setup, and transfers prevent a guaranteed twofold speedup; a smaller speedup remains an experimental target.

## Recommended next experiment

Keep the successful single-job build as the baseline. Before attempting a full split, build a small representative target subset on one runner, transfer its checkpoint, and request the same targets on a second runner. Include generated inputs and host-tool dependencies in the subset. Verify from Siso's execution records that completed compiler actions are reused, that the resulting binaries still target arm64 iOS Simulator, and that a changed input triggers the expected rebuild.

Measure checkpoint size, compression and transfer time, extraction time, and the extra disk space needed while an archive and extracted outputs coexist. With only 4.32 GiB left in the successful run, creating a full workspace archive alongside its contents could exceed available space. Selective checkpoints, removing regenerable caches, or streaming transfers may be necessary.

If cross-runner reuse works and transfer costs are acceptable, use the successful run's timing records to choose a balanced sequential boundary first. If reuse fails, resolve input, path, timestamp, or build-state invalidation before attempting a large build. If faster total turnaround later becomes necessary, evaluate parallel graph partitions separately. No multi-job continuation or parallel partition has been validated yet.

## Manual workflow

The component workflow is dispatched manually with a component `id` and a `version` matching that recipe's pinned manifest. A leading `v` is optional in the input; the manifest determines the Release tag. Updating to another upstream version requires updating the source and toolchain pins before dispatching the workflow. This avoids publishing old source under an unrelated version number.

The workflow performs the build, validates the resulting frameworks, uploads artifacts and diagnostics, and creates a versioned component Release. It does not run lint, type checks, or the repository test suite, and it has no pull-request or push trigger.
