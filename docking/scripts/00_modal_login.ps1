# =============================================================================
# BLOCK 0 - LOG IN TO MODAL (once per PC)
# =============================================================================
# Opens a browser tab. Approve it, and the token is saved and reused.
# =============================================================================

python -m modal setup
# older CLI versions use:  python -m modal token new

python -m modal profile current

# WHAT YOU SHOULD SEE
#   A browser tab opens, you approve, the terminal prints a confirmation,
#   then the active profile name.
