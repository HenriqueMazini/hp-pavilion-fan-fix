#!/bin/bash
# Instala o hp-fan-curve como servico systemd.
set -e
cd "$(dirname "$(readlink -f "$0")")"

[ "$(id -u)" -eq 0 ] || { echo "rode como root: sudo ./install.sh"; exit 1; }

if ! grep -qs '^hp$' /sys/class/hwmon/hwmon*/name; then
  echo "AVISO: nenhum hwmon chamado 'hp' encontrado."
  echo "       O modulo hp_wmi esta carregado? (sudo modprobe hp_wmi)"
  echo "       Sem ele o servico nao tem o que controlar."
  read -rp "Instalar mesmo assim? [s/N] " r
  [ "$r" = "s" ] || exit 1
fi

install -m 0755 -o root -g root hp-fan-curve         /usr/local/sbin/hp-fan-curve
install -m 0644 -o root -g root hp-fan-curve.service /etc/systemd/system/hp-fan-curve.service
systemctl daemon-reload
systemctl enable --now hp-fan-curve.service

sleep 3
echo
systemctl status hp-fan-curve.service --no-pager -l | head -15
echo
echo "Pronto. Acompanhe com:  journalctl -u hp-fan-curve -f"
echo "Desinstalar com:        sudo ./uninstall.sh"
