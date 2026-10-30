# =============================================================================
# 21 - Pull whatever films exist down and open the folder
# =============================================================================
# WHAT IT DOES
#   Calls pack_videos on the volume, which tars every finished .mp4, writes it
#   to Downloads\tem1_video, extracts it and opens the folder.
#
# WHEN TO RUN IT
#   After the preview (one file), or after a full run (six files). Running it
#   early is harmless - you simply get the films that have stitched so far.
#
# WHAT TO LOOK FOR IN THE PREVIEW
#   framing of the pocket, legibility of the residue labels, whether 55 degrees
#   of spin reads well, and whether the HUD bars cover anything important.
# =============================================================================
$dir = "$env:USERPROFILE\Downloads\tem1_video"
modal run "$dir\video_app.py::fetch" --outdir "$dir"
tar -xzf "$dir\tem1_videos.tar.gz" -C "$dir"
Remove-Item "$dir\tem1_videos.tar.gz" -ErrorAction SilentlyContinue
$mp4 = Get-ChildItem "$dir\*.mp4"
$mp4 | Select-Object Name, @{n='MB';e={[math]::Round($_.Length/1MB,1)}} |
    Format-Table -AutoSize
Write-Host "`n$($mp4.Count) film(s) present" -ForegroundColor Cyan
Start-Process $dir
