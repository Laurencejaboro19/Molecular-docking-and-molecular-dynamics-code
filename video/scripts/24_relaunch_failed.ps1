# =============================================================================
# 24 - Re-render only the compounds that failed
# =============================================================================
# WHEN TO USE IT
#   Script 21 reports fewer than six films. The usual cause is two batches
#   having raced each other over the same frame directory (see script 23), so
#   one compound's stitch hit the "frames missing" assertion.
#
# HOW TO USE IT
#   Edit the list below to the compounds that are missing, then run. Needs the
#   app to already be deployed by script 23.
# =============================================================================
$dir = "$env:USERPROFILE\Downloads\tem1_video"
@'
import modal
f = modal.Function.from_name("tem1-video", "film")
for n in ["BTL-023", "Sulbactam"]:          # <- edit to the missing ones
    print("spawned", n, f.spawn(n, "prod", 20).object_id)
'@ | Set-Content -Encoding UTF8 "$dir\relaunch.py"
python "$dir\relaunch.py"
modal app list
