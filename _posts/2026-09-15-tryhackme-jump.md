---
title: "TryHackMe - Jump"
date: 2026-09-15 07:00:00 -0300
categories: [TryHackMe, Linux]
tags: [nmap, ftp, anonymous-ftp, reverse-shell, pspy, cron, lateral-movement, path-hijacking, privilege-escalation]
description: "A write-up of the Jump room, covering anonymous FTP enumeration, automated script execution, lateral movement, and PATH hijacking."
permalink: /posts/jump/
image:
  path: /assets/img/posts/tryhackme/jump/jump.png
  alt: TryHackMe Jump room logo
---

## Overview

This write-up documents the path I followed through the **Jump** room on TryHackMe. The goal was to enumerate exposed services, gain initial access, and move laterally between users by taking advantage of automated tasks and insecure configurations.

The steps are presented in the same order as the original exploitation path:

- service reconnaissance with Nmap;
- anonymous FTP enumeration;
- identification of automatic processing for `.sh` files;
- initial access as `recon_user`;
- lateral movement to `dev_user` through a writable script;
- PATH hijacking to execute a payload as `monitor_user`;
- lateral movement to `ops_user` through an unsafe `sudo` rule;
- final privilege escalation to `root` by using the permitted `less` binary.

> This material is for educational purposes. The activity was performed only against the authorized TryHackMe target. All flags have been redacted.

---

## Reconnaissance

The first step was to identify open ports, services, and versions with Nmap:

```bash
nmap -sC -sV -Pn <TARGET_IP>
```

The scan showed ports 21 and 22 open:

```text
21/tcp  open  ftp  vsftpd 3.0.5
22/tcp  open  ssh  OpenSSH 9.6p1 Ubuntu 3ubuntu13.16
```

Nmap's default scripts also reported that the FTP service allowed anonymous authentication. Since the service exposed a directory accessible without credentials, the next step was to enumerate its contents and check read and write permissions.

![Nmap reconnaissance evidence](/assets/img/posts/tryhackme/jump/01-reconnaissance.png)

---

## FTP Enumeration

I connected to the service using the anonymous account:

```bash
ftp <TARGET_IP>
```

After logging in, the directory listing showed two directories:

```text
incoming
pub
```

The `incoming` directory was writable. In `pub`, I found information indicating that certain file formats uploaded to `incoming` were processed automatically.

That detail shaped the next part of the investigation. Rather than only looking for files to download, I tested which extensions were accepted and what happened when a matching file was uploaded to the writable directory.

![Evidence of the anonymous FTP login and directory listing](/assets/img/posts/tryhackme/jump/02-ftp-enumeration.png)

---

## Initial Access

The tests showed that files with the `.sh` extension were processed. Based on that behavior, I prepared a script containing a reverse shell, uploaded it to `incoming`, and started a listener:

```bash
nc -nlvp 4444
```

When the automated processing ran, the connection returned a shell in the context of `recon_user`.

![Evidence of the script upload and incoming connection](/assets/img/posts/tryhackme/jump/03-initial-shell.png)

With initial access established, I confirmed the first flag. Its value is redacted from both the text and the published visual evidence.

![Evidence of the initial shell as recon_user](/assets/img/posts/tryhackme/jump/04-recon-user-access.png)

---

## Lateral Movement: recon_user -> dev_user

With the initial shell established, the next goal was to understand which tasks ran automatically and under which user account. I used `pspy64`, which allows processes to be observed without administrative privileges:

```bash
./pspy64
```

Among the recurring processes, I saw the following command:

```text
/bin/bash /opt/dev/backup.sh
```

This was relevant because the script was being run by another user. I then checked its permissions:

```bash
ls -la /opt/dev/backup.sh
```

The file belonged to `dev_user`, but was writable from my current context. A writable script that is automatically executed by another user creates an opportunity for lateral movement: its contents can be changed before the next run, causing added commands to execute with the permissions of the scheduled process.

![Evidence of the backup.sh process identified with pspy](/assets/img/posts/tryhackme/jump/05-pspy-processes.png)

![Evidence that backup.sh is writable](/assets/img/posts/tryhackme/jump/06-backup-permissions.png)

I edited the script to include a controlled reverse shell and started another listener:

```bash
nc -nlvp 4445
```

When the automated task ran again, the connection arrived as `dev_user`. This completed the lateral movement without requiring a password or another exposed service.

![Evidence of the shell as dev_user and the flag file](/assets/img/posts/tryhackme/jump/07-dev-user-shell.png)

