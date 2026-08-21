# Caixa-preta

Desligamentos abruptos — corte do EC, queda de energia, falta de memória, falha de
hardware — **não deixam rastro no journal**: ele simplesmente para no meio. Este daemon
grava uma linha CSV a cada 5 s e faz `fsync` no arquivo, para que a última linha
sobreviva a um corte instantâneo.

Vale instalar **mesmo com a ventoinha funcionando**: ele não toca no controle do fan,
custa ~4 min de CPU por dia, e é a diferença entre o próximo desligamento virar
informação ou virar mais um episódio sem explicação.

## O que cada campo responde

**Energia — o campo decisivo é `ac_online`:**

| Comportamento antes do corte | Conclusão |
|---|---|
| `ac_online` cai para `0` | perda de alimentação externa (tomada, fonte, cabo) |
| `ac_online` fica em `1` até a última linha | o **EC ou o hardware** cortou a energia |
| `tctl` subindo forte na última linha | térmico |

**Memória — a outra causa plausível de processo morto ou sistema travado:**

| Campo | O que é | Como ler |
|---|---|---|
| `mem_avail_mb` | `MemAvailable` do kernel | O número que de fato prediz falta de memória. **Não** use `MemFree`: ele ignora o cache reclamável e assusta à toa |
| `swap_used_mb` | swap em uso naquele instante | zram + arquivo somados |
| `pswpout` | páginas escritas em swap **desde o boot** | Contador acumulado. Um pico às 15h volta a zero em `swap_used_mb` e some; no `pswpout` fica |

A distinção entre os dois últimos importa: `swap_used_mb` é uma foto, `pswpout` é o
histórico. Para decidir se a máquina precisa de mais RAM, é o `pswpout` que responde —
se ele continuar em `0` depois de semanas de uso real, a memória sobra.

## Instalar

```bash
sudo install -m 0755 forense/hp-fan-forense /usr/local/sbin/hp-fan-forense
sudo install -m 0644 forense/hp-fan-forense.service /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now hp-fan-forense
```

Se o `sudo` exigir tty num contexto sem terminal, use `pkexec`.

## Ler depois de um evento

```bash
tail -20 /var/log/hp-fan-forense.csv     # os últimos ~100 s antes do corte
column -s, -t /var/log/hp-fan-forense.csv | tail -20
```

Pressão de memória ao longo do tempo:

```bash
# menor mem_avail e maior pswpout registrados
awk -F, 'NR>1 && $14!="" {if(m==""||$14<m)m=$14; if($16>p)p=$16}
         END{printf "mem_avail minimo: %s MB\npswpout maximo:   %s\n", m, p}' \
  /var/log/hp-fan-forense.csv
```

## Remover

```bash
sudo systemctl disable --now hp-fan-forense
sudo rm -f /etc/systemd/system/hp-fan-forense.service /usr/local/sbin/hp-fan-forense
```

## Custo

~1,4 MB de log por dia (87 bytes por linha, 17280 linhas), rotacionado em 20 MB (guarda um arquivo anterior em `.1`).
Roda com `Nice=10` e `IOSchedulingClass=idle`.

Usa **apenas builtins do bash** — o único fork por iteração é o `sync -d`, que sincroniza
só este arquivo. Medido em produção: **~3,7 min de CPU por dia**. A versão ingênua, com
`cat`/`awk`/`date` por campo, gastava ~52 min/dia e forkava ~260 mil processos.

## Mudança de esquema

Se uma versão nova do script acrescentar colunas, ele detecta o cabeçalho antigo no
arquivo e **rotaciona automaticamente** para `.1` antes de gravar. Dois esquemas
misturados no mesmo CSV quebrariam qualquer leitura posterior — justamente no arquivo
cuja única razão de existir é ser lido depois de um desastre.
