#!/bin/bash
# Funcoes compartilhadas pelos scripts de diagnostico.
#
# IMPORTANTE: os indices /sys/class/hwmon/hwmonN NAO sao estaveis entre boots.
# Sempre resolva pelo campo 'name'. Este foi um dos erros que custaram tempo
# durante o diagnostico original.

acha_hwmon() {
  local alvo=$1 h
  for h in /sys/class/hwmon/hwmon*; do
    [ "$(cat "$h/name" 2>/dev/null)" = "$alvo" ] && { echo "$h"; return 0; }
  done
  return 1
}

# Resolve os sensores usados por todos os scripts. Falha cedo e com mensagem
# clara se o hwmon do hp-wmi nao existir.
resolve_sensores() {
  HP=$(acha_hwmon hp) || {
    echo "ERRO: hwmon 'hp' nao encontrado. O modulo hp_wmi esta carregado?" >&2
    echo "      Tente: sudo modprobe hp_wmi" >&2
    return 1
  }
  CPU=$(acha_hwmon k10temp) || {
    echo "ERRO: hwmon 'k10temp' nao encontrado (CPU AMD?)." >&2
    return 1
  }
  GPU=$(acha_hwmon amdgpu) || GPU=""
  TZ=$(acha_hwmon acpitz)  || TZ=""
  export HP CPU GPU TZ
}

# Temperaturas em milicelsius; 0 se o sensor nao existir.
t_cpu() { cat "$CPU/temp1_input" 2>/dev/null || echo 0; }
t_gpu() { [ -n "$GPU" ] && cat "$GPU/temp1_input" 2>/dev/null || echo 0; }
t_tz()  { [ -n "$TZ"  ] && cat "$TZ/temp1_input"  2>/dev/null || echo 0; }

# milicelsius -> string com uma casa decimal
c() { awk -v v="$1" 'BEGIN{printf "%.1f", v/1000}'; }

mhz() {
  awk '{printf "%d", $1/1000}' \
    /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null || echo 0
}

# Aplica o mesmo teto de frequencia a todos os nucleos.
set_freq_max() {
  local f
  for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq; do
    echo "$1" > "$f" 2>/dev/null
  done
}

precisa_root() {
  [ "$(id -u)" -eq 0 ] || {
    echo "ERRO: precisa rodar como root." >&2
    echo "      sudo $0 $*   (ou pkexec, se o sudo exigir tty)" >&2
    exit 1
  }
}
