# =============================================================================
# 15 - 100 ns production runs  (BTL-004 and Avibactam)
# =============================================================================
# WHAT IT DOES
#   Re-derives the budget ceiling for two LONG containers instead of six short
#   ones, adds the seed argument if the local copy predates it, deploys, then
#   spawns two 100 ns runs under tag "prod100".
#
# WHY THE BUDGET LINE MATTERS
#   MAX_SECONDS is derived from BUDGET_USD / (rate x N_SYSTEMS). Left at the
#   production values (70 / 6) after a replicate run had set it to 40 / 12, the
#   ceiling is 1.59 h per container - and a 100 ns run needs about 2.8 h. The
#   run would not crash; the chunked production loop would stop itself early
#   and silently hand back ~55 ns. 13.0 / (2.10 x 2) gives 3.10 h, with margin.
#
# WHY spawn AND NOT `modal run --detach`
#   Modal prints: "running a local entrypoint in detached mode only keeps the
#   last triggered Modal function alive". That is not a theoretical warning -
#   the analysis step was lost to exactly this (see script 16). Spawning
#   against a DEPLOYED app has no client to lose.
#
# COST / TIME     2 x 2.8 h x $2.10 = ~$11.80, about 2 h 45 m wall clock
# =============================================================================
$dir = "$env:USERPROFILE\Downloads\tem1_md"
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$raw = "https://raw.githubusercontent.com/Laurencejaboro19/" +
       "Molecular-docking-and-molecular-dynamics-code/main/md/modal/md_app.py"
Invoke-WebRequest -Uri "$raw`?cb=$(Get-Random)" -OutFile "$dir\md_app.py"
$t = Get-Content "$dir\md_app.py" -Raw

$t = $t -replace 'BUDGET_USD = [\d.]+', 'BUDGET_USD = 13.0'
$t = $t -replace 'N_SYSTEMS = \d+',     'N_SYSTEMS = 2'
foreach ($p in @('BUDGET_USD = 13.0','N_SYSTEMS = 2','seed: int = 0')) {
  if ($t -notmatch [regex]::Escape($p)) { Write-Error "patch failed: $p"; return }
}
$t | Set-Content -Encoding UTF8 "$dir\md_app.py"
Write-Host "ceiling 3.1 h per container - enough for 100 ns" -ForegroundColor Green

modal deploy "$dir\md_app.py"

$pdb = Get-ChildItem "$env:USERPROFILE\Downloads" -Recurse -Filter "1BTL_clean.pdb" |
       Select-Object -First 1 -ExpandProperty FullName
$sdfdir = Get-ChildItem "$env:USERPROFILE\Downloads" -Recurse -Filter "BTL-004*.sdf" |
          Select-Object -First 1 -ExpandProperty DirectoryName
if (-not $pdb -or -not $sdfdir) { Write-Error "receptor or SDF folder not found"; return }
Write-Host "receptor: $pdb`nligands : $sdfdir"

@'
import modal, os, sys
pdb_path, ligdir = sys.argv[1], sys.argv[2]
f = modal.Function.from_name("tem1-md", "simulate")
pdb_text = open(pdb_path).read()
want, found = ["BTL-004", "Avibactam"], {}
for fn in sorted(os.listdir(ligdir)):
    if fn.lower().endswith(".sdf"):
        n = os.path.splitext(fn)[0].replace("_mode1", "")
        if n in want:
            found[n] = open(os.path.join(ligdir, fn)).read()
missing = [w for w in want if w not in found]
if missing:
    sys.exit(f"missing SDF for {missing} in {ligdir} - not spending money")
for i, n in enumerate(want, 1):
    c = f.spawn(n, found[n], pdb_text, "prod100", 100.0, 1.1, 40000 + i)
    print(f"  {n:12s} 100 ns  seed {40000+i}  {c.object_id}")
print("\n2 runs queued on the deployed app. ~2 h 45 m. Est. $11.80.")
'@ | Set-Content -Encoding UTF8 "$dir\launch_100ns.py"

python "$dir\launch_100ns.py" "$pdb" "$sdfdir"
Write-Host "`nCheck TASKS is above 0 before closing this window:" -ForegroundColor Yellow
modal app list
