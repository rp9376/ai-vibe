# Shared interactive-shell setup for the bubble. Agents add their own files here via agents/<name>/rootfs/.
vibe-info() {
  echo "project:   ${VIBE_PROJECT:-?}"
  echo "workspace: ${VIBE_WORKSPACE:-?}"
  echo "network:   ${VIBE_NET:-?}${HTTPS_PROXY:+ (via $HTTPS_PROXY)}"
  cat /opt/vibe/build-info 2>/dev/null
}
