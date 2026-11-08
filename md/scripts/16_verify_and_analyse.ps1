# =============================================================================
# 16 - Confirm the runs reached full length, then analyse
# =============================================================================
# VERIFY FIRST
#   A budget stop is silent: prod.csv exists either way, and the only way to
#   tell a complete run from a truncated one is the last timestamp. A 100 ns
#   production run on top of 1.1 ns equilibration should end at ~101,100 ps.
#   ~55,000 ps means the ceiling in script 15 was still set for short runs.
#
# THEN ANALYSE - BY SPAWN, NOT --detach
#   `modal run --detach ::run_analysis` was tried and LOST. The connection
#   dropped mid-run with "getaddrinfo failed", the ephemeral app went with it,
#   and prod100_report was never written - fetch_report returned a 45-byte
#   empty tarball. Spawning `analyse` against the deployed app survives.
#
# COST      CPU only, pennies. 30-45 min for 2 systems x 10,000 frames.
# =============================================================================
$dir = "$env:USERPROFILE\Downloads\tem1_md"
New-Item -ItemType Directory -Force -Path $dir | Out-Null

foreach ($n in "BTL-004","Avibactam") {
  modal volume get tem1-md "prod100/$n/prod.csv" "$dir\$n`_prod.csv" --force 2>$null
  $last = Get-Content "$dir\$n`_prod.csv" | Select-Object -Last 1
  $ps = ($last -split ',')[1]
  "{0,-12} last frame: {1} ps = {2} ns" -f $n, $ps, [math]::Round([double]$ps/1000,1)
}
Write-Host "`nBoth should read ~101.1 ns. Ctrl+C now if either is short." -ForegroundColor Yellow
Start-Sleep -Seconds 10

@'
import modal
c = modal.Function.from_name("tem1-md", "analyse").spawn("prod100")
print("analysis spawned:", c.object_id)
print("Server-side on the deployed app. Safe to close PowerShell.")
'@ | Set-Content -Encoding UTF8 "$dir\launch_analysis.py"
python "$dir\launch_analysis.py"
modal app list

Write-Host "`nWhen done, prod100_report should hold figures, data and tables:" -ForegroundColor Cyan
Write-Host "  modal volume ls tem1-md prod100_report"
