# Replicate results — two independent 50 ns runs per compound

Tag `prod` is the first run (unseeded). Tag `prod_r2` is the second, identical
in every respect except the random seed applied to the Langevin integrator and
the initial velocity assignment (seeds 20001–20006). Same receptor, same docked
poses, same force field, same box, same length. Verified same receptor by MD5 —
see `scripts/21_verify_receptor_provenance.ps1`.

## Per-trajectory means over 50 ns of production

| Compound | Charge | Rep | Backbone RMSD (Å) | Ligand RMSD (Å) | COM distance (Å) | Outcome |
|---|---|---|---|---|---|---|
| Avibactam | −1 | 1 | 0.84 | 2.20 | 4.36 | bound throughout |
| Avibactam | −1 | 2 | 1.03 | 1.12 | 4.13 | bound throughout |
| Clavulanic acid | −1 | 1 | 1.04 | 1.27 | 4.42 | bound throughout |
| Clavulanic acid | −1 | 2 | 1.21 | 40.24 | **40.37** | **left the site** |
| Sulbactam | −1 | 1 | 0.95 | 6.17 | 9.60 | drifting from 23 ns |
| Sulbactam | −1 | 2 | 0.86 | 1.35 | 5.32 | bound throughout |
| BTL-004 | −1 | 1 | 1.08 | 5.14 | 7.30 | bound, mobile |
| BTL-004 | −1 | 2 | 0.97 | 32.01 | 30.28 | left the site |
| BTL-023 | 0 | 1 | 1.00 | 33.57 | 28.25 | left at 12.3 ns |
| BTL-023 | 0 | 2 | 0.85 | 9.70 | 11.85 | marginal |
| BTL-007 | 0 | 1 | 0.99 | 28.27 | 27.11 | left at 4.5 ns |
| BTL-007 | 0 | 2 | 0.98 | 26.29 | 24.23 | left the site |

## Aggregate

| Compound | Rep 1 COM (Å) | Rep 2 COM (Å) | Mean ± SD (Å) | Replicates retained |
|---|---|---|---|---|
| Avibactam | 4.36 | 4.13 | 4.25 ± 0.16 | **2 / 2** |
| Sulbactam | 9.60 | 5.32 | 7.46 ± 3.03 | 2 / 2 |
| Clavulanic acid | 4.42 | 40.37 | 22.39 ± 25.42 | 1 / 2 |
| BTL-004 | 7.30 | 30.28 | 18.79 ± 16.25 | 1 / 2 |
| BTL-023 | 28.25 | 11.85 | 20.05 ± 11.60 | 0 / 2 |
| BTL-007 | 27.11 | 24.23 | 25.67 ± 2.04 | 0 / 2 |

Retained means a trajectory mean centre-of-mass distance below 10 Å from the
catalytic centroid.

## What the replicates changed

**The headline result from run 1 did not reproduce.** BTL-004 stayed in the site
in `prod` and left in `prod_r2`. It also left in both 100 ns runs. One run in
four kept it.

**Clavulanic acid did the same thing, and that is the finding.** Clavulanate is a
licensed, clinically effective TEM-1 inhibitor. It was the most tightly held
ligand in `prod` at 4.42 Å and 40.37 Å away in `prod_r2`. A method that cannot
retain clavulanate cannot be used to rank anything.

The reason is mechanistic rather than numerical. All three clinical comparators
inhibit TEM-1 by covalently acylating or carbamoylating Ser70. A classical
simulation cannot form that bond, so nothing holds them in the site but
transient non-covalent contacts, and whether those persist for 50 ns is a
property of the random seed.

Avibactam is the exception that shows the mechanism: its sulfamate anchors in
the Ser235/Arg244 anion-binding pocket — the same interaction confirmed
crystallographically by the cross-docking validation against 8DE0 — and it is
the only ligand retained in every run.

## What the replicates do support

Backbone RMSD across all twelve trajectories is **0.99 ± 0.10 Å**, range
0.84–1.21 Å. Radius of gyration varies by under 0.5 Å. Every system was stable,
correctly parameterised, and started from a physically reasonable docked pose.
That is reproducible and it is worth reporting.

## Consequences for how these runs may be used

- **Do not rank compounds on simulated retention.** The clavulanate result
  forbids it.
- **Do not quote single-run hydrogen-bond occupancies.** Which residue a ligand
  touches varies between replicates even when the ligand stays bound.
- **Do not quote any occupancy produced before the row-counting fix.** See
  `PROTOCOL.md`.
- **Report the backbone stability.** It is the one thing every run agrees on.
- **The enzyme assay decides.** Nothing here says a compound is inactive; it says
  the simulation cannot tell.
