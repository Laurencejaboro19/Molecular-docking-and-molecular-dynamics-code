# =============================================================================
# BLOCK 12 - PRODUCTION: ALL SIX COMPOUNDS, EQUAL LENGTH, FULLY OFFLINE
# =============================================================================
# WHAT THIS DOES
#   Spawns one GPU container per compound, server-side, and returns straight
#   away. Each container rebuilds its system from the docked pose, minimises,
#   equilibrates, and runs production.
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
# USE run_spawn, NOT run.
#   `run` drives .starmap() from a local entrypoint. That dies with the client:
#   if the laptop drops its connection the entire map is CANCELLED, even with
#   --detach. This happened - six simulations 40 minutes into production were
#   lost when a mobile connection went down.
#
#   `run_spawn` calls .spawn() for each compound. Those calls are queued
#   server-side and are genuinely independent of your machine.
#
#   Verify with:  python -m modal app list
#   The app must show state "ephemeral (detached)" with Tasks = 6. Only then
#   is it safe to close PowerShell and go offline.
#
# BUDGET
#   There is no dollar cap available in code. The cap is a wall-clock timeout
#   derived from BUDGET_USD at the top of md_app.py, so there is one number to
#   change. At $70 / $2.10 per GPU-hour / 6 containers that is about 5.5 h each.
#
#   Production steps in 1 ns chunks and stops itself 10 minutes before the
#   timeout, so a budget stop saves its trajectory instead of being killed
#   empty. At 50 ns the runs finish in 2-3 h and never reach the cap.
#
#   ALSO set a spending limit in your Modal workspace settings. That one is
#   billing-level and is the only thing Modal actually enforces.
#
# EQUAL LENGTH MATTERS
#   The comparison between the designed compounds and the three clinical
#   inhibitors is the point. Six runs of 30 ns is publishable; three of 50 ns
#   and three of 20 ns is not.
# =============================================================================

$dir = "$env:USERPROFILE\Downloads\tem1_md"
$ns  = 50                     # <-- set from the self-test measurement
Set-Location $dir
$env:PYTHONUTF8="1"; $env:PYTHONIOENCODING="utf-8"

$n = (Get-ChildItem "$dir\ligands\*.sdf").Count
if ($n -ne 6) { Write-Host "Expected 6 ligands, found $n - stopping." -ForegroundColor Red; return }

python -m modal run --detach md_app.py::run_spawn `
    --pdb "$dir\receptor.pdb" --ligdir "$dir\ligands" --tag prod --ns $ns

Write-Host "`nNow confirm it is live before closing this window:" -ForegroundColor Cyan
Write-Host "  python -m modal app list"
Write-Host "  tem1-md must show  ephemeral (detached)  with Tasks = 6"

# WHAT YOU SHOULD SEE IF IT WORKED
#   budget $70.0 -> 5.56 h per container
#   spawned Avibactam fc-01M64WQDC98M5H9BM60Q3KWKBM
#   spawned BTL-004 fc-...
#   spawned BTL-007 fc-...
#   spawned BTL-023 fc-...
#   spawned Clavulanic_acid fc-...
#   spawned Sulbactam fc-...
#   6 simulations spawned - safe to close PowerShell now
#
#   "App completed" afterwards is EXPECTED - that is the local entrypoint
#   finishing, not the simulations. Confirm with `modal app list`.
#
#   Then, in the container logs, each compound should print its atom count,
#   charge and protonation state. Expected at pH 7.4:
#     BTL-023          neutral             0
#     BTL-007          neutral             0
#     BTL-004          tetrazolate        -1
#     Avibactam        sulfate/sulfonate  -1
#     Clavulanic_acid  carboxylate        -1
#     Sulbactam        carboxylate        -1
#
# IF IT FAILS
#   App shows "stopped" shortly after launch
#       The spawn did not take. Check `modal app list` again after a minute;
#       spawned calls can take a few seconds to register as tasks.
#
#   One compound dies, the rest continue
#       They are independent containers. Re-run just that one by moving the
#       other five SDFs out of the ligands folder temporarily.
#
#   You disconnect and want to check progress later
#       python -m modal app list        (state and task count)
#       or open the app URL in a browser - it works with the PC switched off.
#
#   There is no checkpoint-resume wired into the entrypoint. A relaunch starts
#   from the beginning, which costs the few minutes of equilibration, not hours.
