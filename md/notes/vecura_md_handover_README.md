# TEM-1 (1BTL chain A) x 6 ligands: portable MD handover
Ligands (neutral, non-covalent): BTL-023, BTL-007, BTL-004, Avibactam, Clavulanic_acid, Sulbactam.
Starting ligand heavy-atom coordinates = AutoDock Vina mode 1 of Vecura job 47255933 (unchanged, max deviation 0.000 A);
ligand hydrogens were rebuilt (RDKit AddHs addCoords) on those heavy atoms; protein hydrogens added with OpenMM Modeller at pH 7.0 (receptor otherwise unmodified).

| Item | Setting |
|---|---|
| Protein force field | Amber ff14SB (OpenMM `amber14-all.xml`) |
| Ligand force field | OpenFF Sage 2.1.0 (`openff-2.1.0`) via openmmforcefields SMIRNOFFTemplateGenerator |
| Ligand charges | AM1-BCC (AmberTools antechamber/sqm 26.0) computed on the docked conformer; all ligands net charge 0 |
| Water / ions | TIP3P; neutralised with Na+/Cl-, then 0.15 M NaCl (32 Na+, 25 Cl- in every system) |
| Box | truncated octahedron, 1.0 nm minimum padding, edge 7.6107 nm (identical for all six) |
| Systems | 31,639-31,650 atoms; 9,161-9,164 waters |
| Electrostatics / cutoffs | PME, 1.0 nm cutoff, dispersion correction |
| Constraints / HMR | bonds to H constrained; HMR on solute hydrogens (1.5 amu), water at standard masses; production dt 4 fs |
| Thermostat / barostat | V-rescale 300 K; C-rescale 1 bar (NPT) |
| Validated conversion | OpenMM vs GROMACS 2023.2 single-point energy on BTL-004, identical coordinates: -212740.06 vs -212749.66 kJ/mol = 0.0045 % (bond/angle/torsion agree to <=0.01 kJ/mol) |

Protocol files in `mdp/`: em.mdp (steepest descent, Fmax<100, heavy atoms restrained 1000), nvt.mdp (100 ps, 2 fs, 1000 restraint), npt1-5.mdp (5 x 200 ps = 1 ns,
restraint 500/200/100/50/0 kJ/mol/nm2), prod.mdp (4 fs, NPT, frames every 10 ps; nsteps set for 50 ns = 12,500,000 - change once the equal length is agreed).
Order: em -> nvt -> npt1..npt5 -> prod; each stage `grompp -c <previous>.gro -t <previous>.cpt` (to carry velocities) `-r start.pdb`.
GROMACS = 2023.2 (conda-forge). Do NOT compile with a newer GROMACS if running on Vecura's worker (it rejects newer TPRs).
Starting coordinates: use `start.pdb` (full precision); the .gro files round coordinates to 0.01 A and are for convenience only.
Position-restraint topology: `sys.top` (heavy atoms of protein and ligand only; water/ions unrestrained).
Package versions: versions_md_env.txt, versions_gromacs_env.txt. Scripts: scripts/.
Pose SDFs: poses/*_poses.sdf (all 9 modes, corrected hydrogens) and poses/*_mode1.sdf (MD start).

Known caveats: ligands neutral although clavulanic acid, sulbactam and BTL-004 would be anionic at pH 7.4; no covalent Ser70 modelling.
Status at handover: see STATUS.md.
