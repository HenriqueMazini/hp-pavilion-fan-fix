#!/bin/bash
# ============================================================================
# Coleta SOMENTE-LEITURA de tudo que importa para diagnosticar ventoinha
# em notebooks HP no Linux. Nao escreve nada, nao carrega modulos.
# Rode como usuario comum; algumas secoes pedem root e sao puladas sem ele.
# ============================================================================
cd "$(dirname "$(readlink -f "$0")")/.."
. lib/comum.sh

echo "===== 1. SISTEMA ====="
uname -a; grep PRETTY /etc/os-release

echo; echo "===== 2. DMI / BIOS ====="
for f in sys_vendor product_name product_sku board_name board_version \
         bios_vendor bios_version bios_date; do
  printf "  %-16s: %s\n" "$f" "$(cat /sys/class/dmi/id/$f 2>/dev/null)"
done
echo "  (board_name e o System Board ID usado pela HP para casar a BIOS correta)"

echo; echo "===== 3. HWMON (todos) ====="
for h in /sys/class/hwmon/hwmon*; do
  echo "--- $h  name=$(cat "$h/name" 2>/dev/null)  driver=$(readlink -f "$h/device/driver" 2>/dev/null | xargs -r basename)"
  ls -1 "$h/" | grep -vE '^(device|power|subsystem|uevent|of_node)$' | while read -r f; do
    printf "      %-22s = %s\n" "$f" "$(cat "$h/$f" 2>/dev/null || echo '<EIO>')"
  done
done

echo; echo "===== 4. INTERPRETACAO DO pwm1_enable (driver hp-wmi) ====="
cat <<'EOF'
  0 = MAXIMO      -> WMI 0x27 com valor 1; driver renova a cada 90s
                     (o firmware HP reverte sozinho apos 120s)
  1 = MANUAL      -> apenas Victus 16-r/16-s; em outros retorna EOPNOTSUPP
  2 = AUTOMATICO  -> devolve o controle ao EC (default do driver)

  A existencia de fan1_input/fan2_input JA PROVA que a consulta WMI 0x11
  respondeu com sucesso no probe: o driver so cria esses arquivos se
  hp_wmi_get_fan_speed() retornar >= 0. Logo, RPM 0 e o EC dizendo "zero",
  nao "nao sei".
EOF

echo; echo "===== 5. THERMAL ZONES / COOLING DEVICES ====="
for tz in /sys/class/thermal/thermal_zone*; do
  echo "--- $tz type=$(cat "$tz/type" 2>/dev/null) temp=$(cat "$tz/temp" 2>/dev/null)"
  for t in "$tz"/trip_point_*; do
    [ -e "$t" ] && printf "      %s = %s\n" "$(basename "$t")" "$(cat "$t" 2>/dev/null)"
  done
done
echo "--- cooling devices (procure por um do tipo 'Fan'; a ausencia indica"
echo "    que a ventoinha NAO e exposta via ACPI e e 100% gerida pelo EC):"
for cd in /sys/class/thermal/cooling_device*; do
  printf "    %-20s %s\n" "$(basename "$cd")" "$(cat "$cd/type" 2>/dev/null)"
done

echo; echo "===== 6. PLATFORM PROFILE ====="
cat /sys/firmware/acpi/platform_profile 2>/dev/null || echo "  (ausente em /sys/firmware/acpi)"
for p in /sys/class/platform-profile/platform-profile*; do
  [ -e "$p" ] && echo "  $p: name=$(cat "$p/name" 2>/dev/null) profile=$(cat "$p/profile" 2>/dev/null)"
done
echo "  Ausente e NORMAL em Pavilion: o hp-wmi so registra platform_profile"
echo "  para boards nas listas DMI Omen/Victus, ou se a WMI 0x4c responder."

echo; echo "===== 7. MODULOS / WMI ====="
lsmod | grep -iE 'hp_|wmi|k10temp|thermal|ec_sys' || echo "  (nada)"
echo "-- parametros do hp_wmi:"; grep -rs . /sys/module/hp_wmi/parameters/ || echo "   (nenhum)"
echo "-- dispositivos WMI:"
for d in /sys/bus/wmi/devices/*; do
  [ -e "$d" ] && printf "   %-40s inst=%-3s drv=%s\n" "$(basename "$d")" \
    "$(cat "$d/instance_count" 2>/dev/null)" \
    "$(readlink -f "$d/driver" 2>/dev/null | xargs -r basename)"
done

echo; echo "===== 8. LOG DO KERNEL (relevante) ====="
journalctl -k -b 0 --no-pager 2>/dev/null \
  | grep -iE 'hp_wmi|hp-wmi|hp_bioscfg|thermal|platform_profile|ACPI (Error|BIOS Error)|Firmware Bug|wmi_bus|EC:' \
  | head -60
echo "  (erros AE_AML_BUFFER_LIMIT em WQBZ/WQBE costumam ser do hp_bioscfg,"
echo "   enumerando settings da BIOS - NAO tem relacao com a ventoinha)"

echo; echo "===== 9. CPUFREQ ====="
echo "  driver=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver 2>/dev/null)"
echo "  governor=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)"
echo "  max=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq 2>/dev/null) de $(cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq 2>/dev/null)"
