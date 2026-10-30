# =============================================================================
# 23 - Six 20 second films via a DEPLOYED app  (PREFERRED)
# =============================================================================
# WHAT IT DOES
#   `modal deploy` registers tem1-video permanently, the way pdfa-tnf-vhh and
#   pdfa-egfr-dual are registered. launch.py then spawns six film() calls
#   against that deployed function.
#
# WHY THIS IS THE RIGHT ONE
#   A deployed app has no client holding it open, so there is no parent
#   process whose death could take the queued calls with it. Closing
#   PowerShell, losing the data connection or shutting the laptop down changes
#   nothing - the containers keep rendering and the mp4s land in the volume.
#
# DO NOT RUN THIS WHILE SCRIPT 22 IS STILL GOING
#   Both write frames to /cache/<tag>_video/<compound>/fr/ and stitch deletes
#   every frame in that folder once it has encoded. Two batches racing means
#   one pulls the frames out from under the other and some compounds fail the
#   "frames missing" assertion. If both are somehow running:
#       modal app stop <ephemeral app id>
#   and let the deployed one finish alone.
#
# TIME / COST    ~10-12 min for all six, roughly $1
# =============================================================================
$dir = "$env:USERPROFILE\Downloads\tem1_video"
modal deploy "$dir\video_app.py"

@'
import modal
f = modal.Function.from_name("tem1-video", "film")
for n in ["BTL-004", "BTL-023", "BTL-007",
          "Avibactam", "Sulbactam", "Clavulanic_acid"]:
    print("spawned", n, f.spawn(n, "prod", 20).object_id)
print("\nDeployed app - these run to completion regardless of this PC.")
'@ | Set-Content -Encoding UTF8 "$dir\launch.py"

python "$dir\launch.py"
modal app list
