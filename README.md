# Molecular docking and molecular dynamics — TEM-1 β-lactamase

Reproducible AutoDock Vina docking and GROMACS/OpenMM molecular dynamics
against **TEM-1 β-lactamase (PDB 1BTL)**, run on cloud CPU and GPU through
[Modal](https://modal.com), driven from Windows PowerShell.

Final-year research project, Department of Chemistry, University of Benin,
Nigeria. Target: restore ampicillin activity against β-lactamase-producing
*Escherichia coli* by inhibiting the resistance enzyme rather than replacing
the antibiotic.

---

## What this does

```
  1BTL_clean.pdb  +  ligand SDFs
            │
            ▼
  AutoDock Vina on Modal (CPU)          5 conformers per ligand
  fixed seed, fixed grid                keep the best pose
            │
            ▼
  scores + ligand efficiency + verified identities + pose SDFs
            │
            ▼
  GROMACS / OpenMM molecular dynamics (GPU)      [protocol ready, not yet run]
            │
            ▼
  RMSD · RMSF · Rg · SASA · H-bond occupancy · MM-PBSA
```

---

## Layout

| Path | Contents |
|---|---|
| `docking/modal/vina_app.py` | The Modal app — image definition, docking, SDF export, packaging |
| `docking/scripts/00_modal_login.ps1` | Browser login to Modal, once per PC |
| `docking/scripts/01_write_app_and_build.ps1` | Build the cloud image |
| `docking/scripts/02_stage_and_launch.ps1` | Stage files, launch detached |
| `docking/scripts/03_fetch_results.ps1` | Pull results down, write CSVs |
| `docking/scripts/04_build_complexes.ps1` | Merge receptor + pose into one PDB per compound |
| `data/1BTL_clean.pdb` | Prepared receptor, chain A, no HETATM |
| `data/pocket_and_grid.md` | Catalytic residues, grid coordinates, and why |
| `data/reference_inhibitors.md` | Benchmark drugs with isomeric SMILES and InChIKeys |
| `md/PROTOCOL.md` | Full MD protocol, parameters and limitations |
| `md/notes/` | Handover notes and the open GROMACS worker bug report |

Every PowerShell script carries a header saying what it does and a footer
showing **what the terminal should print if it worked**, plus the failures that
actually happened and how each was fixed.

---

## Three decisions that shape the results

**Several conformers per ligand.** AutoDock Vina samples rotatable bonds but
holds **rings rigid** — whatever ring pucker the input conformer has is frozen
for the entire run. Docking one conformer therefore makes the score depend on
how that conformer happened to be generated. Across two earlier single-conformer
runs, the two compounds with flexible saturated rings moved by 0.5 kcal/mol
while the flat aromatic compounds reproduced to the decimal place. Docking five
ETKDG conformers and keeping the best removes that dependence. Rigid bicyclics
legitimately yield fewer than five distinct conformers.

**Stereochemistry is checked, not assumed.** Avibactam, clavulanic acid and
sulbactam each have two defined stereocentres. Every generated conformer is
re-tested by InChIKey against the input and discarded if the stereochemistry
changed, so a wrong enantiomer can never reach the scoring step.

**Ligand efficiency, not raw affinity.** Vina's score scales with molecular
size. In this six-compound set the Pearson correlation between best affinity
and heavy-atom count is **r = −0.900**, so the raw ranking largely restates
which molecule is biggest. Ligand efficiency (|ΔG| / heavy atoms) is reported
alongside and is the more informative comparison.

---

## Grid

```
Centre   x = 8.972   y = 7.236   z = 39.252
Size     22 × 22 × 22 Å
```

Centroid of the six catalytic functional atoms — Ser70 OG, Lys73 NZ, Ser130 OG,
Asn132 ND2, Glu166 OE1, Lys234 NZ. See `data/pocket_and_grid.md` for the
coordinates, the margin calculation, and why the crystallographic sulfate is
not a good box centre.

---

## Outputs

| File | Contents |
|---|---|
| `vina_scores.csv` | Best and worst affinity, all poses, ligand efficiency, InChIKey, formula |
| `per_conformer_scores.csv` | Every individual conformer's score — the sampling record |
| `ligand_verification.csv` | Formula, heavy atoms, charge, stereocentres, checked before scoring |
| `run_metadata.json` | Vina version, seed, exhaustiveness, grid, size correlation |
| `poses_sdf/*_mode1.sdf` | Best pose, bond orders rebuilt from SMILES |
| `poses_sdf/*_all_poses.sdf` | All nine modes |
| `poses_pdbqt/` | Raw Vina output |

`_mode1.sdf` files carry true bond orders and are what a viewer should be given
for 2D interaction diagrams. The merged complex PDBs from block 04 are more
convenient for 3D work but store connectivity without bond order.

---

## Known failure modes, already solved

**`ModuleNotFoundError: No module named 'scipy'`.** Meeko imports scipy but
does not pull it in. It is in the image's pip list.

**`uploading 0 ligands` then `KeyError: 'best_affinity_kcal_mol'`.** No SDFs
were found at the staging path, so the results table was empty. Block 02 now
searches recursively and refuses to launch with anything missing.

**Vina binary download.** The release asset URL changes between versions, so
the image queries the GitHub releases API and installs whatever the current
linux x86_64 asset is, rather than hardcoding a link that rots.

**GROMACS TPR rejected as too new.** The target worker ran GROMACS 2023.2 and
refused a TPR compiled with a newer build. Compile with the matching version.

---

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- A Modal account (`python -m modal setup`)
- Nothing else locally — RDKit, Meeko, Open Babel and Vina all live in the
  cloud image

---

## Note on compound identity

Three of the six compounds docked in this work are unpublished AI-designed
inhibitors and their structures are **not** included in this repository. The
scripts read ligands from SDF files supplied at run time; only the three
clinically approved benchmark inhibitors are included as structures.

---

**Laurence Jaboro** — Department of Chemistry, University of Benin, Nigeria
Co-founder & President, Protein Design for Africa

---

## Molecular dynamics — run order

| Block | What it does |
|---|---|
| `md/scripts/10_download_app.ps1` | Fetch `md_app.py`, create the working folder |
| `md/scripts/11_selftest.ps1` | Stage files, build the image, build ONE system, measure GPU ns/day |
| `md/scripts/12_production.ps1` | Six GPU containers, equal length, detached |
| `md/scripts/13_analyse_and_report.ps1` | All analyses, figures, CSVs and the PDF (CPU) |
| `md/scripts/14_fetch_results.ps1` | Download everything into Downloads\TEM1_MD_results |

**Always run block 11 before block 12.** Production is six GPU containers for
hours; the self-test costs cents and catches the failures that actually
occurred during development.

### Protonation at pH 7.4

Ligands are not simulated as drawn. Each docked pose is protonated for pH 7.4
by functional group before parameterisation, with heavy-atom coordinates
untouched and an assertion that fires if the heavy-atom count changes:

| Group | pKa | State at pH 7.4 |
|---|---|---|
| Carboxylic acid | ~2.7 | deprotonated, −1 |
| Sulfate ester | <1 | deprotonated, −1 |
| Tetrazole | ~4.9 | deprotonated, −1 |
| Triazole | ~10 | **not** deprotonated |
| Everything else | — | neutral |

This matters mechanistically. Class A β-lactamases have an anion-binding pocket
(Ser130, Lys234, Ser235, Thr235) that recognises the C3/C4 carboxylate of
β-lactam substrates. Simulating clavulanate or sulbactam as a neutral COOH
deletes the interaction that defines how they bind, and a neutral tetrazole
cannot act as the carboxylate bioisostere it is designed to be.

### Why OpenMM and not GROMACS

OpenMM runs natively on CUDA, so the system is built and simulated by the same
program — no topology conversion and nothing to validate. GROMACS only entered
this project because one platform's GPU route required a pre-compiled `.tpr`;
that conversion needed its own single-point energy validation (which passed at
0.0045 %) and the worker then failed anyway. See `md/notes/`.

### Packaging failures already solved

All of these happened. The fixes are in the image definition.

**`No module named 'importlib_resources'`.** `openmmforcefields` imports it at
module load and conda does not pull it in.

**Bare `ImportError` from `openff.interchange`.** Interchange 0.4.x predates
pydantic 2; conda resolved it alongside pydantic 2.11 and the real error was
swallowed by a lazy-import `__getattr__`. Pin `openff-interchange=0.5`.

**`CUDA_ERROR_UNSUPPORTED_PTX_VERSION (222)`.** Left unpinned, conda selects
CUDA 13.4 and OpenMM's kernels carry PTX the L40S driver refuses. Pin
`cuda-version=12.9` — the **lowest** value that solves, because
`openmmforcefields 0.16` forces `openmm >= 8.5.1` and every py3.11 build of
those requires CUDA >= 12.9. Pinning 12.4 makes the environment unsolvable.

**Stale `raw.githubusercontent.com`.** A push is not visible to
`Invoke-WebRequest` for several minutes. Block 10 uses a cache-busting query
string and prints the pinned versions so a stale file is obvious.

### Running offline

Use `run_spawn`, not `run`. A local entrypoint driving `.starmap()` is
cancelled when the client disconnects, **even with `--detach`** — six
simulations 40 minutes into production were lost to a dropped mobile
connection. `.spawn()` queues each call server-side instead.

Confirm before going offline:

```
python -m modal app list
```

`tem1-md` must read `ephemeral (detached)` with `Tasks = 6`. "App completed"
in the launch output is expected — that is the local entrypoint exiting, not
the simulations.

### Cost control

Modal has no dollar cap available in code. The only lever is wall-clock
timeout, so the ceiling is derived from `BUDGET_USD` at the top of
`md_app.py` — one number to change. At $70 across six containers at roughly
$2.10 per GPU-hour that is about 5.5 hours each.

Production steps in 1 ns chunks and stops itself 10 minutes before the
timeout, so hitting the cap saves the trajectory instead of losing it: the
volume is only committed at the end, and a killed container writes nothing.

This is arithmetic, not enforcement. **Also set a spending limit in the Modal
workspace settings** — that is billing-level and is the only thing Modal
actually stops charges on.

Measured on an L40S at 41,906 atoms: 1,271 ns/day as a short burst. Sustained
production is lower. Six containers at 50 ns is roughly 9–18 GPU-hours.
