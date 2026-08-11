#!/bin/bash
# ============================================================================
# TESTE 3 - CALORIMETRIA: quanto o EC esta subutilizando a ventoinha?
#
# Quando o tacometro morre, voce perde o instrumento que mediria a rotacao.
# A saida e usar a propria temperatura como instrumento: roda EXATAMENTE a
# mesma carga duas vezes, mudando so o modo do fan, e compara.
#
# Uso:  sudo ./calorimetria.sh [--threads N] [--freq KHZ|max] [--dur SEG]
#
# A diferenca de pico entre AUTO e MAX e a medida direta da reserva de
# refrigeracao que o EC deixa de usar.
# ============================================================================
cd "$(dirname "$(readlink -f "$0")")"
ARGS=("$@")

pico_de() {  # $1 = modo
  local saida
  saida=$(./carga.sh --modo "$1" "${ARGS[@]}" 2>&1)
  echo "$saida" >&2
  echo "$saida" | grep -oP 'PICO DE Tctl\s+:\s+\K[0-9.]+' | tail -1
}

echo "############ RODADA 1/2 - modo AUTOMATICO ############"
AUTO=$(pico_de auto)
echo
echo "############ esfriando entre as rodadas ############"
sleep 30
echo
echo "############ RODADA 2/2 - modo MAXIMO ############"
MAX=$(pico_de max)

echo
echo "==========================================================="
echo "                     CALORIMETRIA"
echo "==========================================================="
printf "  pico em AUTOMATICO : %s C\n" "${AUTO:-?}"
printf "  pico em MAXIMO     : %s C\n" "${MAX:-?}"
if [ -n "$AUTO" ] && [ -n "$MAX" ]; then
  awk -v a="$AUTO" -v b="$MAX" 'BEGIN{
    d=a-b; printf "  diferenca          : %+.1f C\n\n", d;
    if (d >= 8)       print "  => O EC subutiliza MUITO a ventoinha.\n     Provavel causa: tacometro inoperante -> sem malha fechada.\n     Correcao: curva em espaco de usuario (hp-fan-curve) + reparo do tacometro.";
    else if (d >= 3)  print "  => Subutilizacao moderada, porem real.\n     A curva em espaco de usuario ajuda, mas parte do deficit e dissipacao.";
    else              print "  => Sem diferenca util: a ventoinha ja opera perto do maximo.\n     O gargalo NAO e o modo do fan -> aletas entupidas ou pasta termica seca.";
  }'
else
  echo "  (uma das rodadas nao completou; verifique a saida acima)"
fi
echo "==========================================================="
echo "  Se as duas rodadas abortarem no limite, o pico fica igual ao limite"
echo "  e a comparacao perde sentido. Nesse caso compare o TEMPO ate o aborto"
echo "  na saida detalhada, ou baixe --freq / --threads."
echo "==========================================================="
