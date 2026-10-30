# Trajectory movies

Vertical 1080×1920 ray-traced films of each compound in the TEM-1 active site,
rendered from the production trajectories in the `tem1-md` Modal volume. One
20-second film per compound at 24 fps: 480 frames sampled evenly across 50 ns,
so one second of film is 2.5 ns of simulation.

```
md/modal/md_app.py  ->  /cache/prod/<compound>/{start.pdb, traj.dcd}
                              |
                   video/modal/video_app.py
                              |
                        <compound>.mp4
```

## Running it

| Script | Purpose |
|---|---|
| `scripts/20_download_app_and_preview.ps1` | fetch the app, render a 3 s test clip |
| `scripts/21_fetch_and_watch.ps1` | pull finished films into Downloads |
| `scripts/23_deploy_and_launch.ps1` | **all six, 20 s each — use this one** |
| `scripts/22_detached_run.ps1` | the `--detach` route, kept for the record |
| `scripts/24_relaunch_failed.ps1` | re-render only compounds that errored |

Preview first. The three settings worth changing before committing to a full
run are the zoom buffer, `SPIN`, and `label_size`, all near the top of `shard`.

## What the films show

The camera is locked onto the eight pocket residues and never follows the
ligand. That is deliberate: a compound that leaves the site visibly walks out
of frame instead of being chased by the camera. The yellow dashes are polar
contacts recomputed from the coordinates every frame, so a hydrogen bond
breaking and reforming is the real event, not an annotation. The
`IN ACTIVE SITE` / `LEFT THE SITE` badge is driven by the per-frame distance
between the ligand centre of mass and the catalytic centroid, thresholded at
10 Å — the same measurement the analysis uses for bound fraction.

BTL-004's badge flips red briefly around 42 ns. That is the single excursion
visible in `md/results/data/com_dist.csv`, not a rendering fault.

## Why there is no GPU here

PyMOL's `ray` is a CPU ray tracer with no GPU code path; the graphics card is
only used for the interactive viewport, which does not exist headless.
Attaching a GPU would cost money and change nothing. Speed came from two
other places:

**`max_threads` set explicitly.** In a container PyMOL mis-reads the cgroup
CPU limit and often falls back to one or two threads. Setting it to the
container's real core count took the render from roughly 25 s/frame to
**2.2 s/frame**. This was by far the largest single improvement.

**Sharding.** Frame 200 does not depend on frame 199, so the frame range is
cut into eight slices rendered in parallel containers. Same total
core-seconds, about an eightfold reduction in wall time. Each shard derives
its camera from frame 1 and rotates by `step × frame_index`, which is
deterministic — so eight processes that never communicate produce one
continuous camera move. An earlier version used a cumulative `cmd.turn()`,
which only works when one process renders every frame in order.

Full set: ~10–12 minutes, roughly $1.

## Failures worth keeping

**Ambler numbering rebuilt when it did not need to be.** MDAnalysis warns
`PDB file is missing resid information` on these files, so the first version
rebuilt the protein numbering as `position + 26`. But `start.pdb` *does*
carry correct Ambler numbering — 26 to 290, with the standard TEM-1 gaps at
239 and 253. A flat `position + 26` ignores those gaps and shifts everything
after residue 238, silently relabelling **Arg244 as Lys245** — the one
residue the BTL-004 result depends on. The current version verifies the
numbering against known residue identities, only rebuilds if it was genuinely
lost, and asserts every pocket residue is the amino acid it should be before
a single frame is drawn. It prints `pocket residues verified` when it passes.

**Minimum image.** OpenMM wraps each molecule into the primary box
separately, so the ligand can sit a whole box-length from the protein in the
raw coordinates even while bound. Every frame shifts the ligand by the integer
box vector bringing its centre closest to the protein's. Without it the ligand
teleports across the screen at every periodic boundary crossing. Same class of
bug as the one that once made all six ligands appear to have left the site.

**`.spawn()` does not survive a disconnect on its own.** `modal run` without
`--detach` creates an *ephemeral* app that stops the instant the local
entrypoint returns, taking queued spawns with it. The first full run looked
successful — six `spawned` lines, no errors — and `modal app list` then showed
`stopped, 0 tasks`, created and stopped in the same minute. Nothing rendered.
`--detach` keeps the app alive but Modal warns that only the last triggered
function is guaranteed to persist. A **deployed** app has no client to
disconnect from at all, which is why `23_deploy_and_launch.ps1` is the
preferred route. Always verify with `modal app list` before walking away.

**Two batches racing.** Running the detached and deployed launches together
put two sets of shards on the same frame directory. `stitch` deletes every
frame once it has encoded, so whichever finished first pulled the frames out
from under the other and those compounds failed the `frames missing`
assertion. Stop one with `modal app stop <app id>` and let the other finish.

**Labels too large.** At `label_size 20` the residue names collided into an
unreadable pile across the middle of the pocket, and the H-bond distance
numbers stacked on top of them. Fixed in the current version: size 13 with a
black outline and a shadow so they read against both the protein and the
background, offset 3 Å off the atom, cut from eight labels to five
(Ser70, Ser130, Glu166, Lys234, Arg244), distance labels hidden, and the zoom
buffer tightened from 9.0 to 7.5. The dashes already show the contact; the
occupancy numbers belong in the paper, not flickering on screen.

## Confidentiality

The Avibactam, Sulbactam and Clavulanic_acid films show public compounds and
can be shared anywhere. The three BTL films show unpublished structures in
full 3D and should not be posted publicly while the patent position is open.
No structures, SMILES or InChIKeys for the BTL compounds appear in this
directory.
