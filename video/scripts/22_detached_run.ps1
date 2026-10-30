# =============================================================================
# 22 - Six 20 second films via a detached ephemeral app  (SECOND CHOICE)
# =============================================================================
# Prefer 23_deploy_and_launch.ps1. This script is kept because it is what the
# first successful full run used, and because the failure it documents is
# worth keeping.
#
# THE FAILURE THIS FIXES
#   `modal run` without --detach creates an EPHEMERAL app that is stopped the
#   instant the local entrypoint returns. Function.spawn() queues the call
#   against that app, so when the app dies the queued calls die with it. The
#   first attempt looked successful - six "spawned" lines, no errors - and
#   `modal app list` then showed:
#
#     ap-dzcYLQNB62Cgw5OdzAKcSr  tem1-video  stopped  0 tasks
#
#   created and stopped in the same minute, nothing rendered. ALWAYS verify
#   with `modal app list` before walking away.
#
# REMAINING CAVEAT
#   Modal prints: "running a local entrypoint in detached mode only keeps the
#   last triggered Modal function alive after the parent process has been
#   killed or disconnected." Read literally, only the sixth spawn is
#   guaranteed to survive. In practice all 58 tasks kept running, but that is
#   an observation, not a guarantee - which is why script 23 exists.
#
# EXPECTED OUTPUT OF THE VERIFY STEP
#   tem1-video   ephemeral (detached)   52     (tasks well above zero)
# =============================================================================
$dir = "$env:USERPROFILE\Downloads\tem1_video"
modal run --detach "$dir\video_app.py::render_all" --tag prod --seconds 20
Write-Host "`nVerify TASKS is above zero before closing this window:" -ForegroundColor Yellow
modal app list
