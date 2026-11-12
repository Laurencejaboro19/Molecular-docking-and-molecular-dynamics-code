# 18_replicate_50ns.ps1 - second independent 50 ns replicate of all six systems.
#
# This is the script that produced tag prod_r2. Run 12_production.ps1 produced
# prod; everything here is identical except the random seed, so the two runs are
# independent samples of the same ensemble rather than two copies of one
# trajectory.
#
# Three things differ from 12_production.ps1 and all three are deliberate:
#
#   1. Seeds. simulate() takes a seed that is applied to BOTH the Langevin
#      integrator and the initial velocity assignment. seed=0 is the original
#      unseeded behaviour, so prod is reproducible as it was. prod_r2 uses
#      20001-20006, one per compound.
#
#   2. Deployed app, not `modal run --detach`. --detach keeps the app alive but
#      Modal only guarantees the LAST triggered function survives; it is what
#      lost the 100 ns analysis. A deployed app has no client to disconnect
#      from. Deploy once, then .spawn() against it.
#
#   3. MAX_SECONDS set directly instead of derived from BUDGET_USD. The derived
#      form reads like a spend cap and is not one - Modal never sees that
#      number. It only sets the per-container timeout. Setting it too low does
#      not save money, it truncates the run and you pay for the truncated part.
#
# Inputs are the SAME ones run 12 used: Downloads\tem1_md\receptor.pdb and
# Downloads\tem1_md\ligands. Verified identical by MD5 - see
# 21_verify_receptor_provenance.ps1.
#
# Cost: 6 containers x ~1.3 h x $2.10 = ~$16.40. Wall clock ~1 h 20 m, all
# parallel. Safe to close PowerShell and go offline once TASKS reads 6.

$dir = "$env:USERPROFILE\Downloads\tem1_md"
Set-Location $dir
$env:PYTHONUTF8 = "1"
$env:PYTHONIOENCODING = "utf-8"

# ---- pre-flight: never spawn a container that will die on a missing file ----
Write-Host "`n== pre-flight ==" -ForegroundColor Cyan
if (-not (Test-Path "$dir\receptor.pdb")) { Write-Error "receptor.pdb missing"; return }
$sdf = Get-ChildItem "$dir\ligands\*.sdf" -EA SilentlyContinue
"receptor.pdb  {0:N0} bytes" -f (Get-Item "$dir\receptor.pdb").Length
$sdf | ForEach-Object { "  {0,-28} {1,8:N0} bytes" -f $_.Name, $_.Length }
if ($sdf.Count -ne 6) { Write-Error "expected 6 ligand SDFs, found $($sdf.Count)"; return }

# ---- fetch the app and set the timeout directly ----
$raw = "https://raw.githubusercontent.com/Laurencejaboro19/" +
       "Molecular-docking-and-molecular-dynamics-code/main/md/modal/md_app.py"
Invoke-WebRequest -Uri "$raw`?cb=$(Get-Random)" -OutFile "$dir\md_app.py"

$t = Get-Content "$dir\md_app.py" -Raw
if ($t -notmatch 'seed: int = 0') { Write-Error "repo copy lacks the seed parameter"; return }
# 3.5 h per container. A 50 ns run needs ~1.3 h; production steps in 1 ns chunks
# and stops itself 10 min before the timeout, so nothing is lost.
$t = $t -replace 'MAX_SECONDS = int\([^\)]*\)[^\r\n]*', 'MAX_SECONDS = 12600   # 3.5 h per container'
if ($t -notmatch 'MAX_SECONDS = 12600') { Write-Error "timeout patch failed"; return }
$t | Set-Content -Encoding UTF8 "$dir\md_app.py"
Select-String -Path "$dir\md_app.py" -Pattern "MAX_SECONDS ="

python -m modal deploy "$dir\md_app.py"

# ---- spawn one container per compound against the DEPLOYED app ----
@'
import modal, os, sys
ligdir, pdb_path = sys.argv[1], sys.argv[2]
f = modal.Function.from_name("tem1-md", "simulate")
pdb_text = open(pdb_path).read()
ligs = {os.path.splitext(fn)[0].replace("_mode1", ""):
        open(os.path.join(ligdir, fn)).read()
        for fn in sorted(os.listdir(ligdir)) if fn.lower().endswith(".sdf")}
if len(ligs) != 6:
    sys.exit(f"expected 6 SDFs, found {len(ligs)} - not spending money")

for i, n in enumerate(sorted(ligs), 1):
    seed = 20000 + i
    c = f.spawn(n, ligs[n], pdb_text, "prod_r2", 50.0, 1.1, seed)
    print(f"  prod_r2  {n:18s} 50 ns  seed {seed}  {c.object_id}")
print("\n6 replicate runs queued.  ~7.8 GPU-h  est. $16.40  wall clock ~1 h 20 m")
'@ | Set-Content -Encoding UTF8 "$dir\launch_replicate.py"

python "$dir\launch_replicate.py" "$dir\ligands" "$dir\receptor.pdb"

Write-Host "`nTASKS must read 6 before you walk away:" -ForegroundColor Yellow
python -m modal app list
