# Caixa-preta (opcional)

Desligamentos abruptos — corte do EC, queda de energia, falha de hardware — **não
deixam rastro no journal**: ele simplesmente para no meio. Este daemon grava uma linha
CSV a cada 5 s e faz `fsync` no arquivo, para que a última linha sobreviva a um corte
instantâneo.

O campo decisivo é **`ac_online`**:

| Comportamento antes do corte | Conclusão |
|---|---|
| `ac_online` cai para `0` | perda de alimentação externa (tomada, fonte, cabo) |
| `ac_online` fica em `1` até a última linha | o **EC ou o hardware** cortou a energia |
| `tctl` subindo forte na última linha | térmico (o resto do projeto trata disso) |

## Instalar

```bash
sudo install -m 0755 forense/hp-fan-forense /usr/local/sbin/hp-fan-forense
sudo install -m 0644 forense/hp-fan-forense.service /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now hp-fan-forense
```

## Ler depois de um evento

```bash
tail -20 /var/log/hp-fan-forense.csv     # os últimos ~100 s antes do corte
column -s, -t /var/log/hp-fan-forense.csv | tail -20
```

## Remover

```bash
sudo systemctl disable --now hp-fan-forense
sudo rm -f /etc/systemd/system/hp-fan-forense.service /usr/local/sbin/hp-fan-forense
```

Custo: ~1,7 MB de log por dia, rotacionado em 20 MB. Roda com `Nice=10` e
`IOSchedulingClass=idle`.
