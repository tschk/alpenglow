# Alpenglow power management script
# Uses elogind + sysfs for suspend/hibernate
set -eu

case "${1:-}" in
  suspend|s)
    echo "→ Suspending..."
    loginctl suspend
    ;;
  hibernate|h)
    echo "→ Hibernating..."
    loginctl hibernate
    ;;
  hybrid|hy)
    echo "→ Hybrid sleep..."
    loginctl hybrid-sleep
    ;;
  status)
    cat /sys/class/power_supply/*/status 2>/dev/null || echo "No battery"
    cat /sys/class/power_supply/*/capacity 2>/dev/null || true
    ;;
  *)
    echo "Usage: $0 {suspend|hibernate|hybrid|status}"
    ;;
esac
