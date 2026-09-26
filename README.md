# hp-pavilion-fan-fix

Diagnóstico de notebooks **HP Pavilion** cuja ventoinha não gira sozinha no Linux —
incluindo o caso em que ela **também não gira dentro do BIOS**, mesmo com
`Fan Always On = Enabled`.

> **Se você chegou aqui com esse sintoma, comece pelo [reset do EC](#comece-por-aqui-o-reset-do-ec).**
> É gratuito, leva minutos e foi o que resolveu de verdade neste caso. Todo o resto
> deste repositório é o diagnóstico que levou até lá, as medições que o sustentam, e a
> mitigação para enquanto o problema persistir.

---

## Índice

- [Comece por aqui: o reset do EC](#comece-por-aqui-o-reset-do-ec)
- [O desfecho, e uma tese que caiu](#o-desfecho-e-uma-tese-que-caiu)
- [A quem isto serve](#a-quem-isto-serve)
- [Sintomas](#sintomas)
- [O diagnóstico, camada por camada](#o-diagnóstico-camada-por-camada)
- [`pwm1_enable` no driver `hp-wmi`](#pwm1_enable-no-driver-hp-wmi)
- [Medições: quanto o EC deixava na mesa](#medições-quanto-o-ec-deixava-na-mesa)
- [A mitigação: `hp-fan-curve`](#a-mitigação-hp-fan-curve)
- [A caixa-preta forense](#a-caixa-preta-forense)
- [Scripts de diagnóstico](#scripts-de-diagnóstico)
- [Travamentos: o problema que continua aberto](#travamentos-o-problema-que-continua-aberto)
- [O tacômetro: defeito real, mas não era a causa](#o-tacômetro-defeito-real-mas-não-era-a-causa)
- [O que foi descartado, e por quê](#o-que-foi-descartado-e-por-quê)
- [Armadilhas que custaram tempo](#armadilhas-que-custaram-tempo)
- [BIOS](#bios)
- [Segurança](#segurança)

---

## Comece por aqui: o reset do EC

O **Embedded Controller** é um microcontrolador independente da CPU. Ele guarda estado
próprio, que **sobrevive a reboot e a desligamento normal**. Quando esse estado trava, o
EC pode parar de acionar a ventoinha — e ignorar até a própria configuração de BIOS.

O sinal de que é o seu caso: **a ventoinha não gira nem dentro do BIOS setup**, com
`Fan Always On = Enabled`. Nesse momento nenhuma linha de Linux está rodando, então o
problema não é o sistema operacional. Não perca tempo trocando de distro ou de kernel.

Como forçar o reset:

1. Desligue por completo — **não** suspender, não hibernar.
2. Tire da tomada.
3. Remova a bateria, se o seu modelo permitir.
4. Segure o botão **Power por 30–60 s** com tudo desconectado, para drenar os capacitores.
5. Deixe descansar. No caso documentado aqui foram **horas** sem energia.
6. Recoloque tudo e ligue.

Se não resolver, o nível seguinte é reflashear o firmware do EC junto com a BIOS, pelo
**HP BIOS Recovery via `Win+B`** — sem pendrive, sem download, sem Windows: desligado e
na tomada, segure `Win`+`B`, pressione Power por 2–3 s, solte o Power mantendo `Win`+`B`
por mais ~10 s.

Se ainda assim não resolver, aí sim vale ler o resto deste repositório.

## O desfecho, e uma tese que caiu

Este README afirmou por várias versões que a causa raiz era o **tacômetro inoperante**:
sem leitura de RPM, o EC perderia a realimentação da malha de controle e operaria numa
curva mínima defensiva. A hipótese era coerente, explicava as medições e sobreviveu a
todos os testes disponíveis na época.

**Ela está errada**, e foi a própria máquina que a derrubou.

Depois de uma reinstalação de sistema — que envolveu um período longo sem energia — a
ventoinha voltou a funcionar sozinha, sem nada deste repositório instalado. E o
tacômetro **continua morto**:

| | Antes (Ubuntu 26.04) | Depois (Zorin OS 18.1) |
|---|---|---|
| Kernel | 7.0.0-29 | 7.0.0-29 no 1º boot, 7.0.0-30 depois |
| BIOS | F.05 | F.05 |
| `fan1_input` / `fan2_input` | 0 / 0 | **0 / 0** |
| `pwm1_enable` | 2 (AUTO) | 2 (AUTO), nada instalado |
| EC obedece `Fan Always On` | **não** | **sim** |
| Ventoinha em repouso | parada | **girando** |

A lógica é direta:

- **Antes:** tacômetro em 0 → ventoinha parada
- **Depois:** tacômetro em 0 → ventoinha funciona

Mesma leitura de tacômetro, comportamento oposto. Logo, **o tacômetro morto não era o que
impedia o EC de acionar a ventoinha.** A correlação era real; a causalidade estava
invertida.

O que mudou não foi a *informação* que o EC tem — foi o *estado* dele. E o primeiro boot
do sistema novo rodou o **mesmo kernel `7.0.0-29`** do sistema antigo, o que elimina
kernel e driver como explicação. BIOS também não mudou. Por eliminação, sobra o ciclo de
energia longo.

O detalhe que fecha o caso é a ventoinha girar **em repouso, a ~35 °C**. Um EC saudável
manteria ela parada nessa temperatura — a não ser que `Fan Always On = Enabled` esteja
sendo obedecido. Que é exatamente a opção que estava ligada o tempo todo e que o EC
travado ignorava, inclusive dentro do próprio BIOS setup.

### Ressalva honesta

Não foi um experimento controlado. Não é trivial travar o EC de novo sob demanda para
confirmar, e o gatilho exato dentro do processo de reinstalação não foi isolado — foi um
período sem energia, mas não sabemos qual duração é necessária. A conclusão é por
eliminação de todas as outras variáveis, não por reprodução.

## A quem isto serve

Sistema onde o diagnóstico foi feito:

| | |
|---|---|
| Modelo | HP Pavilion Laptop 15-eh3xxx |
| System Board ID | **8BC7** |
| CPU | AMD Ryzen 7 7730U |
| BIOS | F.05 (24/04/2024), AMI |
| SO na época do diagnóstico | Ubuntu 26.04 LTS, kernel 7.0.0-29 |
| SO atual | Ubuntu 26.04 (reinstalado em 22/set), kernel 7.0.0-34 |
| RAM atual | 16 + 32 GB (nenhum pente original) |
| Driver | `hp-wmi` (`/sys/class/hwmon/hwmonN` com `name=hp`) |

**Os scripts de diagnóstico são genéricos** e resolvem tudo por nome de sensor. A
mitigação depende de o `pwm1_enable` aceitar o valor `0`, e o daemon lê a CPU pelo
`k10temp` — ou seja, hoje ele pressupõe AMD.

Não serve para: Omen, Victus 16-d e Victus 16-r/16-s. Esses têm caminhos próprios no
driver (perfis térmicos, e no caso do Victus S até `pwm1` proporcional).

## Sintomas

- Ventoinha completamente parada, mesmo sob carga pesada
- Notebook **trava**: telas e mouse apagam, mas o LED do power continua aceso — parece
  desligamento, [e não é](#travamentos-o-problema-que-continua-aberto)
- `sensors` mostra `fan1: 0 RPM` e `fan2: 0 RPM`
- **A ventoinha também não gira dentro do BIOS/UEFI**, com `Fan Always On = Enabled`
- Reset de CMOS/EC pelo procedimento curto não resolve
- `fancontrol`, `pwmconfig` e NBFC não encontram nada para controlar

O quarto item é o mais informativo de todos, e o que aponta direto para o EC.

## O diagnóstico, camada por camada

A investigação percorreu a pilha de cima para baixo, eliminando uma camada por vez com
evidência, em vez de tentar soluções no escuro:

```
Ubuntu ............... OK
kernel 7.0 ........... OK
hp-wmi ............... OK   <- hwmon registrado, leitura e escrita funcionam
ACPI / WMI ........... OK   <- comando 0x27 executa, exit=0
BIOS ................. OK   <- não rejeita o comando
Embedded Controller .. FALHA <- aceita "máximo", mas sua política automática estava travada
tacômetro ............ FALHA <- nunca reporta RPM  (defeito real, mas independente)
alimentação / motor .. OK   <- ventoinha gira quando comandada
```

O ponto sutil, e que só ficou claro no fim: o EC tem **duas funções separadas** aqui, e
só uma estava quebrada.

| Função do EC | Estado |
|---|---|
| Executar comando explícito (WMI `0x27` = máximo) | **sempre funcionou** |
| Política autônoma de ventoinha (curva própria, `Fan Always On`) | **travada** |

Por isso forçar o máximo sempre deu certo enquanto o modo automático não fazia nada. Não
era o EC "escolhendo" uma curva conservadora por falta de dados — era a política dele
inerte.

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

## `pwm1_enable` no driver `hp-wmi`

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

## Medições: quanto o EC deixava na mesa

Estas medições foram feitas com o EC travado. Elas continuam integralmente válidas: são
a quantificação do que se perde quando a política autônoma do EC não está funcionando.

Com o tacômetro inoperante, o instrumento que mediria a rotação também morreu. A saída
foi usar **a própria temperatura como instrumento**: mesma carga, mesmo ponto de partida,
mudando apenas o modo do fan.

| Instante | AUTO | MAX | Δ |
|---|---:|---:|---:|
| t+3 s | 75,1 °C | 64,0 °C | **11,1 °C** |
| t+42 s | **88,1 °C** (abortou) | **79,8 °C** | **8,3 °C** |
| tempo até 88 °C | 42 s | 78 s | **1,9×** |

Isso também **descartou** aletas entupidas e pasta térmica ressecada como gargalo
principal: se a dissipação fosse o limite, o modo máximo não faria diferença.

### Validação com a mitigação instalada, máquina fechada

| Carga (16 threads) | Antes: tampa aberta, sem serviço | Depois: tampa fechada, com serviço |
|---|---|---|
| @ 2,5 GHz | 77,2 °C aos 120 s, ainda subindo | **73,4 °C** estabilizado |
| @ 3,5 GHz | **88,1 °C aos 42 s → aborto** | pico 85,4 °C, **desceu** para 78,9 °C |
| sem limite | não testado | pico 78,2 °C, **desceu** para 74,5 °C |

Repouso caiu de 44–46 °C para **39,9 °C**. A carga que antes disparava o corte térmico
em 42 segundos passou a ser vencida pela refrigeração.

Para referência, com o **EC recuperado** e sem nada instalado, o repouso está em
**~35 °C**. A comparação não é perfeitamente controlada — essa leitura foi na bateria,
com `energy_performance_preference=balance_power`, então parte do ganho é consumo menor e
não só ventilação.

### Um alerta: carga total e thread única dão respostas opostas

| Carga (sem limite de frequência) | Pico | Comportamento |
|---|---:|---|
| 16 threads | **74,5 °C** | sobe, estabiliza e **desce** |
| 1 thread | **90,5 °C** | sobe devagar e segue subindo |

É densidade de potência: em all-core ~30 W se espalham por 8 núcleos; em thread única
~20 W se concentram num só, e o ponto quente do die dispara mais rápido do que qualquer
ventoinha responde. **Medir só carga total leva a conclusão errada sobre limitar
frequência.** Os ~90 °C são o teto físico da máquina — a ventoinha já está em MÁXIMO
durante todo o trecho quente — e ficam bem abaixo do Tjmax de ~105 °C, onde a própria
CPU se limita.

Medições completas em [`dados/medicoes.md`](dados/medicoes.md).

## A mitigação: `hp-fan-curve`

> **Não instale isto se a sua ventoinha já funciona.** Forçar o máximo por cima de um EC
> saudável é uma regressão: mais ruído, mais desgaste do mancal, e ainda mascara se o EC
> está de fato operando. Este daemon é para quem tem o EC travado e ainda não conseguiu
> destravá-lo.

O `hp-wmi` neste hardware oferece apenas **MÁXIMO** ou **AUTOMÁTICO** — não há controle
proporcional (`pwm1` só existe nos Victus S). Rodar sempre em máximo resolveria a
temperatura ao custo de ruído constante.

A mitigação alterna entre os dois modos por temperatura, com histerese —
**implementando em espaço de usuário a política que o EC deixou de executar**, usando
exclusivamente a interface suportada:

- **≥ 60 °C** → `pwm1_enable=0` (MÁXIMO)
- **≤ 52 °C** → `pwm1_enable=2` (AUTOMÁTICO)
- entre os dois → mantém o estado atual

Os limiares padrão foram escolhidos por medição, não por chute: comparados a 68/58, eles
deram baseline 12 °C menor e **2,6× mais tempo** até a temperatura crítica numa rajada de
thread única — sem provocar alternância (2 chaveamentos em 10 minutos de uso real).

Só escreve quando o estado **muda**, então em uso normal são pouquíssimas chamadas WMI.
Ao parar (`stop`, `restart`, reboot) deixa em máximo, que é a direção termicamente segura.

### Instalação

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

### Como saber que o EC voltou, e desinstalar

Com `Fan Always On = Enabled`, um EC recuperado mantém a ventoinha girando **mesmo em
repouso**. Isso te dá um detector de regressão audível e gratuito — algo que o
`fan1_input` **não** oferece, já que ele marca `0` nos dois cenários.

Pare o serviço por alguns minutos e observe. Se ela continuar girando sozinha, o EC
voltou: desinstale.

## A caixa-preta forense

Travamentos e desligamentos abruptos **não deixam rastro no journal** — ele simplesmente
para no meio. O daemon em [`forense/`](forense/) grava uma linha CSV a cada 5 s com
`fsync`, para que a última linha sobreviva a um corte ou a um travamento.

**Instale isto mesmo que a sua ventoinha esteja funcionando.** Ele não toca no controle
da ventoinha, custa quase nada em CPU (só builtins de bash; o único fork por iteração é o
`sync -d`), e é a única forma de transformar o próximo evento em informação em vez de
mais um episódio sem explicação.

**O CSV sozinho não distingue travamento de corte de energia**: nos dois casos a última
linha é normal e depois não há nada. Quem distingue é o LED do botão power — uma
observação de dois segundos que nenhum log guarda. Por isso a primeira pergunta não está
no CSV:

| O que se vê | Conclusão |
|---|---|
| LED do power **aceso**, telas e USB mortas | **travamento** — a energia não foi cortada ([ver abaixo](#travamentos-o-problema-que-continua-aberto)) |
| LED **apagado**, `ac_online` cai para `0` antes | perda de alimentação externa (tomada, fonte, cabo) |
| LED **apagado**, `ac_online` em `1` até a última linha | o **EC ou o hardware** cortou a energia |
| `tctl` subindo forte na última linha | térmico |

Instruções em [`forense/README.md`](forense/README.md).

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

## Travamentos: o problema que continua aberto

O problema que continua aberto nesta máquina **não é desligamento — é travamento**. Este
README passou semanas afirmando o contrário.

O sintoma, igual em todos os episódios desde o começo — na época da ventoinha parada,
depois com ela comprovadamente em máximo, e depois do reset do EC: **as telas apagam, o
mouse apaga, mas o LED do botão power continua aceso.** A máquina segue energizada e só
sai dali segurando o botão. Ninguém cortou energia: o processador inteiro parou, e vídeo e
USB caíram junto com ele.

### O que estava errado aqui antes

A versão anterior desta seção concluía que o EC cortava a energia por conta própria. O
raciocínio partia de um fato que continua verdadeiro — a thermal zone desta máquina expõe
só dois trip points:

```
trip_point_0_type = hot      trip_point_0_temp = 113000
trip_point_1_type = passive  trip_point_1_temp =  98000
```

**Não existe trip `critical`**, e o kernel registra em todo boot:

```
ACPI: thermal: [Firmware Bug]: Invalid critical threshold (-274000)
```

O `_CRT` da BIOS devolve lixo — −274 °C fica abaixo do zero absoluto — e por isso **o
Linux não tem como desligar esta máquina por temperatura.** Isso continua valendo, e
continua sendo um risco: a única proteção térmica que sobra é a do próprio EC.

O salto errado foi "o Linux não desligou, logo o EC cortou". Com o LED aceso, ninguém
desligou nada. A tese se sustentou enquanto ninguém perguntou o que acontecia com o LED.

### Por que a caixa-preta não viu a diferença

Travamento e corte de energia deixam **a mesma assinatura** no CSV: a última linha é
normal e depois não há nada. O `ac_online` em `1` até o fim, que antes era lido como "o
EC cortou", aparece igual num travamento. E nesta máquina ele informa ainda menos, porque
ela passa 98,6% do tempo na tomada.

Episódios registrados pela caixa-preta:

| Última linha do CSV | Tctl | GPU | Tomada | RAM disponível | load |
|---|---|---|---|---|---|
| 15/set 20:50:27 | 77,8 °C | 77 °C | sim, carregando | 12,8 GB | 1,63 |
| 18/set 12:51:32 | 54,3 °C | 45 °C | sim, bateria cheia | 11,3 GB | 1,16 |
| 26/set 15:34:18 | 66,0 °C | 56 °C | sim, carregando | 22,0 GB | 1,47 |

Um terceiro episódio, em 24/set, veio depois de reinstalar o Ubuntu e trocar **toda** a
RAM (agora 16 + 32 GB). Não há CSV: a reinstalação desfez a caixa-preta e o vigia. O
journal termina às 01:15:15, com o Docker subindo containers. Às 00:36 o firmware do
Wi-Fi (RTL8852BE) tinha travado pela segunda vez naquele boot.

Em todos os episódios com CSV: nenhum MCE ou erro de hardware no log do kernel, `pstore` vazio, nenhuma
sequência de desligamento no journal, `pswpout` parado. Não foi calor, não foi falta de
memória e, com o LED aceso, não foi energia.

**O horário do journal engana.** Em 18/set o journal termina às 12:50:17, mas a
caixa-preta gravou até 12:51:32. Por padrão o `journald` segura mensagens até 5 minutos
na memória antes de gravar (`SyncIntervalSec`); num travamento resolvido no botão, esse
último trecho se perde. O horário do evento é a última linha do CSV. Com
`SyncIntervalSec=15s`, em 26/set o journal parou só 4 s antes do CSV.

### 26/set: o vigia armado não disparou

O episódio de 26/set foi o primeiro com o [vigia de travamento](#como-separar-os-suspeitos)
armado (`hardlockup_panic=1`, `NMI watchdog: Enabled` no boot) e a mitigação do Wi-Fi
ativa. A máquina **não reiniciou sozinha** e o `pstore` ficou vazio.

O NMI é uma interrupção que a CPU atende mesmo com o kernel travado. Se nem ele rodou, o
travamento foi **abaixo do kernel**: o processador inteiro parou. Isso descarta travamento
de software — kernel, `amdgpu`, Docker, qualquer processo —, que o vigia teria pegado.

### Suspeitos que restam

Só fica na lista o que esteve presente em **todos** os episódios:

| Suspeito | Por que continua na lista |
|---|---|
| Processador (Ryzen 7 7730U) e firmware — BIOS, SMU/PSP, EC | presente em todos os episódios, e é a camada onde um travamento derruba vídeo e USB ao mesmo tempo |
| Wi-Fi Realtek RTL8852BE (`rtw89`) — **enfraquecido** | presente em todos os episódios; o firmware travou duas vezes no boot de 24/set, 40 min antes do travamento. Com a mitigação ativa (`rtw89_pci disable_aspm_l1=y disable_aspm_l1ss=y disable_clkreq=y` e `rtw89_core disable_ps_mode=y` em `/etc/modprobe.d/`), o firmware ainda travou uma vez, em 24/set 19:41, se recuperou, e a máquina rodou mais 44 h antes de travar sem nenhum erro de Wi-Fi por perto. Não sai da lista porque um dispositivo PCIe travado também pode parar o barramento abaixo do kernel |

**Descartado: os pentes de RAM.** A RAM passou de 2 × 8 GB para 8 + 16 GB, e depois para
16 + 32 GB, sem nenhum pente original. Os travamentos continuaram nas três configurações.
O controlador de memória fica dentro do processador, então ele segue no primeiro suspeito.

**Descartado: `amdgpu` e kernel.** Um travamento de software seria pego pelo vigia, e em
26/set ele [não disparou](#26set-o-vigia-armado-não-disparou).

### Como separar os suspeitos

Por padrão o kernel detecta CPU travada (`nmi_watchdog=1`), mas só **avisa** — e o aviso
se perde junto com o resto. Armado, o vigia transforma o travamento em pane, a pane é
gravada pelo firmware (`efi_pstore`) e a máquina reinicia sozinha:

```bash
# vigia de travamento: vira pane, grava no pstore, reinicia em 10 s
printf 'kernel.softlockup_panic = 1\nkernel.hardlockup_panic = 1\nkernel.panic = 10\n' \
  | sudo tee /etc/sysctl.d/99-caixa-preta.conf
sudo sysctl -p /etc/sysctl.d/99-caixa-preta.conf

# journald grava no máximo a cada 15 s, em vez de 5 min
sudo mkdir -p /etc/systemd/journald.conf.d
printf '[Journal]\nSyncIntervalSec=15s\n' | sudo tee /etc/systemd/journald.conf.d/caixa-preta.conf
sudo systemctl restart systemd-journald
```

Para desfazer, apague os dois arquivos. Se o `sudo` não tiver um terminal para pedir a
senha, ponha os comandos num script e rode com `pkexec sh script.sh`.

O próximo travamento responde:

| O que acontece | Conclusão | Próximo passo |
|---|---|---|
| Reinicia sozinho em ~10 s e deixa arquivo em `/var/lib/systemd/pstore/` | o kernel viu o travamento — driver ou software | ler o dump, que diz onde parou |
| Trava como sempre: LED aceso, sem reiniciar, `pstore` vazio | travou abaixo do kernel — processador, firmware ou um dispositivo PCIe (Wi-Fi) | se já estiver com a mitigação do Wi-Fi, a [BIOS F.07](#bios) |

### Teste em andamento: `processor.max_cstate=1`

Desde 26/set, antes de arriscar a BIOS F.07 (irreversível), está em teste uma mudança
barata e reversível: limitar o processador ao estado ocioso C1. Travamento total ao
entrar ou sair dos estados mais profundos (C2/C3) é uma causa conhecida em Ryzen. Nesta
máquina o driver de idle é o `acpi_idle`, que é o que respeita esse parâmetro.

```bash
echo 'GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT processor.max_cstate=1"' \
  | sudo tee /etc/default/grub.d/99-max-cstate.cfg
sudo update-grub   # e reiniciar
# conferir: só devem existir POLL e C1
grep . /sys/devices/system/cpu/cpu0/cpuidle/state*/name
```

Para desfazer: `sudo rm /etc/default/grub.d/99-max-cstate.cfg && sudo update-grub`.

O custo é um pouco mais de calor e consumo em repouso. Os travamentos vinham a cada 1–2
dias, então o critério é **uma semana sem travar**. Se travar de novo com o C-state
limitado, o próximo passo é a [BIOS F.07](#bios).

Sobre o memtest86+: com Secure Boot ligado ele pode não iniciar — desligue
temporariamente no setup da BIOS (F10) e religue depois. No Ubuntu o menu do GRUB fica
oculto por padrão; aperte Esc logo depois do logo da HP para vê-lo.

**Duas lições de método.**

A reinstalação apagou o disco inteiro e com ele todo o histórico — journal, `wtmp` e o
CSV da caixa-preta. Semanas de sintoma viraram zero evidência. Se você está caçando um
problema intermitente, **formatar destrói justamente o que você precisa.** Instale a
caixa-preta antes.

E antes de concluir qualquer coisa sobre um "desligamento", **pergunte o que aconteceu
com o LED**. É uma observação de dois segundos, não fica em log nenhum, e sozinha derrubou
a tese central desta seção.

## O tacômetro: defeito real, mas não era a causa

O tacômetro continua sem reportar RPM. É um defeito genuíno, apenas independente do
problema da ventoinha.

**Já descartado:** conector mal encaixado. O conector foi reassentado com firmeza e
`fan1_input`/`fan2_input` continuaram em `0` com a ventoinha comprovadamente girando.

Candidatos restantes, todos abaixo do conector:

1. **O cabo da ventoinha** — rompimento interno no fio do tacômetro, muitas vezes sem
   sinal externo visível.
2. **O sensor Hall dentro da ventoinha.**
3. **O pino de entrada do tacômetro no EC** — nível de placa-mãe.

Os candidatos 1 e 2 se resolvem juntos, porque **o conjunto ventoinha + cabo é uma peça
única** neste chassi.

Dito isso: com o EC funcionando, o impacto prático é pequeno. Você perde a leitura de RPM
e o detector de regressão passa a ser auditivo em vez de numérico. Não é mais urgente.

Como verificar depois de qualquer intervenção — com a ventoinha comprovadamente girando:

```bash
for h in /sys/class/hwmon/hwmon*; do
  [ "$(cat "$h/name")" = hp ] && cat "$h/fan1_input" "$h/fan2_input"
done
```

## O que foi descartado, e por quê

| Hipótese | Veredito |
|---|---|
| **Trocar de distro** | **Inútil, e comprovadamente.** A ventoinha não girava dentro do BIOS setup, onde nenhuma linha de Linux roda. E o sistema novo bootou com o **mesmo kernel 7.0.0-29** do antigo, com resultado oposto |
| **`fancontrol` / `pwmconfig` / NBFC** | Inúteis aqui. O DSDT **não expõe a ventoinha como dispositivo ACPI** — não há `_FAN`, `_ACx` nem cooling device do tipo `Fan`. O controle é 100% do EC |
| **Regressão de kernel** | Descartada duas vezes: a ventoinha não girava dentro do BIOS, e depois o mesmo kernel produziu comportamento oposto |
| **`platform_profile` ausente** | Normal. O `hp-wmi` só registra perfil térmico para boards nas listas DMI Omen/Victus (8BC7 não está) ou se a WMI `0x4c` responder. O módulo aparecer no `lsmod` é só dependência de símbolo do `hp_wmi`, não registro de perfil |
| **`hp-wmi-sensors` não carregar** | Esperado. Os GUIDs `8F1F6435/6436-…` aparecem no log como `has zero instances` — são das linhas comerciais (EliteBook/ProBook) |
| **Erros `AE_AML_BUFFER_LIMIT` em `WQBZ`/`WQBE`** | **Não têm relação com a ventoinha.** São do `hp_bioscfg` enumerando settings da BIOS — o log traz `hp_bioscfg: Returned error 0x3` na linha seguinte, e `/sys/class/firmware-attributes/hp-bioscfg/attributes/` fica quase vazio. É um off-by-one de AML na F.05 (índice `0x32` num objeto de comprimento `0x32`) |
| **Aletas entupidas / pasta térmica** | Descartadas pela calorimetria: se a dissipação fosse o gargalo, o modo máximo não daria 8–11 °C de ganho |
| **Ventoinha, alimentação, MOSFET, conector de força** | Íntegros: ela gira quando comandada |
| **Tacômetro morto como causa da ventoinha parada** | **Falsificado.** Tacômetro segue em `0` e a ventoinha voltou a funcionar |

## Armadilhas que custaram tempo

- **Correlação não é causa, e este projeto é o exemplo.** Duas falhas simultâneas —
  tacômetro morto e EC travado — pareciam uma só, com uma explicação causal elegante
  ligando as duas. A explicação sobreviveu a meses de evidência consistente e caiu
  quando uma das variáveis mudou sozinha.
- **Se o sintoma aparece dentro do BIOS setup, pare de investigar o sistema operacional.**
  Foi o dado mais informativo do diagnóstico inteiro e o que menos peso recebeu no começo.
- **Os índices `hwmonN` não são estáveis entre boots.** Hoje o `hp` pode ser `hwmon6` e
  amanhã outro. Sempre resolva pelo campo `name`. Todo script aqui faz isso.
- **`fan1_input = 0` não significa ventoinha parada.** Com o tacômetro morto ela gira e
  o número continua zero. Confirme visualmente ou com uma tira de papel.
- **Cuidado com a linha `Average` da extensão GNOME Vitals.** No menu suspenso, o Vitals
  calcula `Average`, `Minimum` e `Maximum` **sobre todos os sensores de temperatura
  juntos** — CPU, GPU, placa e NVMe. Num pico em que o `Tctl` marcava 70,6 °C, a linha
  `Average` exibia **58 °C**, porque o NVMe a ~40 °C puxa a média para baixo. Ponha o
  máximo no painel:
  ```bash
  SD=~/.local/share/gnome-shell/extensions/Vitals@CoreCoding.com/schemas
  gsettings --schemadir "$SD" get org.gnome.shell.extensions.vitals hot-sensors
  # acrescente '__temperature_max__' à lista retornada e grave de volta com `set`
  ```
- **O firmware HP reverte o modo do fan após 120 s.** Qualquer teste de modo automático
  com menos de ~3 minutos é inconclusivo. O driver renova a cada 90 s, mas só em modo
  máximo.
- **Com a tampa inferior removida a condição térmica não é a real** — costuma ser até um
  pouco melhor para a CPU. Meça com a máquina fechada antes de concluir qualquer coisa.
- **Se o `sudo` exigir tty** e você estiver num contexto sem terminal, use `pkexec`, que
  abre um diálogo gráfico via polkit.

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

**Quando atualizar:** a BIOS carrega o firmware do EC e do processador, que são suspeitos
tanto da ventoinha parada quanto dos [travamentos](#travamentos-o-problema-que-continua-aberto).
A F.07 é uma carta legítima, mas **não numa máquina que está funcionando**. Um travamento
no meio da gravação, que obriga a desligar no botão, deixa você sem máquina. A gravação
roda fora do Linux, então um travamento de driver ou de kernel não chega a ela — o risco é
o travamento vir de RAM, processador ou firmware. Guarde a F.07 para dois casos: o EC
travar a ventoinha de novo, ou o vigia de travamento mostrar que o problema está abaixo
do kernel **e** a RAM passar no memtest.

## Segurança

- A mitigação usa **apenas** a interface suportada do `hp-wmi`. Nenhuma escrita em
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
