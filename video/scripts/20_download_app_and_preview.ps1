# =============================================================================
# 20 - Fetch the render app and make a 3 second test clip
# =============================================================================
# WHAT IT DOES
#   Downloads video/modal/video_app.py from this repo into
#   %USERPROFILE%\Downloads\tem1_video, then renders a 3 second BTL-004 clip
#   so the framing, labels and camera spin can be judged before paying to
#   render six 20 second films.
#
# WHY A CACHE BUSTER
#   raw.githubusercontent.com serves a stale copy for several minutes after a
#   push, and a Cache-Control header does not defeat it. The random query
#   string does. The grep afterwards is a version check - if the downloaded
#   file predates the max_threads fix it is the stale copy, and rendering with
#   it would be ten times slower for no visible reason.
#
# EXPECTED OUTPUT
#   "[BTL-004] pocket residues verified"
#   "[BTL-004] 72 frames from 5000, 4093 atoms"
#   eight shard lines reporting roughly 2.2 s/frame
#   a dict ending {'compound': 'BTL-004', 'MB': 3.3, ...}
#
# TIME         ~5 min on a cold image build, ~2 min afterwards
# =============================================================================
$dir = "$env:USERPROFILE\Downloads\tem1_video"
New-Item -ItemType Directory -Force -Path $dir | Out-Null

$raw = "https://raw.githubusercontent.com/Laurencejaboro19/" +
       "Molecular-docking-and-molecular-dynamics-code/main/video/modal/video_app.py"
Invoke-WebRequest -Uri "$raw`?cb=$(Get-Random)" -OutFile "$dir\video_app.py"

if (-not (Select-String -Path "$dir\video_app.py" -Pattern 'max_threads' -Quiet)) {
    Write-Error "stale copy downloaded - wait a minute and run this block again"
    return
}
Write-Host "app downloaded and version-checked" -ForegroundColor Green

modal run "$dir\video_app.py::preview" --name BTL-004
