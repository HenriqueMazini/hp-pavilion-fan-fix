# hp-pavilion-fan-fix

Diagnóstico completo e correção para notebooks **HP Pavilion** cuja ventoinha não gira
sozinha no Linux — incluindo o caso em que ela **também não gira dentro do BIOS**, mesmo
com `Fan Always On = Enabled`.

O sintoma parece ser "o Linux não controla a ventoinha". Não é. Neste caso, o
**Embedded Controller (EC) subutiliza severamente a ventoinha** porque o **tacômetro não
reporta RPM** e ele perde a realimentação da malha de controle.

> **Resultado medido:** forçar o modo máximo pela interface oficial do `hp-wmi` recupera
> **8–11 °C** e quase **dobra** o tempo até a temperatura crítica sob a mesma carga.

---

## Índice

- [A quem isto serve](#a-quem-isto-serve)
- [Sintomas](#sintomas)
- [O diagnóstico, camada por camada](#o-diagnóstico-camada-por-camada)
- [A descoberta principal](#a-descoberta-principal)
- [A correção](#a-correção)
- [Instalação](#instalação)
- [Scripts de diagnóstico](#scripts-de-diagnóstico)
- [O que foi descartado, e por quê](#o-que-foi-descartado-e-por-quê)
- [Armadilhas que custaram tempo](#armadilhas-que-custaram-tempo)
- [Causa raiz ainda em aberto](#causa-raiz-ainda-em-aberto)
- [BIOS](#bios)
- [Segurança](#segurança)

---

## A quem isto serve

Sistema onde o diagnóstico foi feito:

| | |
|---|---|
| Modelo | HP Pavilion Laptop 15-eh3xxx |
| System Board ID | **8BC7** |
| CPU | AMD Ryzen 7 7730U |
| BIOS | F.05 (24/04/2024), AMI |
| SO | Ubuntu 26.04 LTS |
| Kernel | 7.0.0-29-generic |
| Driver | `hp-wmi` (`/sys/class/hwmon/hwmonN` com `name=hp`) |

Deve servir a qualquer HP que exponha `pwm1_enable` via `hp-wmi` e apresente os
mesmos sintomas. **Os scripts de diagnóstico são genéricos**; a correção depende
apenas de o `pwm1_enable` aceitar o valor `0`.

Não serve para: Omen, Victus 16-d e Victus 16-r/16-s. Esses têm caminhos próprios no
driver (perfis térmicos, e no caso do Victus S até `pwm1` proporcional) e provavelmente
não têm este problema.

## Sintomas

- Ventoinha completamente parada, mesmo sob carga pesada
- Notebook **desliga sozinho** por superaquecimento
- `sensors` mostra `fan1: 0 RPM` e `fan2: 0 RPM`
- **A ventoinha também não gira dentro do BIOS/UEFI**, com `Fan Always On = Enabled`
- Reset de CMOS/EC não resolve
- `fancontrol`, `pwmconfig` e NBFC não encontram nada para controlar

## O diagnóstico, camada por camada

A investigação percorreu a pilha de cima para baixo, eliminando uma camada por vez com
evidência, em vez de tentar soluções no escuro:

```
Ubuntu ............... OK
kernel 7.0 ........... OK
hp-wmi ............... OK   <- hwmon registrado, leitura e escrita funcionam
ACPI / WMI ........... OK   <- comando 0x27 executa, exit=0
BIOS ................. OK   <- não rejeita o comando
Embedded Controller .. FALHA <- aceita "máximo", mas sua política automática subutiliza
tacômetro ............ FALHA <- nunca reporta RPM  (causa raiz provável)
alimentação / motor .. OK   <- ventoinha gira quando comandada
```

Duas evidências fecharam o caso do lado do software:

**1. Os arquivos `fan1_input`/`fan2_input` existirem já é uma prova.**
No `drivers/platform/x86/hp/hp-wmi.c`, `hp_wmi_hwmon_is_visible()` só cria esses
atributos se a consulta WMI tiver sucesso:

```c
case hwmon_fan:
    if (hp_wmi_get_fan_speed(channel) >= 0)
        return 0444;
    break;
```

Ou seja: `0 RPM` é o EC **respondendo "zero"**, não "não sei". O canal de comunicação
está íntegro.

**2. A escrita de `1` falhar é o controle do experimento.**
`hp_wmi_hwmon_write()` retorna `-EOPNOTSUPP` para `PWM_MODE_MANUAL` fora dos Victus S
**antes** de alterar `priv->mode`. Ver esse erro exato confirma que o kernel em execução
corresponde ao código analisado — e que a leitura da semântica está certa.

### `pwm1_enable` no driver `hp-wmi`

```c
enum pwm_modes {
    PWM_MODE_MAX    = 0,
    PWM_MODE_MANUAL = 1,
    PWM_MODE_AUTO   = 2,
};
```

| Valor | O que faz de fato |
|---|---|
| `0` | **MÁXIMO** — comando WMI `0x27` com valor 1. O driver renova a cada 90 s, porque o firmware HP reverte sozinho após 120 s |
| `1` | **MANUAL** — apenas Victus 16-r/16-s; retorna `EOPNOTSUPP` nos demais |
| `2` | **AUTOMÁTICO** — devolve o controle ao EC (padrão do driver ao carregar) |

Isso segue a ABI padrão do hwmon (`0` = sem controle/velocidade máxima). O valor `2` que
você encontra por padrão **não é sintoma de nada** — é só o default.

## A descoberta principal

Com o tacômetro inoperante, o EC não consegue fechar a malha de controle e opera numa
curva mínima e defensiva. É comportamento razoável para um firmware que não sabe se a
ventoinha está respondendo — mas o resultado prático é refrigeração muito abaixo do que
o hardware entrega.

Como o tacômetro morreu, o instrumento que mediria a rotação também morreu. A saída foi
usar **a própria temperatura como instrumento**: mesma carga, mesmo ponto de partida,
mudando apenas o modo do fan.

| Instante | AUTO | MAX | Δ |
|---|---:|---:|---:|
| t+3 s | 75,1 °C | 64,0 °C | **11,1 °C** |
| t+42 s | **88,1 °C** (abortou) | **79,8 °C** | **8,3 °C** |
| tempo até 88 °C | 42 s | 78 s | **1,9×** |

Isso também **descarta** aletas entupidas e pasta térmica ressecada como gargalo
principal: se a dissipação fosse o limite, o modo máximo não faria diferença.

### Validação com o serviço instalado, máquina fechada

| Carga (16 threads) | Antes: tampa aberta, sem serviço | Depois: tampa fechada, com serviço |
|---|---|---|
| @ 2,5 GHz | 77,2 °C aos 120 s, ainda subindo | **73,4 °C** estabilizado |
| @ 3,5 GHz | **88,1 °C aos 42 s → aborto** | pico 85,4 °C, **desceu** para 78,9 °C |
| sem limite | não testado | pico 78,2 °C, **desceu** para 74,5 °C |

Repouso caiu de 44–46 °C para **39,9 °C**. A carga que antes disparava o corte térmico
em 42 segundos agora é vencida pela refrigeração.

Medições completas em [`dados/medicoes.md`](dados/medicoes.md).

## A correção

O `hp-wmi` neste hardware oferece apenas **MÁXIMO** ou **AUTOMÁTICO** — não há controle
proporcional (o modo `pwm1` só existe nos Victus S). Rodar sempre em máximo resolveria a
temperatura ao custo de ruído constante e desgaste do mancal.

A solução é alternar entre os dois modos por temperatura, com histerese —
**implementando em espaço de usuário a curva que o EC deixou de fazer**, usando
exclusivamente a interface suportada:

- **≥ 68 °C** → `pwm1_enable=0` (MÁXIMO)
- **≤ 58 °C** → `pwm1_enable=2` (AUTOMÁTICO)
- entre os dois → mantém o estado atual

Só escreve quando o estado **muda**, então em uso normal são pouquíssimas chamadas WMI.
Ao parar (`stop`, `restart`, reboot) deixa em máximo, que é a direção termicamente segura.

## Instalação

```bash
git clone https://github.com/HenriqueMazini/hp-pavilion-fan-fix.git
cd hp-pavilion-fan-fix
sudo ./install.sh
```

Acompanhar:

```bash
journalctl -u hp-fan-curve -f
```

Ajustar os limiares — edite `Environment=` em `/etc/systemd/system/hp-fan-curve.service`
e recarregue:

```bash
sudo systemctl daemon-reload && sudo systemctl restart hp-fan-curve
```

| Você quer | Faça |
|---|---|
| Mais silêncio | aumente `SOBE` (ex.: `75000`) |
| Mais folga térmica | diminua `SOBE` (ex.: `62000`) |
| Evitar alternância | mantenha ao menos 8–10 °C entre `SOBE` e `DESCE` |

Desinstalar (remove tudo e devolve o controle ao EC):

```bash
sudo ./uninstall.sh
```

## Scripts de diagnóstico

Todos resolvem os sensores **pelo nome**, nunca por índice fixo.

| Script | Root? | O que faz |
|---|---|---|
| [`diagnostico/coleta.sh`](diagnostico/coleta.sh) | não | Dump **somente-leitura** de DMI, hwmon, thermal zones, cooling devices, platform profile, dispositivos WMI e log do kernel — com notas explicando como ler cada saída |
| [`diagnostico/forca-maximo.sh`](diagnostico/forca-maximo.sh) | sim | O teste decisivo: escreve `1` (controle, deve falhar) e `0` (máximo), e monitora 30 s |
| [`diagnostico/carga.sh`](diagnostico/carga.sh) | sim | Teste térmico parametrizável sob carga, com aborto automático |
| [`diagnostico/calorimetria.sh`](diagnostico/calorimetria.sh) | sim | Roda a mesma carga em AUTO e em MAX e mede a diferença |

```bash
./diagnostico/coleta.sh > coleta.txt
sudo ./diagnostico/forca-maximo.sh
sudo ./diagnostico/calorimetria.sh --threads 16 --freq 3500000 --dur 120
```

Os testes de carga têm, **sempre ativas**: aborto automático por temperatura (padrão
88 °C), `trap EXIT/INT/TERM` que mata a carga + restaura o teto de frequência original +
põe a ventoinha em máximo, espera de resfriamento antes de começar, e teto rígido de
duração. A carga é um laço de inteiros puro, deliberadamente mais branda que `stress-ng`.

## O que foi descartado, e por quê

| Hipótese | Veredito |
|---|---|
| **`fancontrol` / `pwmconfig` / NBFC** | Inúteis aqui. O DSDT **não expõe a ventoinha como dispositivo ACPI** — não há `_FAN`, `_ACx` nem cooling device do tipo `Fan`. O controle é 100% do EC |
| **Regressão de kernel** | Impossível: a ventoinha também não girava **dentro do BIOS**, onde nenhuma linha de Linux roda. Testar kernel antigo seria desperdício |
| **`platform_profile` ausente** | Normal. O `hp-wmi` só registra perfil térmico para boards nas listas DMI Omen/Victus (8BC7 não está) ou se a WMI `0x4c` responder |
| **`hp-wmi-sensors` não carregar** | Esperado. Os GUIDs `8F1F6435/6436-…` aparecem no log como `has zero instances` — são das linhas comerciais (EliteBook/ProBook) |
| **Erros `AE_AML_BUFFER_LIMIT` em `WQBZ`/`WQBE`** | **Não têm relação com a ventoinha.** São do `hp_bioscfg` enumerando settings da BIOS — o log traz `hp_bioscfg: Returned error 0x3` na linha seguinte, e `/sys/class/firmware-attributes/hp-bioscfg/attributes/` fica quase vazio. É um off-by-one de AML na F.05 (índice `0x32` num objeto de comprimento `0x32`) |
| **Aletas entupidas / pasta térmica** | Descartadas pela calorimetria: se a dissipação fosse o gargalo, o modo máximo não daria 8–11 °C de ganho |
| **Ventoinha, alimentação, MOSFET, conector de força** | Íntegros: ela gira quando comandada |

## Armadilhas que custaram tempo

- **Os índices `hwmonN` não são estáveis entre boots.** Hoje o `hp` pode ser `hwmon6` e
  amanhã outro. Sempre resolva pelo campo `name`. Todo script aqui faz isso.
- **A extensão GNOME Vitals mostra a média de todos os sensores por padrão.** Num pico
  em que o `Tctl` marcava 70,6 °C, o Vitals exibia **58 °C**. Configure para exibir o
  máximo, ou fixe o `k10temp`. Monitorar pela média é como dirigir olhando a média do
  velocímetro com o conta-giros.
- **O firmware HP reverte o modo do fan após 120 s.** Qualquer teste de modo automático
  com menos de ~3 minutos é inconclusivo. O driver renova a cada 90 s, mas só em modo
  máximo.
- **`fan1_input = 0` não significa ventoinha parada.** Com o tacômetro morto ela gira e
  o número continua zero. Confirme visualmente ou com uma tira de papel.
- **Com a tampa inferior removida a condição térmica não é a real** — costuma ser até um
  pouco melhor para a CPU. Meça com a máquina fechada antes de concluir qualquer coisa.
- **Se o `sudo` exigir tty** e você estiver num contexto sem terminal, use `pkexec`, que
  abre um diálogo gráfico via polkit.

## Causa raiz ainda em aberto

O serviço compensa o sintoma por um caminho legítimo, mas **o defeito continua lá**: o
tacômetro não reporta RPM. Candidatos, do mais provável ao menos:

1. **Conector ou cabo da ventoinha** — pino do tacômetro sem contato, conector não
   assentado até o fim, fio pinçado ou rompido. É o mais provável, especialmente se o
   notebook foi aberto recentemente. Reencaixe com firmeza e verifique:
   ```bash
   cat /sys/class/hwmon/hwmon*/fan1_input   # com a ventoinha comprovadamente girando
   ```
   Qualquer valor diferente de zero significa que o tacômetro voltou — e é provável que
   o EC recupere sozinho a curva correta, tornando este serviço dispensável.
2. **Firmware do EC** — vale tentar o **HP BIOS Recovery via `Win+B`**, que reflasheia
   BIOS *e* firmware do EC sem precisar de pendrive, download ou Windows: desligado e na
   tomada, segure `Win`+`B`, pressione Power 2–3 s, solte o Power mantendo `Win`+`B` por
   mais ~10 s.
3. **Sensor Hall da própria ventoinha** — nesse caso a peça precisa ser trocada.

## BIOS

Para o board **8BC7**, a versão mais recente confirmada é a **F.07**, verificada no
arquivo CVA oficial da HP (não por semelhança de família):

```
SoftPaq   : SP155619            (01/11/2024)
ROM       : 08BC7F07.bin
SysId01   : 0x8BC7
Supersede : SP154164 (F.06, 08BC7F06.bin)
```

- CVA: `https://ftp.hp.com/pub/softpaq/sp155501-156000/sp155619.cva`
- O SHA-256 do `.exe` confere com o declarado no CVA
- ⚠️ **É irreversível**: *"previous BIOS versions cannot be reinstalled after this BIOS update"*
- Sem Windows, o caminho é `Win+B` (recovery) ou extrair o SoftPaq (o `cabextract` não
  basta; é preciso p7zip ou rodar o `BIOS_Update.EXE` no Wine para gerar o pendrive de
  recuperação). A estrutura esperada no pendrive é
  `EFI\Hewlett-Packard\BIOS\New\08BC7F07.bin` + `.sig`
- HP não publica Pavilion no LVFS, então `fwupdmgr` não encontra esta atualização

## Segurança

- O serviço usa **apenas** a interface suportada do `hp-wmi`. Nenhuma escrita em
  registrador de EC, nenhuma tentativa e erro em endereços, nenhum módulo fora da árvore.
- O comando `0x27` é o mesmo que o próprio driver emite no boot (com argumento `0`) e o
  que o software da HP usa. Empurra sempre na direção termicamente segura.
- Os testes de carga têm aborto automático e restauram tudo via `trap`.
- Mesmo assim: **este projeto mexe com refrigeração.** Se sua ventoinha estiver
  comprovadamente parada, não rode testes de carga até ter ventilação funcionando. Um
  limite temporário de frequência é uma boa mitigação enquanto isso:
  ```bash
  # exemplo: limitar a 2,5 GHz enquanto diagnostica
  for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq; do
      echo 2500000 | sudo tee "$f" >/dev/null
  done
  ```

## Referências

- [`drivers/platform/x86/hp/hp-wmi.c`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/platform/x86/hp/hp-wmi.c) — fonte da verdade sobre a semântica do `pwm1_enable`
- [ABI do hwmon](https://docs.kernel.org/hwmon/sysfs-interface.html)
- [HP — Recovering the BIOS](https://support.hp.com/us-en/document/ish_3932413-2337994-16)

## Licença

MIT — veja [LICENSE](LICENSE).
