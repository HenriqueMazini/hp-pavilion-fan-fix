# Medições — HP Pavilion 15-eh3xxx (board 8BC7)

Todas as medições foram feitas em 10–11/ago/2026, Ubuntu 26.04, kernel 7.0.0-29-generic,
BIOS F.05, **com a tampa inferior removida** (ver ressalva no final).

Sensor de referência: `k10temp` / **Tctl** — o sensor do die da CPU.
Carga: laço de inteiros (`while :; do :; done`), um processo por thread.

---

## 1. Estado inicial — a ventoinha não girava

| Condição | Ventoinha |
|---|---|
| Ubuntu ocioso, `pwm1_enable=2` (AUTO) | parada |
| Ubuntu sob carga de containers Docker | parada → **desligamento térmico** |
| Dentro do BIOS/UEFI setup, `Fan Always On = Enabled` | parada |
| Após reset de CMOS (erro 502) e reconfiguração | parada |

`fan1_input` e `fan2_input` = 0 em todos os casos.

## 2. O comando de máximo destravou o acionamento

```
echo 1 > pwm1_enable   ->  exit=1, modo inalterado   (EOPNOTSUPP, esperado)
echo 0 > pwm1_enable   ->  exit=0, ventoinha GIROU
```

A escrita de `1` falhando é o **controle do experimento**: confirma que o kernel em
execução corresponde ao código-fonte analisado, já que `hp_wmi_hwmon_write()` retorna
`-EOPNOTSUPP` para `PWM_MODE_MANUAL` fora dos Victus S, **antes** de tocar em `priv->mode`.

## 3. Carga com o fan em AUTOMÁTICO

| Threads | Teto de CPU | Resultado |
|---:|---|---|
| 8 | 2,5 GHz | equilíbrio em **70,6 °C** aos 180 s (curva achatada) |
| 16 | 2,5 GHz | **77,2 °C** aos 120 s, ainda subindo lentamente |
| 16 | 3,5 GHz | **88,1 °C em 42 s** → aborto automático |

Sem throttling térmico nos dois primeiros casos: `cpu0` ficou em 2495 MHz o tempo todo.

## 4. Calorimetria — AUTOMÁTICO vs MÁXIMO

Carga idêntica: 16 threads, teto de 3,5 GHz, mesmo ponto de partida (~46 °C).

| Instante | AUTO | MAX | Δ |
|---|---:|---:|---:|
| t+3 s | 75,1 °C | 64,0 °C | **11,1 °C** |
| t+9 s | 79,0 °C | 68,6 °C | 10,4 °C |
| t+24 s | 82,0 °C | 73,1 °C | 8,9 °C |
| t+42 s | **88,1 °C** (abortou) | **79,8 °C** | **8,3 °C** |
| tempo até 88 °C | 42 s | 78 s | **1,9×** |

**Conclusão:** o EC deixa de usar 8–11 °C de reserva de refrigeração. A dissipação
mecânica (aletas, pasta térmica, heat pipe) **não** é o gargalo — em modo máximo a
mesma carga leva quase o dobro do tempo para chegar ao mesmo ponto.

## 5. Defasagem entre sensores

Amostra do estágio de 16 threads @ 2,5 GHz:

| t | Tctl (k10temp) | amdgpu | acpitz |
|---:|---:|---:|---:|
| 0 s | 45,8 | 44 | 45 |
| 60 s | 70,0 | 63 | 67 |
| 120 s | 77,2 | 68 | 74 |

O `acpitz` é um sensor de placa: atrasa e se move em degraus grosseiros. O `amdgpu`
fica ~9 °C abaixo do Tctl sob carga de CPU.

**Consequência prática:** a extensão GNOME **Vitals mostra a média de todos os sensores
por padrão**. No pico em que o Tctl marcava 70,6 °C, o Vitals exibia **58 °C** — uma
subestimação de ~12 °C. Configure para exibir o máximo, ou fixe o `k10temp`.

---

## 6. Validação final — tampa fechada, com o `hp-fan-curve` no comando

Máquina fechada e parafusada, após reboot, com o serviço instalado decidindo sozinho
(sem forçar modo em momento algum). Limiares: sobe em 68 °C, desce em 58 °C.

| Carga | Tampa aberta, sem serviço | Tampa fechada, com serviço |
|---|---|---|
| 16 threads @ 2,5 GHz | 77,2 °C aos 120 s, **ainda subindo** | **73,4 °C** aos 240 s, estabilizado |
| 16 threads @ 3,5 GHz | **88,1 °C aos 42 s → aborto** | pico 85,4 °C, **desceu** para 78,9 °C |
| 16 threads sem limite | nunca testado | pico 78,2 °C aos 60 s, **desceu** para 74,5 °C |

O caso de 3,5 GHz é o mais eloquente: a mesma carga que antes disparava o aborto em
42 segundos agora sobe, a refrigeração **alcança e vence**, e a temperatura volta a cair.

O serviço chaveou nos três estágios, sempre logo após cruzar o limiar:

```
Estágio 1  t+99s  a 68,4 °C  ->  MÁXIMO
Estágio 2  t+6s   a 69,8 °C  ->  MÁXIMO
Estágio 3  t+9s   a 69,1 °C  ->  MÁXIMO
```

### Duas observações contraintuitivas

**Remover o teto de frequência esfriou a máquina.** Sem limite (pico 78,2 °C) ficou mais
frio do que com teto de 3,5 GHz (pico 85,4 °C). Com `scaling_max_freq` no máximo do
hardware, o `amd-pstate-epp` usa as próprias heurísticas de boost e potência e acabou
rodando all-core mais baixo (2582–2969 MHz) do que quando fixado em 3,5 GHz
(3069–3169 MHz). Fixar um teto intermediário atrapalhou o governor.

**O teto de frequência quase não importa em carga total.** Em all-core o 7730U fica
limitado por potência a ~2,6–3,0 GHz independentemente do valor de `scaling_max_freq`.
O teto só afeta picos de 1–2 threads, ou seja, a responsividade interativa.

### Temperatura de repouso

Com a tampa fechada e a ventoinha operante: **39,9 °C** — abaixo dos 44–46 °C medidos
com a tampa aberta.

---

## Nota sobre a tampa aberta

As medições das seções 1 a 5 foram feitas com a **tampa inferior removida**. Sem a tampa
a admissão de ar fica desobstruída e a placa dissipa por convecção direta. As medições da
seção 6, com a máquina fechada, são as que valem para uso real — e saíram melhores.
