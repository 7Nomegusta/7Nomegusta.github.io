---
title: "TryHackMe - Silver Platter"
date: 2026-09-20 16:00:00 -0300
categories: [TryHackMe, Linux]
tags: [nmap, web-enumeration, silverpeas, hydra, idor, ssh, credential-reuse, log-analysis, privilege-escalation]
description: "A write-up of the Silver Platter room, covering web enumeration, Silverpeas authentication, an IDOR vulnerability, credential exposure in system logs, and privilege escalation through sudo access."
permalink: /posts/silver-platter/
image:
  path: /assets/img/posts/tryhackme/silver-platter/silver-platter.png
  alt: TryHackMe Silver Platter room artwork
---

# TryHackMe - Silver Platter

## Overview

This write-up documents the path I followed through the **Silver Platter** room on TryHackMe. The objective was to enumerate the exposed services, gain access to the Silverpeas application, obtain an initial shell, and escalate privileges to `root`.

The attack path consisted of:

- service reconnaissance with Nmap;
- web and directory enumeration;
- discovery of a Silverpeas username;
- creation of a targeted password wordlist;
- authentication to Silverpeas through a dictionary attack;
- exploitation of an insecure direct object reference (IDOR);
- SSH access as `tim`;
- discovery of credentials exposed in authentication logs;
- credential reuse to access the `tyler` account;
- final privilege escalation through `sudo`.

> This material is for educational purposes. The activity was performed only against the authorized TryHackMe target. Passwords and flags have been redacted.

---

## Reconnaissance

I began by scanning all TCP ports and enabling Nmap's default scripts and service-version detection:

```bash
nmap -sV -sC -Pn -p- <TARGET_IP>
```

The scan identified three exposed services:

```text
22/tcp    open  ssh
80/tcp    open  http
8080/tcp  open  http-proxy
```

Port 22 exposed OpenSSH, port 80 hosted an Nginx website, and port 8080 returned HTTP content that required further investigation.

![Nmap scan showing the exposed services](/assets/img/posts/tryhackme/silver-platter/01-nmap-scan.png)

---

## Web Enumeration

I first inspected the website on port 80. Most of its content appeared static, but the contact section disclosed the username `scr1ptkiddy` and mentioned that the project manager used Silverpeas.

This provided two useful pieces of information: a likely application username and the name of the platform running on the second web service.

![Username disclosed on the website contact section](/assets/img/posts/tryhackme/silver-platter/02-username-disclosure.png)

I also used Gobuster to enumerate common files and directories:

```bash
gobuster dir \
  -u http://<TARGET_IP> \
  -w /usr/share/dirbuster/wordlists/directory-list-2.3-medium.txt \
  -x php,txt,pdf,bak,html
```

The scan found the expected static content, including `/images`, `/assets`, `README.txt`, and `LICENSE.txt`, but it did not reveal a direct path to exploitation.

![Gobuster results for the website on port 80](/assets/img/posts/tryhackme/silver-platter/03-gobuster-enumeration.png)

Visiting the service on port 8080 confirmed that Silverpeas was available under `/silverpeas`:

```text
http://<TARGET_IP>:8080/silverpeas/
```

![Silverpeas login page on port 8080](/assets/img/posts/tryhackme/silver-platter/04-silverpeas-login.png)

---

## Silverpeas Authentication

Before attempting a dictionary attack, I intercepted a login request with Burp Suite to understand the application's authentication flow. A failed login produced a `302 Found` response and redirected the browser to an error page.

![Failed Silverpeas login request inspected with Burp Suite](/assets/img/posts/tryhackme/silver-platter/05-burp-login-response.png)

The room indicated that the password would not be present in `rockyou.txt`, so a generic password list was unlikely to be effective. Instead, I used CeWL to build a targeted wordlist from the words on the public website:

```bash
cewl http://<TARGET_IP> > passwords.txt
```

![Creating a targeted password list with CeWL](/assets/img/posts/tryhackme/silver-platter/06-cewl-wordlist.png)

I then used Hydra against the Silverpeas authentication endpoint. The request body was reproduced from the request observed in Burp Suite, and `S=200` was used to identify the successful response:

```bash
hydra -l scr1ptkiddy -P passwords.txt <TARGET_IP> -s 8080 \
  http-post-form "/silverpeas/AuthenticationServlet:Login=^USER^&Password=^PASS^&DomainId=0:S=200"
```

