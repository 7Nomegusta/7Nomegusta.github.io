---
title: "TryHackMe - Jump"
date: 2026-09-15 07:00:00 -0300
categories: [TryHackMe, Linux]
tags: [nmap, ftp, anonymous-ftp, reverse-shell, pspy, cron, lateral-movement, path-hijacking, privilege-escalation]
description: "Writeup da sala Jump, cobrindo enumeracao de FTP anonimo, execucao automatica de scripts, movimentacao lateral e PATH hijacking."
permalink: /posts/jump/
image:
  path: /assets/img/posts/tryhackme/jump/jump.png
  alt: Logo da sala Jump no TryHackMe
---

# TryHackMe - Jump

## Visao Geral

Este writeup documenta o caminho seguido na sala **Jump**, do TryHackMe. O objetivo foi enumerar os servicos expostos, obter acesso inicial e realizar movimentacao lateral entre usuarios a partir de tarefas automatizadas e configuracoes inseguras.

O raciocinio foi organizado na mesma ordem em que a exploracao ocorreu:

- reconhecimento dos servicos com Nmap;
- enumeracao do FTP anonimo;
- identificacao do processamento automatico de arquivos `.sh`;
- acesso inicial como `recon_user`;
- movimentacao lateral para `dev_user` por meio de um script gravavel;
- exploracao de PATH hijacking para executar um payload como `monitor_user`.

> Este material foi produzido para fins educacionais e a atividade foi realizada somente contra o alvo autorizado do TryHackMe. As flags foram ocultadas.

---

## Reconhecimento

O primeiro passo foi identificar portas, servicos e versoes com o Nmap:

```bash
nmap -sC -sV -Pn <TARGET_IP>
```

O resultado mostrou as portas 21 e 22 abertas:

```text
21/tcp  open  ftp  vsftpd 3.0.5
22/tcp  open  ssh  OpenSSH 9.6p1 Ubuntu 3ubuntu13.16
```

Os scripts padrao do Nmap tambem indicaram que o servico FTP permitia autenticacao anonima. Como o servico expunha um diretorio acessivel sem credenciais, a proxima etapa foi enumerar seu conteudo e verificar as permissoes de leitura e escrita.

![Evidencia do reconhecimento com Nmap](/assets/img/posts/tryhackme/jump/01-reconnaissance.png)

---

## Enumeracao do FTP

Conectei-me ao servico utilizando o usuario anonimo:

```bash
ftp <TARGET_IP>
```

Depois do login, a listagem apresentou dois diretorios:

```text
incoming
pub
```

O diretorio `incoming` possuia permissao de escrita. No diretorio `pub`, havia uma informacao indicando que determinados formatos enviados para `incoming` eram processados automaticamente.

Esse detalhe mudou a linha de investigacao. Em vez de apenas procurar arquivos para baixar, passei a testar quais extensoes eram aceitas e o que acontecia quando um arquivo correspondente era enviado ao diretorio gravavel.

![Evidencia do login anonimo e da listagem do FTP](/assets/img/posts/tryhackme/jump/02-ftp-enumeration.png)

---

## Acesso Inicial

Os testes mostraram que arquivos com extensao `.sh` eram processados. A partir disso, preparei um script contendo uma reverse shell, enviei o arquivo para `incoming` e deixei um listener aguardando a conexao:

```bash
nc -nlvp 4444
```

Quando o processamento automatico ocorreu, a conexao retornou um shell no contexto de `recon_user`.

![Evidencia do envio do script e do recebimento da conexao](/assets/img/posts/tryhackme/jump/03-initial-shell.png)

Com esse acesso inicial, confirmei a existencia da primeira flag. O valor foi ocultado tanto do texto quanto da evidencia visual publicada.

![Evidencia do acesso inicial como recon_user](/assets/img/posts/tryhackme/jump/04-recon-user-access.png)

---

## Movimentacao lateral: recon_user -> dev_user

Com o shell inicial estabelecido, o proximo objetivo foi entender quais tarefas eram executadas automaticamente e em qual contexto de usuario. Para isso, utilizei o `pspy64`, que permite observar processos sem exigir privilegios administrativos:

