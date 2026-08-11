#!/bin/bash
# ============================================================================
# TESTE 2 - Teste termico sob carga, com travas de seguranca.
#
# Uso:
#   sudo ./carga.sh [--modo auto|max] [--threads N] [--freq KHZ|max]
#                   [--dur SEG] [--aborta C] [--esfria-ate C]
#
# Exemplos:
#   sudo ./carga.sh --modo auto --threads 8  --dur 180
#   sudo ./carga.sh --modo max  --threads 16 --freq 3500000 --dur 120
#   sudo ./carga.sh --modo auto --threads 16 --freq max --aborta 85
#
# TRAVAS (todas ativas sempre):
#   - aborta ao atingir a temperatura limite (padrao 88 C)
#   - trap EXIT/INT/TERM: mata a carga, RESTAURA o teto de frequencia original
#     e poe a ventoinha em MAXIMO. Vale para saida normal, Ctrl+C, erro e kill.
#   - espera esfriar antes de comecar, para as medicoes serem comparaveis
#   - teto rigido de duracao
#
# A carga e um laco de inteiros pura ("while :; do :; done"), deliberadamente
# mais branda que stress-ng: aquece de forma progressiva e previsivel.
# ============================================================================
cd "$(dirname "$(readlink -f "$0")")/.."
. lib/comum.sh

MODO=auto; THREADS=$(nproc); FREQ=""; DUR=180; ABORTA=88000; ESFRIA=50000
while [ $# -gt 0 ]; do
  case "$1" in
    --modo)        MODO=$2; shift 2;;
    --threads)     THREADS=$2; shift 2;;
    --freq)        FREQ=$2; shift 2;;
    --dur)         DUR=$2; shift 2;;
    --aborta)      ABORTA=$(( $2 * 1000 )); shift 2;;
    --esfria-ate)  ESFRIA=$(( $2 * 1000 )); shift 2;;
    -h|--help)     sed -n '2,30p' "$0"; exit 0;;
    *) echo "opcao desconhecida: $1"; exit 1;;
  esac
done

precisa_root
resolve_sensores || exit 1

ORIG_FREQ=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq)
HW_FREQ=$(cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq)
[ "$FREQ" = "max" ] && FREQ=$HW_FREQ
PIDS=(); MAXT=0; ABORTOU=""

cleanup() {
  echo
  echo "=================== ENCERRAMENTO SEGURO ==================="
  for p in "${PIDS[@]}"; do kill -9 "$p" 2>/dev/null; done
  wait 2>/dev/null
  set_freq_max "$ORIG_FREQ"
  echo 0 > "$HP/pwm1_enable" 2>/dev/null
  echo "  carga encerrada"
  echo "  teto de CPU restaurado : $(awk -v v=$ORIG_FREQ 'BEGIN{printf "%.2f GHz", v/1000000}')"
  echo "  ventoinha              : pwm1_enable=$(cat "$HP/pwm1_enable") (MAXIMO)"
  echo "  PICO DE Tctl           : $(c $MAXT) C"
  [ -n "$ABORTOU" ] && echo "  *** $ABORTOU ***"
  echo "==========================================================="
}
trap cleanup EXIT INT TERM

echo "=========================================================="
echo "  modo fan   : $MODO      threads : $THREADS"
echo "  teto freq  : $( [ -n "$FREQ" ] && awk -v v=$FREQ 'BEGIN{printf "%.2f GHz", v/1000000}' || echo "inalterado ($(awk -v v=$ORIG_FREQ 'BEGIN{printf "%.2f GHz", v/1000000}'))")"
echo "  duracao    : ${DUR}s    aborta em : $(c $ABORTA) C"
echo "=========================================================="

echo ">>> esfriando ate $(c $ESFRIA) C (ventoinha em MAXIMO)"
echo 0 > "$HP/pwm1_enable"
for ((i=0; i<480; i+=10)); do
  T=$(t_cpu); printf "    t+%-4ss  Tctl=%5s C\n" "$i" "$(c "$T")"
  [ "$T" -le "$ESFRIA" ] && break
  sleep 10
done
[ "$(t_cpu)" -gt "$ESFRIA" ] && { echo "  nao esfriou o suficiente; abortando para nao viciar a medicao"; exit 1; }

case "$MODO" in
  max)  echo 0 > "$HP/pwm1_enable";;
  auto) echo 2 > "$HP/pwm1_enable";;
  *) echo "modo invalido: $MODO"; exit 1;;
esac
echo ">>> fan em $MODO (pwm1_enable=$(cat "$HP/pwm1_enable")); assentando 20s"
sleep 20

[ -n "$FREQ" ] && set_freq_max "$FREQ"
echo
echo ">>> CARGA - $THREADS threads por ate ${DUR}s"
echo "    OBSERVE A VENTOINHA: ela acelera conforme a temperatura sobe?"
echo
for _ in $(seq 1 "$THREADS"); do ( while :; do :; done ) & PIDS+=($!); disown; done

for ((i=0; i<=DUR; i+=3)); do
  T=$(t_cpu); [ "$T" -gt "$MAXT" ] && MAXT=$T
  printf "    t+%-4ss  Tctl=%5s C  gpu=%5s C  acpitz=%5s C  cpu0=%sMHz\n" \
    "$i" "$(c "$T")" "$(c "$(t_gpu)")" "$(c "$(t_tz)")" "$(mhz)"
  if [ "$T" -ge "$ABORTA" ]; then
    ABORTOU="ABORTO em $(c "$T") C aos ${i}s"; echo; echo "!!! $ABORTOU"; exit 0
  fi
  sleep 3
done
echo
echo ">>> concluiu ${DUR}s sem atingir o limite. Pico: $(c $MAXT) C"
