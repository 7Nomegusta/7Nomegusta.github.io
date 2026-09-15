---
title: "TryHackMe - Jump"
date: 2026-09-15 18:00:00 -0300
categories: [TryHackMe, Linux]
tags: [nmap, ftp, anonymous-ftp, reverse-shell, pspy, cron, path-hijacking, privilege-escalation]
description: "A Linux-focused TryHackMe writeup covering anonymous FTP, automated shell execution, horizontal privilege escalation and PATH hijacking."
image:
  path: /assets/img/posts/tryhackme/jump/01-reconnaissance.png
  alt: TryHackMe Jump reconnaissance evidence
---

# TryHackMe - Jump

## Overview

This writeup documents my path through the **Jump** room on TryHackMe. The goal was to enumerate the exposed services, obtain an initial foothold, and move laterally between users by identifying insecure automation and execution contexts.

The main techniques covered were:

- Nmap service enumeration;
- anonymous FTP access;
- automated processing of uploaded shell scripts;
- process monitoring with `pspy`;
- exploitation of a writable script executed by another user;
- PATH hijacking through an unqualified system binary.

> This material is for educational purposes and was performed against the authorized TryHackMe target only. Flags are intentionally redacted.

---

## Reconnaissance

I started with a service and version scan:

```bash
nmap -sC -sV -Pn <TARGET_IP>
```

The scan identified two relevant services:

```text
21/tcp  open  ftp  vsftpd 3.0.5
22/tcp  open  ssh  OpenSSH 9.6p1 Ubuntu 3ubuntu13.16
```

The default scripts also reported that anonymous FTP authentication was allowed:

```text
ftp-anon: Anonymous FTP login allowed
```

![Nmap scan and FTP enumeration](/assets/img/posts/tryhackme/jump/01-reconnaissance.png)

---

## Anonymous FTP

I connected to the FTP service using the anonymous account:

```bash
ftp <TARGET_IP>
```

After logging in, the directory listing exposed two locations:

```text
incoming
pub
```

The `incoming` directory was writable. The `pub` directory contained information indicating that files uploaded to `incoming` were processed automatically when they matched an accepted format.

This changed the direction of the enumeration: instead of only looking for downloadable files, I tested which uploaded file types triggered server-side processing.

---

## Initial Access

After testing different formats, shell scripts with the `.sh` extension were accepted and processed. I created a script containing a reverse shell, uploaded it to `incoming`, and started a listener on the attacker machine:

```bash
nc -nlvp 4444
```

When the server processed the uploaded script, the connection returned a shell as:

```text
recon_user
```

From this foothold, I confirmed access to the first user flag. The value is not included in this public writeup.

![Initial access through the automated FTP upload](/assets/img/posts/tryhackme/jump/02-initial-access.png)

---

## Horizontal Privilege Escalation

### recon_user -> dev_user

With the initial shell established, I enumerated recurring processes using `pspy64`:

```bash
./pspy64
```

The output revealed a scheduled execution of:

```text
/bin/bash /opt/dev/backup.sh
```

I then checked the permissions on the script:

```bash
ls -la /opt/dev/backup.sh
```

The file was owned by `dev_user`, but it was writable by the group/other permissions available to the current context. This meant the script could be modified before its next automated execution.

I added a controlled reverse-shell command to the script and opened a second listener:

```bash
nc -nlvp 4445
```

When the scheduled task executed again, the new connection arrived as:

```text
dev_user
```

This completed the first lateral movement step. The `dev_user` flag was also located, but is intentionally omitted here.

![Process discovery, writable backup script and dev_user shell](/assets/img/posts/tryhackme/jump/03-horizontal-escalation.png)

---

## PATH Hijacking

### dev_user -> monitor_user

Continuing the process enumeration from `dev_user`, I observed the recurring health-check service:

```text
/usr/local/bin/healthcheck
```

The script executed the `ps` command without an absolute path:

```bash
ps aux | grep -v grep
```

Using a command name instead of `/usr/bin/ps` makes execution dependent on the process environment's `PATH`. I inspected the service definition:

```bash
cat /etc/systemd/system/healthcheck.service
```

The service ran as `monitor_user` and exposed a useful PATH configuration:

```text
Environment=PATH=/opt/dev/bin:/usr/local/bin:/usr/bin
```

Because `/opt/dev/bin` appeared before `/usr/bin`, a malicious executable named `ps` placed in that directory would be selected first. I created a controlled replacement that started a reverse shell, made it executable, and waited for the health-check service to invoke it.

The technique is a classic PATH hijacking condition: a privileged or different-user process invokes a binary by name, while an attacker can write to an earlier directory in the search path.

![Health-check script, service PATH and PATH hijacking setup](/assets/img/posts/tryhackme/jump/04-path-hijacking.png)

---

## Key Lessons

1. **Small service details matter.** Anonymous FTP and a writable upload directory were enough to create the initial attack path.
2. **Automated jobs expand the attack surface.** `pspy` exposed scripts and services that were not obvious from the initial login.
3. **File permissions must be reviewed together with execution context.** A script is dangerous when it is both writable and executed by another user.
4. **Always inspect how commands are invoked.** An unqualified command such as `ps` can become exploitable when the PATH order is attacker-influenced.
5. **Public writeups should protect challenge answers.** The technical reasoning is preserved here, while the flags remain redacted.

## Tools Used

- Nmap
- FTP client
- Netcat
- `pspy64`
- Linux shell utilities

