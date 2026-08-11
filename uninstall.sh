#!/bin/bash
# Remove completamente o hp-fan-curve.
set -e
[ "$(id -u)" -eq 0 ] || { echo "rode como root: sudo ./uninstall.sh"; exit 1; }

systemctl disable --now hp-fan-curve.service 2>/dev/null || true
rm -f /etc/systemd/system/hp-fan-curve.service /usr/local/sbin/hp-fan-curve
systemctl daemon-reload

# Devolve o controle ao EC.
for h in /sys/class/hwmon/hwmon*; do
  if [ "$(cat "$h/name" 2>/dev/null)" = "hp" ]; then
    echo 2 > "$h/pwm1_enable" 2>/dev/null && echo "fan devolvido ao modo AUTOMATICO (pwm1_enable=2)"
  fi
done

echo "removido."