```bash
./pspy64
```

Entre os processos recorrentes, apareceu a execucao de:

```text
/bin/bash /opt/dev/backup.sh
```

A descoberta foi relevante porque o script era executado por outro usuario. Em seguida, verifiquei suas permissoes:

```bash
ls -la /opt/dev/backup.sh
```

O arquivo pertencia a `dev_user`, mas estava gravavel no contexto disponivel. Um script gravavel que sera executado automaticamente por outro usuario representa uma oportunidade de movimentacao lateral: o conteudo pode ser alterado antes da proxima execucao e os comandos adicionados serao executados com as permissoes do processo agendado.

![Evidencia do processo backup.sh identificado pelo pspy](/assets/img/posts/tryhackme/jump/05-pspy-processes.png)

![Evidencia das permissoes de escrita em backup.sh](/assets/img/posts/tryhackme/jump/06-backup-permissions.png)

Editei o script para incluir uma reverse shell controlada e iniciei outro listener:

```bash
nc -nlvp 4445
```

Na execucao seguinte da tarefa automatizada, a conexao foi recebida como `dev_user`. Assim, a movimentacao lateral foi concluida sem depender de uma senha ou de um novo servico exposto.

![Evidencia do shell obtido como dev_user e do arquivo de flag](/assets/img/posts/tryhackme/jump/07-dev-user-shell.png)

---

## PATH Hijacking: dev_user -> monitor_user

Ainda a partir de `dev_user`, continuei analisando os processos observados pelo `pspy`. O servico recorrente `/usr/local/bin/healthcheck` chamou atencao porque executava o comando `ps` sem informar seu caminho absoluto:

```bash
ps aux | grep -v grep
```

Em vez de chamar diretamente `/usr/bin/ps`, o shell precisa localizar um executavel chamado `ps` consultando os diretorios definidos na variavel `PATH`. O script do health-check era executado como `monitor_user`:

```bash
cat /etc/systemd/system/healthcheck.service
```

Na configuracao do servico, o PATH estava definido assim:

```text
Environment=PATH=/opt/dev/bin:/usr/local/bin:/usr/bin
```

O shell procura os binarios da esquerda para a direita. Como `/opt/dev/bin` aparecia antes de `/usr/bin`, um binario falso chamado `ps`, colocado no primeiro diretorio pesquisado, poderia ser encontrado antes do binario legitimo do sistema.

![Evidencia do script health-check executando ps sem caminho absoluto](/assets/img/posts/tryhackme/jump/08-healthcheck-script.png)

![Evidencia do PATH e da execucao do servico como monitor_user](/assets/img/posts/tryhackme/jump/09-service-path.png)

A partir dessa condicao, criei um binario `ps` controlado contendo o payload de reverse shell e aguardei a execucao do health-check. Como o servico era executado no contexto de `monitor_user`, o payload seria chamado com as permissoes desse usuario.

Esse e o principio do **PATH hijacking**: um processo executado por outro usuario chama um binario apenas pelo nome, enquanto o atacante consegue influenciar um diretorio que aparece antes do caminho oficial no `PATH`.

---

## Principais aprendizados

1. Um servico aparentemente simples pode revelar uma cadeia de ataque quando suas permissoes sao analisadas com cuidado.
2. FTP anonimo, diretorio gravavel e processamento automatico de arquivos formaram o caminho ate o acesso inicial.
3. O `pspy` ajudou a identificar tarefas recorrentes e a relacionar cada tarefa ao usuario que a executava.
4. Scripts gravaveis executados por outro usuario devem ser tratados como uma oportunidade de movimentacao lateral.
5. Comandos chamados sem caminho absoluto precisam ser avaliados junto com a ordem do `PATH` e as permissoes dos diretorios envolvidos.
6. Em um writeup publico, e importante preservar o raciocinio tecnico sem expor as respostas da sala. Por isso, as flags permanecem ocultas.

## Ferramentas utilizadas

- Nmap
- Cliente FTP
- Netcat
- `pspy64`
- Utilitarios de shell Linux