---

## PATH Hijacking: dev_user -> monitor_user

Still operating as `dev_user`, I continued reviewing the processes observed with `pspy`. The recurring `/usr/local/bin/healthcheck` service stood out because it ran `ps` without specifying an absolute path:

```bash
ps aux | grep -v grep
```

Instead of invoking `/usr/bin/ps` directly, the shell has to locate an executable named `ps` by searching the directories listed in the `PATH` variable. The health-check script ran as `monitor_user`:

```bash
cat /etc/systemd/system/healthcheck.service
```

The service configuration defined `PATH` as follows:

```text
Environment=PATH=/opt/dev/bin:/usr/local/bin:/usr/bin
```

The shell searches for executables from left to right. Because `/opt/dev/bin` appeared before `/usr/bin`, a fake executable named `ps` placed in the first directory could be found before the legitimate system binary.

![Evidence of the health-check script invoking ps without an absolute path](/assets/img/posts/tryhackme/jump/08-healthcheck-script.png)

![Evidence of the PATH value and the service running as monitor_user](/assets/img/posts/tryhackme/jump/09-service-path.png)

I created a controlled `ps` executable containing a reverse-shell payload and waited for the health check to run. Since the service ran in the context of `monitor_user`, the payload was executed with that user's permissions.

This is the principle behind **PATH hijacking**: a process running as another user invokes a binary by name, while an attacker can influence a directory that appears before the official binary's location in `PATH`.

![Evidence of the shell obtained as monitor_user](/assets/img/posts/tryhackme/jump/10-monitor-user-shell.png)

---

## Lateral Movement: monitor_user -> ops_user

From the `monitor_user` shell, I performed basic enumeration of the permissions delegated to that account. The `sudo` configuration showed that `monitor_user` could run `/usr/local/bin/deploy.sh` as `ops_user` without entering a password.

![Evidence of the sudo permission for monitor_user](/assets/img/posts/tryhackme/jump/11-monitor-sudo-config.png)

Inspecting the script showed that `/usr/local/bin/deploy.sh` ran the relative file `./deploy_helper.sh` from within `/opt/app`. The helper file was writable by the current user, making it the point of control: its contents could be changed, and it would be invoked when the main script ran through `sudo`.

![Evidence of deploy.sh and its call to the helper file](/assets/img/posts/tryhackme/jump/12-deploy-script.png)

![Evidence that deploy_helper.sh is writable](/assets/img/posts/tryhackme/jump/13-deploy-helper.png)

I placed the reverse-shell payload in the helper file and ran the main script using the available delegation:

```bash
sudo -u ops_user /usr/local/bin/deploy.sh
```

Because the process was started as `ops_user`, execution of the helper returned a new connection under that account.

![Evidence of the payload prepared for deploy_helper.sh](/assets/img/posts/tryhackme/jump/14-ops-user-payload.png)

![Evidence of the shell obtained as ops_user](/assets/img/posts/tryhackme/jump/15-ops-user-shell.png)

---

## Final Privilege Escalation: ops_user -> root

Next, enumeration of `ops_user`'s permissions revealed another unsafe `sudo` configuration: the user could run `/usr/bin/less` as `root` without a password.

![Evidence of the sudo permission allowing ops_user to run less as root](/assets/img/posts/tryhackme/jump/16-root-sudo-config.png)

This permission allowed me to use `less` as `root` to open the flag file under `/root` directly. Access to its contents confirmed the final escalation to `root`; the flag value remains redacted in the visual evidence.

![Evidence of reading the flag with less as root](/assets/img/posts/tryhackme/jump/17-root-less-flag.png)

---

## Key Takeaways

1. A seemingly simple service can expose an attack chain when its permissions are examined carefully.
2. Anonymous FTP, a writable directory, and automatic file processing formed the path to initial access.
3. `pspy` helped identify recurring tasks and determine which user ran each one.
4. Writable scripts executed by another user should be treated as a lateral-movement opportunity.
5. Commands invoked without absolute paths must be assessed together with `PATH` ordering and directory permissions.
6. `sudo` rules that allow scripts or binaries to run as another user can greatly increase the impact of writable files.
7. Interactive binaries such as `less` also require careful review when they can be run as `root`.
8. A public write-up should preserve the technical reasoning without exposing room answers. All flags therefore remain redacted.

## Tools Used

- Nmap
- FTP client
- Netcat
- `pspy64`
- Linux shell utilities
- `sudo`
- `less`
