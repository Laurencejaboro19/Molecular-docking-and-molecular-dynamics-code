# Molecular dynamics protocol

Status: systems built and validated, **production not yet run**. See
`notes/vecura_md_handover_STATUS.md` and `notes/BUG_REPORT_gromacs_tpr_worker.md`.

## System setup — identical for all six complexes

| Item | Setting |
|---|---|
| Protein force field | Amber ff14SB (OpenMM `amber14-all.xml`) |
| Ligand force field | OpenFF Sage 2.1.0 via openmmforcefields SMIRNOFFTemplateGenerator |
| Ligand charges | AM1-BCC (AmberTools antechamber/sqm), computed on the docked conformer |
| Water / ions | TIP3P; neutralised with Na+/Cl-, then 0.15 M NaCl |
| Box | truncated octahedron, 1.0 nm minimum padding, edge 7.6107 nm |
| System size | 31,639–31,650 atoms; 9,161–9,164 waters; 32 Na+ / 25 Cl- |
| Electrostatics | PME, 1.0 nm cutoff, dispersion correction |
| Constraints | bonds to hydrogen; HMR on solute hydrogens (1.5 amu) |
| Timestep | 4 fs production (HMR), 2 fs equilibration |
| Thermostat / barostat | V-rescale 300 K; C-rescale 1 bar |

Starting ligand coordinates are the **top-scoring docked pose**, unchanged.
Ligand hydrogens are rebuilt on the unchanged docked heavy atoms; protein
hydrogens added with OpenMM Modeller.

## Stage order

```
em -> nvt (100 ps) -> npt1..npt5 (5 x 200 ps = 1 ns) -> production
```

