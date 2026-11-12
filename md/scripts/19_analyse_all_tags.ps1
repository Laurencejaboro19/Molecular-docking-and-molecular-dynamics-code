# 19_analyse_all_tags.ps1 - progress check, then analysis of every tag.
#
# Two failure modes this avoids:
#
#   1. `modal` as a bare command. The modal.exe launcher fails with
#      "The directory name is invalid" whenever the shell's current directory
#      no longer exists - which happened when Downloads\tem1_md was deleted
#      while a PowerShell window was sitting in it. Windows cannot start any
#      process from a deleted working directory. `python -m modal` is used
#      everywhere below, and the script cd's somewhere that exists first.
#
#   2. `modal run --detach ::analyse`. That is what returned a 45-byte tarball
#      and a getaddrinfo failure. Spawning against the deployed app has no
#      client to lose.
#
# Re-analysing prod and prod100 is deliberate: both were first analysed with the
# row-counting occupancy bug (see PROTOCOL.md). Analysis is CPU only and costs
# pennies, so it is cheaper to re-run them than to hand-correct the tables.
#
# Analysis takes 30-45 min per tag; prod100 is slowest at 10,000 frames per
# system. Safe to close PowerShell once the function IDs print.

Set-Location $env:USERPROFILE
$env:PYTHONUTF8 = "1"

# ---- progress ----
foreach ($tag in @("prod", "prod100", "prod_r2")) {
  Write-Host "`n== $tag ==" -ForegroundColor Cyan
  foreach ($n in "Avibactam","BTL-004","BTL-007","BTL-023","Clavulanic_acid","Sulbactam") {
    $d = ""
    try { $d = (python -m modal volume ls tem1-md "$tag/$n" 2>&1 | Out-String) } catch { $d = "" }
    if ($null -eq $d) { $d = "" }
    if     ($d -match "prod\.csv")  { "  {0,-18} DONE"       -f $n }
    elseif ($d -match "traj\.dcd")  { "  {0,-18} simulating" -f $n }
    elseif ($d -match "start\.pdb") { "  {0,-18} building"   -f $n }
  }
}
Write-Host "`n== app ==" -ForegroundColor Cyan
python -m modal app list

# ---- analyse, server-side ----
Write-Host "`nSpawning analysis. Ctrl-C now if any tag above is still simulating." -ForegroundColor Yellow
$dir = "$env:USERPROFILE\Downloads\tem1_md"
New-Item -ItemType Directory -Force -Path $dir | Out-Null
@'
import modal
f = modal.Function.from_name("tem1-md", "analyse")
for tag in ["prod", "prod100", "prod_r2"]:
    print(f"{tag:10s} {f.spawn(tag).object_id}")
print("\nAll spawned server-side. Safe to close PowerShell.")
'@ | Set-Content -Encoding UTF8 "$dir\analyse_all.py"
python "$dir\analyse_all.py"
