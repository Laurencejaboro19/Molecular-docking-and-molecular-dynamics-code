# =============================================================================
# BLOCK 12 - PRODUCTION: ALL SIX COMPOUNDS, EQUAL LENGTH
# =============================================================================
# WHAT THIS DOES
#   Launches one GPU container per compound. Each one rebuilds its system from
#   the docked pose, minimises, equilibrates, and runs production.
#
#   Per compound:
#     energy minimisation
#     NVT   100 ps, 300 K, solute heavy atoms restrained at 1000 kJ/mol/nm^2
#     NPT   5 x 200 ps at 300 K / 1 bar, restraints released
#           1000 -> 500 -> 200 -> 100 -> 50 -> 0
#     production  NPT, 4 fs timestep with hydrogen mass repartitioning,
#                 frames every 10 ps, checkpoint every 100 ps
#
#   Equilibration (1.1 ns) does NOT count toward the production length.
#
# WHY --detach MATTERS
#   The containers run on Modal's hardware. Once this prints a call ID you can
#   close PowerShell, shut the laptop, lose power or go offline and the run
#   continues. Results persist in the Modal volume until fetched.
#
# WHY EQUAL LENGTH MATTERS
#   The comparison between the designed compounds and the three clinical
#   inhibitors is the whole point. Six runs of 30 ns is publishable; three of
#   50 ns and three of 20 ns is not.
#
# COST
#   There is NO spend cap in this code. timeout=24h per container is a
#   wall-clock ceiling, not a budget. Set a spending limit in your Modal
#   workspace settings - that is the only real backstop.
#
#   Six containers at 50 ns, 400-900 ns/day sustained, is roughly 9-18
#   GPU-hours. At about $2/hour for an L40S that is about $18-36.
# =============================================================================

$dir = "$env:USERPROFILE\Downloads\tem1_md"
$ns  = 50                     # <-- set from the self-test measurement
Set-Location $dir
$env:PYTHONUTF8="1"; $env:PYTHONIOENCODING="utf-8"

$n = (Get-ChildItem "$dir\ligands\*.sdf").Count
if ($n -ne 6) { Write-Host "Expected 6 ligands, found $n - stopping." -ForegroundColor Red; return }

python -m modal run --detach md_app.py::run `
    --pdb "$dir\receptor.pdb" --ligdir "$dir\ligands" --tag prod --ns $ns

# WHAT YOU SHOULD SEE IF IT WORKED
#   launching 6 simulations at 50 ns each
#   [BTL-004] 41906 atoms, charge -1, tetrazolate
#   [BTL-004] restrained solute heavy atoms: 2044
#   [BTL-004] minimising
#   [BTL-004] NVT done
#   [BTL-004] NPT stage k=500 done
#   [BTL-004] NPT stage k=200 done
#   ... through k=0 ...
#   [BTL-004] production 50.0 ns (12500000 steps)
#   / Running (6/6 containers active)...
#
#   Reaching "production" for all six means the restraints, the barostat and
#   the staged release all worked.
#
#   DO NOT press Ctrl+C in this window. Open a second PowerShell window if you
#   need the prompt. Monitor from the Modal dashboard link instead - it works
#   with the PC switched off.
#
#   Check the speed after ten minutes in the dashboard logs. The reporter
#   prints a Speed (ns/day) column. Below 400 ns/day, consider stopping and
#   restarting all six at 30 ns rather than overrunning the budget.
