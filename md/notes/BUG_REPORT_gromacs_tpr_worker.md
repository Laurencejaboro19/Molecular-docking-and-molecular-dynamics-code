# Bug report: `gromacs` worker fails ("unknown error", no output/log) on valid GROMACS 2023.2 TPR input

**To:** Vecura platform team  **Tool:** `gromacs` / operation `run_molecular_dynamics_simulation` / `input_mode = tpr_file`

## Summary
A pre-built, internally validated protein–ligand TPR compiled with the worker's own GROMACS version (2023.2) is
accepted by the version check but the run then fails with `error_message: "unknown error"`. There is no output
artifact and no log. Two different test TPRs fail the same way, so I cannot tell whether the cause is my input or the worker.

## Failing jobs
| Job ID | Submitted (UTC) | Test TPR | Result |
|---|---|---|---|
| `bfc6c0e9-6a0c-4413-9af7-ae7712e36561` | 2026-10-29 12:46 | `gpu_test23.tpr` (NVT-style, no pressure coupling) | failed after **39.1 s**, "unknown error", no output |
| `8306dbe1-f5aa-4261-b193-84de2e51f8c7` | 2026-10-29 12:47 | `gpu_npt23.tpr` (NPT, C-rescale) | failed after **7.4 s**, "unknown error", no output |

Earlier, for context, job `426eb77f-62d9-4768-957a-f26e9b0332d7` was rejected instantly with a clear message
("This .tpr was generated with a newer GROMACS (2026.3-conda_forge) than this service supports (GROMACS 2023.2)").
That message is how I learned the worker version. After rebuilding with 2023.2 the version gate was passed
(job `bfc6c0e9...` ran for 39 s), then failed with no message.

## Form inputs used (both jobs)
`input_mode = tpr_file`, `tpr_file = <the .tpr below>`, `save_freq_ps = 1`. All other fields left at their defaults
(simulation_time_ns 1.0, nvt_time_ns 0.05, npt_time_ns 0.05, dt 0.002, etc.). It is possible that these defaults
conflict with a TPR input; the form does not say which fields are ignored in TPR mode.

## How the TPRs were built
GROMACS **2023.2-conda_forge**, mixed precision (conda-forge `gromacs=2023.2`, `gmx --version` confirms).
```
gmx grompp -f prod_test.mdp -c sys2.gro -p sys2.top -o gpu_test23.tpr -maxwarn 3    # job bfc6c0e9
gmx grompp -f npt_test.mdp  -c sys2.gro -p sys2.top -o gpu_npt23.tpr  -maxwarn 3    # job 8306dbe1
```
Both compile without errors (`-maxwarn 3` was used to allow standard grompp warnings; I did not record which ones appeared).

## Test files (contents and sizes)
- `gpu_test23.tpr` — 1,772,624 bytes, md5 `efe6c1373c79f376603dd6b14910a3d4`
- `gpu_npt23.tpr` — 1,772,624 bytes, md5 `3a7940c8517c71afc96991328d9f2d7f`
- `sys2.top` (md5 `95ab81eaf62a5ddca35502f4167721ea`, 40,887 lines) and `sys2.gro` (md5 `530dd01fbb4b4a5d5c927ac0f6619a7f`)
- Staged copies: `s3://dev-vecura-workflow/agent-downloads/68804652-1db0-405e-846c-6e2b38369def/b4512b06/gpu_test23.tpr`
  and `.../ee7ac390/gpu_npt23.tpr`

System: TEM-1 β-lactamase (PDB 1BTL chain A) + neutral ligand BTL-004 (21 atoms) in a TIP3P truncated octahedron
(edge 7.6107 nm), 31,643 atoms, 9,164 waters, 32 Na+ / 25 Cl- (0.15 M, neutralised). Amber ff14SB, OpenFF Sage 2.1.0,
AM1-BCC charges, hydrogen mass repartitioning (solute H = 1.5 amu), constraints = h-bonds, dt = 4 fs.
Moleculetypes in the topology: `system1` (protein), `LIG`, `HOH` (water, SETTLE), `NA`, `CL`.

`prod_test.mdp` (job bfc6c0e9):
```
integrator=md  dt=0.004  nsteps=2500  cutoff-scheme=Verlet  coulombtype=PME  rcoulomb=1.0
vdwtype=cut-off  vdw-modifier=none  rvdw=1.0  DispCorr=EnerPres  constraints=h-bonds  constraint-algorithm=lincs
tcoupl=V-rescale  tc-grps=System  tau-t=1.0  ref-t=300  gen-vel=yes  gen-temp=300  gen-seed=42  pcoupl=no
nstenergy=250  nstlog=250  nstxout-compressed=250
```
`npt_test.mdp` (job 8306dbe1) is the same plus: `pcoupl=C-rescale pcoupltype=isotropic tau-p=5.0 ref-p=1.0
compressibility=4.5e-5 nsttcouple=10 nstpcouple=10 nstcalcenergy=125 comm-mode=linear`.

Features that differ from a "standard" auto-built system and might trip a worker pipeline:
a single `tc-grps = System` (no Protein / Non-Protein split), water residue named `HOH` (not `SOL`), a ligand residue `LIG`
inside a separate `[ moleculetype ]`, `gen-vel = yes`, and no index file supplied.

## What the worker returned
`status: failed`, `error_message: "unknown error"`, `jobs.output` → "has no output artifact yet". No log, no stderr, no
partial trajectory or energy file.

## Questions I need answered
1. **Why is a valid GROMACS 2023.2 TPR failing?** Please pull the worker-side stderr/log for the two job IDs above.
   Is the cause one of the features listed above (e.g. expected index groups, water named SOL, a required `analysis_group`),
   a conflict between the form defaults and the TPR's own run parameters, or something else?
2. **Does the worker support multi-stage runs or restarts from a checkpoint?** I need
   minimisation → NVT → NPT (several restraint-release stages) → ~50 ns production, with each stage starting from the previous
   stage's final coordinates **and velocities**. `simulation_time_ns` is capped at 2 ns per job, so 50 ns would need ~25
   chained jobs. Can a job take a checkpoint (`.cpt`) or a TPR built from the previous stage's final state, and can it return
   the energy series (temperature, pressure, density, potential, box) for each stage?

## The system itself is sound (independently validated)
The OpenMM → GROMACS conversion was checked on this exact system (BTL-004): single-point potential energy on identical
coordinates agrees to **0.0045 %** (OpenMM −212,740.06 kJ/mol vs GROMACS 2023.2 −212,749.66 kJ/mol; bond, angle and torsion
terms agree to ≤0.01 kJ/mol; the 9.6 kJ/mol residual is in the PME/non-bonded term). The same GROMACS 2023.2 energy is
reproduced locally with `gmx mdrun -rerun`. So this is not a topology problem on my side as far as I can test.
I have not yet run these two exact test TPRs locally to completion; I will add that result if it is useful.