Hydra identified a valid password for `scr1ptkiddy`. The password is redacted from the published evidence.

![Hydra identifying valid Silverpeas credentials](/assets/img/posts/tryhackme/silver-platter/07-hydra-result.png)

---

## IDOR in Silverpeas Notifications

After authenticating, I reviewed the application's available features and opened the notifications area. Individual messages were loaded through a URL containing a numeric `ID` parameter:

```text
/silverpeas/RSILVERMAIL/jsp/ReadMessage.jsp?ID=5
```

Changing the value manually returned notifications that did not belong to the authenticated user. The application accepted the object identifier without verifying whether `scr1ptkiddy` was authorized to access the requested message.

This is an **insecure direct object reference (IDOR)**: an application exposes an internal object identifier but does not enforce object-level authorization before returning the resource.

![Accessing another notification by changing its ID](/assets/img/posts/tryhackme/silver-platter/08-idor-notification.png)

By enumerating nearby message IDs, I found a notification containing SSH credentials for the user `tim`. The password remains redacted in the screenshot.

![SSH credentials disclosed through the IDOR](/assets/img/posts/tryhackme/silver-platter/09-ssh-credentials.png)

---

## Initial Access as tim

I used the credentials recovered from Silverpeas to connect to the target over SSH:

```bash
ssh tim@<TARGET_IP>
```

The login succeeded and provided an interactive shell as `tim`. From this account, I was able to read the first flag. Its value has been removed from the published evidence.

![Initial SSH access and the redacted user flag](/assets/img/posts/tryhackme/silver-platter/10-tim-user-flag.png)

---

## Log Analysis and Credential Exposure

Initial privilege-enumeration checks did not reveal an obvious escalation path. I then reviewed the account's group memberships and noticed that `tim` belonged to the `adm` group. On Ubuntu systems, this group commonly grants read access to selected log files under `/var/log`.

I searched the authentication log for commands containing password-related values:

```bash
grep -i "password" /var/log/auth.log
```

The log contained a `sudo` entry showing a Docker command previously executed by `tyler`. A database password had been supplied directly through the command line as an environment variable:

```text
DB_PASSWORD=<REDACTED>
```

Command-line secrets can be exposed through process listings, shell history, audit records, and authentication logs. In this case, the database password had also been reused as `tyler`'s system password.

> The screenshot containing this log entry was intentionally omitted because another occurrence of the credential remained visible outside the original redaction.

---

## Privilege Escalation: tim -> tyler -> root

I tested the recovered credential against the `tyler` account over SSH:

```bash
ssh tyler@<TARGET_IP>
```

The credential reuse allowed me to authenticate successfully. After logging in, I enumerated the account's delegated privileges:

```bash
sudo -l
```

The output contained the following rule:

```text
(ALL : ALL) ALL
```

This rule allowed `tyler` to run any command as any user and group, including `root`. Since no command restrictions were defined, I used the unrestricted sudo access to start a root shell:

![sudo -l showing tyler's unrestricted sudo privileges](/assets/img/posts/tryhackme/silver-platter/11-tyler-sudo-permissions.png)

```bash
sudo su
```

The prompt changed to `root`, confirming successful privilege escalation. From the root shell, the final flag could be read from `/root`; its value is not included in this write-up.

![Root shell obtained through tyler's sudo privileges](/assets/img/posts/tryhackme/silver-platter/12-root-shell.png)

---

## Key Takeaways

1. Public-facing content can disclose usernames and technology names that significantly improve later enumeration.
2. A targeted wordlist built from application-specific content can be more effective than a large generic password list.
3. Different responses for failed and successful authentication attempts can provide a reliable match condition for automated testing.
4. Numeric object identifiers must always be protected by server-side authorization checks; changing an ID should never expose another user's data.
5. Membership in groups such as `adm` can expose sensitive operational information even without direct administrative privileges.
6. Secrets should not be passed on command lines because they can be recorded in logs and other system artifacts.
7. Password reuse can turn an exposed application or database credential into operating-system access.
8. Privileged accounts and `sudo` rules should follow the principle of least privilege.

## Tools Used

- Nmap
- Gobuster
- Burp Suite
- CeWL
- Hydra
- SSH
- Linux shell utilities
