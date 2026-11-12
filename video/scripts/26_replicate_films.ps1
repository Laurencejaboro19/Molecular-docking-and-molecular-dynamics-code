# 26_replicate_films.ps1 - 20 s films of the six prod_r2 replicate trajectories.
#
# Four things this script exists to get right:
#
#   1. The captions. video_app.py ships with NOTE entries carrying run-1
#      numbers, including "Ser130 H-bond held 64% of frames". That figure came
#      from the row-counting occupancy bug AND from the single run that behaved
#      differently from the other three. Burning it into a replicate film would
#      put a wrong number into pixels that cannot be corrected later. The patch
#      below replaces every caption with neutral text and the script REFUSES TO
#      RUN if either the patch fails or the old string survives.
#
#   2. The volume is tem1-md, not tem1-video. The app is named tem1-video but
#      it reads trajectories from and writes films to the tem1-md volume.
#      `modal volume ls tem1-video ...` returns "Volume not found".
#
#   3. One launch only. Running the launch block twice puts two sets of shards
#      on the same frame directory; stitch deletes each frame once it has
#      encoded it, so whichever finishes first pulls the frames out from under
#      the other and the loser fails a "frames missing" assertion. If you are
#      not sure whether you already launched, check TASKS before launching
#      again - do not just re-run.
#
#   4. Fetch only after TASKS reads 0. Fetching early returns a 0.0 MB tarball
#      and extracts nothing.
#
# ~12 min for all six, ~$1. Films are 1080x1920, 480 frames, exactly 20.000 s.

$vdir = "$env:USERPROFILE\Downloads\tem1_video"
New-Item -ItemType Directory -Force -Path $vdir | Out-Null
Set-Location $vdir
$env:PYTHONUTF8 = "1"

$raw = "https://raw.githubusercontent.com/Laurencejaboro19/" +
       "Molecular-docking-and-molecular-dynamics-code/main/video/modal/video_app.py"
Invoke-WebRequest -Uri "$raw`?cb=$(Get-Random)" -OutFile "$vdir\video_app.py"

$v = Get-Content "$vdir\video_app.py" -Raw
$v = $v -replace 'SUB = "[^"]*"',
                 'SUB = "50 ns molecular dynamics - TEM-1 beta-lactamase (1BTL)"'
$v = $v -replace '(?s)NOTE = \{.*?\n\}',
@'
NOTE = {
 "BTL-004":         "independent replicate, 50 ns",
 "BTL-023":         "independent replicate, 50 ns",
 "BTL-007":         "independent replicate, 50 ns",
 "Avibactam":       "clinical inhibitor - reference",
 "Sulbactam":       "clinical inhibitor - reference",
 "Clavulanic_acid": "clinical inhibitor - reference",
}
'@
if ($v -notmatch 'independent replicate') { Write-Error "caption patch failed - stop"; return }
if ($v -match '64% of frames')            { Write-Error "old occupancy caption survived - stop"; return }
$v | Set-Content -Encoding UTF8 "$vdir\video_app.py"

python -m modal deploy "$vdir\video_app.py"

@'
import modal
f = modal.Function.from_name("tem1-video", "film")
for n in ["Avibactam","BTL-004","BTL-007","BTL-023","Clavulanic_acid","Sulbactam"]:
    print("spawned", n, f.spawn(n, "prod_r2", 20).object_id)
print("\n6 films queued from the 50 ns replicates. ~12 min, ~$1.")
print("Do NOT run this block twice - see the header.")
'@ | Set-Content -Encoding UTF8 "$vdir\launch_r2.py"
python "$vdir\launch_r2.py"
python -m modal app list

Write-Host "`nWait until tem1-video shows TASKS 0, then:" -ForegroundColor Yellow
Write-Host '  python -m modal volume ls tem1-md "prod_r2_video/BTL-004"' -ForegroundColor Yellow
Write-Host "  then run the fetch block below." -ForegroundColor Yellow

<# ---------------- fetch, once TASKS reads 0 ----------------
$vdir = "$env:USERPROFILE\Downloads\tem1_video"
Set-Location $vdir
Remove-Item "$vdir\tem1_videos.tar.gz" -EA SilentlyContinue
python -m modal run "$vdir\video_app.py::fetch" --tag prod_r2 --outdir "$vdir"
if ((Get-Item "$vdir\tem1_videos.tar.gz").Length -lt 100000) {
  Write-Warning "tarball empty - films not finished, wait and retry"; return }
New-Item -ItemType Directory -Force -Path "$vdir\r2" | Out-Null
tar -xzf "$vdir\tem1_videos.tar.gz" -C "$vdir\r2"
Get-ChildItem "$vdir\r2" -Recurse -Filter *.mp4 | ForEach-Object {
  Copy-Item $_.FullName (Join-Path "$env:USERPROFILE\Downloads" ("TEM1_50ns_r2_" + $_.BaseName + "_20s.mp4")) -Force
}
Get-ChildItem "$env:USERPROFILE\Downloads\TEM1_50ns_r2_*.mp4" | Select-Object Name, Length
#>
