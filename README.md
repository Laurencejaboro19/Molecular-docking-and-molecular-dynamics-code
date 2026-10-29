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
