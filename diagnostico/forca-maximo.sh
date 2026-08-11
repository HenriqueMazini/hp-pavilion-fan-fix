#!/bin/bash
# ============================================================================
# TESTE 1 - A ventoinha responde ao comando de MAXIMO?
#
# E o teste que separa "problema acima do EC" de "problema abaixo do EC".
# Faz DUAS escritas em pwm1_enable. Nenhuma escrita em registrador de EC.
#
#   escreve 1 (MANUAL) -> deve FALHAR com EOPNOTSUPP fora dos Victus S.
#                         Serve de controle: confirma que o kernel em execucao
#                         corresponde ao codigo esperado.
#   escreve 0 (MAXIMO) -> comando WMI 0x27, o unico jeito suportado de
#                         forcar a ventoinha neste hardware.
#
# Seguro: e a interface que a propria HP definiu, ja usada pelo driver no boot
# (com argumento 0, para entrar em AUTO). Empurra na direcao termicamente
# segura. Reversivel com `echo 2`, e o firmware reverte sozinho em 120s.
# ============================================================================
cd "$(dirname "$(readlink -f "$0")")/.."
. lib/comum.sh
precisa_root
resolve_sensores || exit 1

INICIO=$(date '+%Y-%m-%d %H:%M:%S')
echo "=== $INICIO  |  hp=$HP  cpu=$CPU"
echo
echo "--- BASELINE ---"
echo "  pwm1_enable = $(cat "$HP/pwm1_enable")"
echo "  fan1=$(cat "$HP/fan1_input" 2>/dev/null)  fan2=$(cat "$HP/fan2_input" 2>/dev/null)"
echo "  Tctl = $(c "$(t_cpu)") C"

echo
echo "--- CONTROLE: escrever 1 (MANUAL). Esperado: falhar. ---"
echo 1 > "$HP/pwm1_enable" 2>&1
echo "  exit=$?   pwm1_enable = $(cat "$HP/pwm1_enable")"

echo
echo "--- TESTE: escrever 0 (MAXIMO, WMI 0x27) ---"
echo 0 > "$HP/pwm1_enable" 2>&1; RC=$?
echo "  exit=$RC  pwm1_enable = $(cat "$HP/pwm1_enable")"
[ $RC -ne 0 ] && echo "  >>> A BIOS REJEITOU o comando: suspeite de firmware."

echo
echo "--- MONITORAMENTO 30s ---"
for i in $(seq 0 2 30); do
  printf "  t+%-3ss  fan1=%-6s Tctl=%5s C\n" "$i" "$(cat "$HP/fan1_input" 2>/dev/null)" "$(c "$(t_cpu)")"
  sleep 2
done

echo
journalctl -k --since "$INICIO" --no-pager 2>/dev/null | grep -iE 'hp_wmi|ACPI Error' | tail -10
echo
cat <<'EOF'
COMO LER O RESULTADO
  exit=0 e a ventoinha GIRA     -> o caminho todo funciona; investigue por que
                                   o modo AUTOMATICO nao a aciona.
  exit=0 e a ventoinha NAO gira -> falha abaixo do EC: alimentacao, MOSFET,
                                   conector ou a propria ventoinha.
  exit!=0                       -> a BIOS rejeita o controle: firmware.

ATENCAO: com o tacometro inoperante, fan1_input fica 0 mesmo com a ventoinha
girando. Confirme VISUALMENTE ou com uma tira de papel - nao pelo numero.
EOF
