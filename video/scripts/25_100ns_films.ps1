# =============================================================================
# 25 - Films from the 100 ns trajectories (BTL-004 and Avibactam)
# =============================================================================
# WHY THE CAPTIONS ARE PATCHED
#   SUB and NOTE in video_app.py are hard-coded to the 50 ns campaign. Left
#   alone, a 100 ns film is captioned "50 ns molecular dynamics" and carries
#   occupancy figures measured in a different run - a wrong number burnt into
#   a video that will be posted publicly. The patch is verified before the
#   file is written, so a silent failure cannot slip through.
#
#   Film length stays 20 s, so one second is now 5 ns instead of 2.5.
#
# OUTPUT     Downloads\TEM1_100ns_BTL-004_20s.mp4
#            Downloads\TEM1_100ns_Avibactam_20s.mp4
# COST/TIME  ~$0.40, about 10 minutes
# =============================================================================
$vdir = "$env:USERPROFILE\Downloads\tem1_video"
$dl   = "$env:USERPROFILE\Downloads"
New-Item -ItemType Directory -Force -Path $vdir | Out-Null
$raw = "https://raw.githubusercontent.com/Laurencejaboro19/" +
       "Molecular-docking-and-molecular-dynamics-code/main/video/modal/video_app.py"
Invoke-WebRequest -Uri "$raw`?cb=$(Get-Random)" -OutFile "$vdir\video_app.py"
$v = Get-Content "$vdir\video_app.py" -Raw

$v = $v -replace 'SUB = "50 ns molecular dynamics[^"]*"',
                 'SUB = "100 ns molecular dynamics - TEM-1 beta-lactamase (1BTL)"'
$v = $v -replace '(?s)NOTE = \{.*?\n\}',
@'
NOTE = {
 "BTL-004":   "100 ns trajectory, independent run",
 "Avibactam": "clinical inhibitor - reference, 100 ns",
}
'@
if ($v -notmatch '100 ns molecular dynamics') { Write-Error "subtitle patch failed"; return }
if ($v -notmatch '100 ns trajectory')         { Write-Error "caption patch failed";  return }
$v | Set-Content -Encoding UTF8 "$vdir\video_app.py"
Write-Host "video app captioned for 100 ns" -ForegroundColor Green

modal deploy "$vdir\video_app.py"

@'
import modal
f = modal.Function.from_name("tem1-video", "film")
for n in ["BTL-004", "Avibactam"]:
    print("spawned", n, f.spawn(n, "prod100", 20).object_id)
print("\nTwo 20 s films queued from the 100 ns trajectories.")
'@ | Set-Content -Encoding UTF8 "$vdir\launch_100ns_films.py"
python "$vdir\launch_100ns_films.py"
modal app list

Write-Host "`nWhen prod100_video holds both folders, fetch with:" -ForegroundColor Cyan
Write-Host @"
  modal run "`$env:USERPROFILE\Downloads\tem1_video\video_app.py::fetch" --tag prod100 --outdir "`$env:USERPROFILE\Downloads\tem1_video"
  tar -xzf "`$env:USERPROFILE\Downloads\tem1_video\tem1_videos.tar.gz" -C "`$env:USERPROFILE\Downloads\tem1_video"
  foreach (`$f in Get-ChildItem "`$env:USERPROFILE\Downloads\tem1_video\*.mp4") {
    Copy-Item `$f.FullName (Join-Path "`$env:USERPROFILE\Downloads" ("TEM1_100ns_" + `$f.BaseName + "_20s.mp4")) -Force
  }
"@