NPT restraints are released in stages: 1000 -> 500 -> 200 -> 100 -> 50 -> 0
kJ/mol/nm^2 on protein and ligand heavy atoms. Each stage starts from the
previous stage's coordinates **and velocities** (`grompp -c prev.gro -t prev.cpt
-r start.pdb`).

Equilibration does not count toward production length.

## Engine note

Systems are built with OpenMM + OpenFF Interchange and converted to GROMACS for
execution. This is a change of integration engine, **not** of force field. The
conversion was validated by single-point potential energy on identical
coordinates: OpenMM -212,740.06 kJ/mol vs GROMACS 2023.2 -212,749.66 kJ/mol,
agreeing to **0.0045 %**, with bonded terms agreeing to <=0.01 kJ/mol.

Re-parameterising the ligands with GAFF2 (as some automated MD workflows do)
is NOT acceptable here — it discards the Sage parameters the systems were
built with.

## Analyses to produce

- Protein backbone RMSD vs time
- **Ligand RMSD vs time after alignment on the protein backbone** — reported
  separately from protein RMSD. This is the plot that says whether the ligand
  stayed bound; backbone RMSD alone does not.
- Per-residue RMSF with Ser70, Lys73, Ser130, Asn132, Glu166, Lys234 labelled
- Radius of gyration, SASA
- Hydrogen bond count vs time, plus a per-residue occupancy table
- Ligand centre-of-mass distance from the catalytic centroid (8.972, 7.236, 39.252)
- MM-PBSA / MM-GBSA with per-residue decomposition, if available

All six plotted on shared axes so the designed compounds read directly against
the three clinical inhibitors.

## Stated limitations

- Non-covalent treatment of avibactam, clavulanic acid and sulbactam, which
  really acylate Ser70
- Ligands modelled neutral, although clavulanic acid, sulbactam and the
  tetrazole-containing compound would be anionic at pH 7.4
- Single replicate per system

---

## 100 ns extension runs (tag `prod100`)

Two systems were extended to 100 ns as independent replicates with explicit
random seeds: **BTL-004** (seed 40001) and **Avibactam** (seed 40002). Both
completed in full — `prod.csv` ends at 101,100 ps, which is 100 ns of
production on top of 1.1 ns of equilibration.

Scripts: `md/scripts/15_long_runs_100ns.ps1`, `16_verify_and_analyse.ps1`,
`17_fetch_100ns_report.ps1`. Films: `video/scripts/25_100ns_films.ps1`.

### Result

| | mean ligand RMSD | mean COM distance | outcome |
|---|---|---|---|
| Avibactam | 2.98 Å | 5.47 Å | bound throughout |
| BTL-004 | 27.24 Å | 23.33 Å | **left the active site** |

Avibactam reproduces its 50 ns behaviour. **BTL-004 does not.** In the 50 ns
run it was bound for 95.8% of frames with a single excursion near 42 ns; in
this independent 100 ns run it left and did not return, ending up against
surface residues (Arg120 41.1%, with Thr118, Arg94, Gly92, Leu91) rather than
the catalytic pocket. Its active-site contacts — Ser130 21.7%, Ser235 18.5% —
are from the period before it left.

BTL-004 therefore stands at one run bound, one run not. No claim of stable
binding can be made from the current data, and further replicates on that
compound specifically are the next thing worth running.

### Hydrogen-bond occupancies are not reproducible at n = 1

Avibactam stayed bound in both runs, but its contact profile differs
completely: Ser130 62.5% at 50 ns against 13.4% at 100 ns, with Arg244 and
Asn132 dominating the longer run. Whether a ligand stays is reproducible;
which residue it is touching at any moment is not. Single-run occupancy
figures should not be quoted — report mean ± SD across replicates or omit them.

### Occupancy bug found and fixed

The 100 ns avibactam analysis reported **Arg244 at 115.9%**, which is
impossible. `_hb_pairs` counted rows in `hba.results.hbonds`, and that table
holds one row per bond per frame — two of the ligand's donors reaching the
same residue in one frame counted twice. Occupancy is now the number of
*frames* in which the residue made at least one hydrogen bond, so it is
bounded by 100% as the word implies. Figures produced before this fix are
inflated for any residue making multiple simultaneous contacts.

### Two process failures worth keeping

**`modal run --detach` did not protect the analysis.** Modal warns that
detached mode "only keeps the last triggered Modal function alive". The
connection dropped mid-analysis with `getaddrinfo failed`, the ephemeral app
went with it, and `prod100_report` was never written — `fetch_report` returned
a 45-byte empty tarball. Spawning `analyse` against the **deployed** app
worked. Use `.spawn()` on a deployed function for anything long.

**A budget stop is silent.** `MAX_SECONDS` is derived from
`BUDGET_USD / (rate × N_SYSTEMS)`. Left at values set for six short containers,
a 100 ns run would have been cut off at roughly 55 ns with no error — the
chunked production loop stops itself cleanly. Always check the final
timestamp in `prod.csv` before analysing.

## Replicate runs (tag `prod_r2`)

A second independent 50 ns run of all six systems, identical to `prod` except
for the random seed applied to the Langevin integrator and to the initial
velocity assignment (seeds 20001–20006). Launched by
`scripts/18_replicate_50ns.ps1`. Full numbers and interpretation in
`RESULTS_REPLICATES.md`.

Backbone RMSD across all twelve trajectories: 0.99 ± 0.10 Å. Retention is not
reproducible: clavulanic acid, a licensed TEM-1 inhibitor, was retained in run 1
and left the site in run 2. Ligand retention is therefore not used as a
predictor of activity anywhere in this work.

### `BUDGET_USD` is not a spend cap

`MAX_SECONDS` is derived from `BUDGET_USD / (USD_PER_GPU_HOUR * N_SYSTEMS)`, and
the result is a per-container **timeout**. Modal never reads `BUDGET_USD`. The
actual bill is GPU-hours × rate and depends only on how long the runs take.

Lowering `BUDGET_USD` therefore saves nothing. It shortens the timeout, and the
production loop stops itself 10 minutes before the timeout and writes what it
has — so the run is silently truncated and you pay for the truncated part.
Scripts 18 onwards set `MAX_SECONDS` directly to make this unambiguous. The only
enforced cap is the workspace spending limit in Modal's billing settings.

### Three more process failures worth keeping

**`modal.exe` fails when the working directory has been deleted.** Symptom:
`Program 'modal.exe' failed to run: The directory name is invalid`, followed by
null-reference errors from the surrounding PowerShell. Windows cannot launch any
process from a deleted current directory. It is not a Modal fault and nothing is
wrong with the running jobs. Fix: `Set-Location $env:USERPROFILE` first, and use
`python -m modal` rather than the bare launcher.

**The video app writes to the `tem1-md` volume.** The app is *named* `tem1-video`
but both apps share one volume. `modal volume ls tem1-video ...` returns
`Volume 'tem1-video' not found in environment 'main'`. Films are at
`tem1-md:<tag>_video/<compound>/<compound>.mp4`.

**Launching the same film twice races on the frame directory.** `stitch` deletes
each frame once it has encoded it, so two concurrent launches for the same
compound fight over the same frames and the loser fails the `frames missing`
assertion. Check `TASKS` before relaunching anything.

### Receptor provenance

Three campaigns were launched from three different local folders, and one of
those folders was later deleted. `simulate()` writes `_rec.pdb` beside every
trajectory, so the receptor each run actually used is preserved on the volume.
`scripts/21_verify_receptor_provenance.ps1` hashes those against the docking
receptor; all returned `D8F974B3AEA9AE87EFB86C495B10E52A`, closing the chain
from `1BTL_clean.pdb` through docking to every MD run.
