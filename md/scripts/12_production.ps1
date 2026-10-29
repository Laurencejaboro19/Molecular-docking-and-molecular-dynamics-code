# =============================================================================
# BLOCK 12 - PRODUCTION: ALL SIX COMPOUNDS, EQUAL LENGTH
# =============================================================================
# Each compound gets its own GPU container and they run in parallel, so the
# wall-clock time is roughly one run, not six.
#
# Per compound: minimise -> NVT 100 ps -> NPT 5 x 200 ps with restraints
# released 1000/500/200/100/50/0 -> production.
#
# Set $ns from the self-test number. Keep it IDENTICAL for all six - an
# unequal comparison is not publishable.
#
# Detached: close PowerShell, lose power, the runs continue.
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
#   [BTL-004] 31043 atoms, charge -1, tetrazolate
#   [BTL-004] restrained solute heavy atoms: 2044
#   [BTL-004] minimising
#   [BTL-004] NVT done
#   [BTL-004] NPT stage k=500 done
#   ...
#   [BTL-004] production 50 ns (12500000 steps)
#   [BTL-004] done in N.NN h
#
#   Watch the StateDataReporter output for speed and remaining time. Progress
#   is also visible on the Modal dashboard.
#
# IF IT FAILS
#   One compound dies, the rest continue
#       They are independent containers. Re-run just that one by moving the
#       other five SDFs out of the ligands folder temporarily.
#
#   Out of memory
#       Drop to one container at a time, or request a larger GPU.
