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
