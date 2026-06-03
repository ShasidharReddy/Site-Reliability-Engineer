# Lab 03: System Audit

This lab teaches a practical audit loop: capture evidence, review exposure, inspect permissions, check security posture, and decide if the host is production ready.
The exercises are intentionally operational, not compliance-theory heavy.

## Audit mindset

- Evidence first, remediation second.
- Scope the host role before judging any setting.
- Treat unknown services and unknown access paths as high priority until explained.
- Check logs and recoverability, not just hardening knobs.
- End with a clear readiness recommendation and ownership list.

## 1. Ground rules and evidence capture

### Objective
Create a repeatable audit trail before you evaluate users, ports, files, and kernel posture.

### Safety and setup
- Open a shell with read-only intent first; avoid making changes during the evidence phase.
- Create an evidence directory such as ./audit-evidence if you need to copy outputs locally.
- Record hostname, kernel version, distro, environment, and owner of the system.
- Know which compliance or internal baseline you are auditing against.
- If the host is containerized, note whether you are auditing the node, container, or both.

### Questions to answer
- What is the scope of the audit: access, exposure, drift, hardening, or production readiness?
- Which accounts and services are expected to exist?
- What change window or owner should approve remediation?
- What evidence must be preserved for later review?

### Runbook
```bash
hostname
uname -a
date
uptime
cat /etc/os-release
systemctl list-units --type=service --state=running
ss -tulpen
journalctl -p warning -n 50
```

### Interpretation guide
| Evidence item | Why it matters | Example |
| --- | --- | --- |
| host identity | avoids mixing systems | hostname and serial or instance ID |
| kernel and distro | baseline behavior depends on version | uname and os-release |
| running services | attack surface and ownership | systemctl list-units |
| listening ports | network exposure | ss -tulpen |
| recent warnings | existing instability | journalctl warnings |

### What to look for
- A good audit starts with facts that later remediations can be compared against.
- This phase is where you discover whether the system already had warnings unrelated to your target scope.
- Capture service ownership early; unknown services are harder to triage later.
- If the host is heavily managed, note configuration tools so drift can be fixed in the right place.
- Record timestamps to make future evidence comparable.

### Completion checklist
- You can describe the host and its purpose without ambiguity.
- You have a current list of running services and listening sockets.
- You know the audit owner and the expected baseline source.
- You can proceed without writing changes to the host yet.

### Extension
- Build a standard pre-audit evidence bundle for your environment.
- Add asset identifiers from CMDB or cloud metadata if available.
- Compare this baseline with another host in the same fleet for drift.

## 2. User and access audit

### Objective
Confirm that only expected users, groups, and privileged paths exist.

### Safety and setup
- Know which human and service accounts should be present.
- Identify the expected sudo or privilege escalation model.
- If SSH is in scope, know whether key-only auth is required.
- Have a list of emergency or break-glass accounts that are approved.
- Coordinate with IAM or directory teams if accounts are centrally managed.

### Questions to answer
- Which accounts can log in interactively?
- Who has sudo or equivalent privilege?
- Are there stale keys, expired accounts, or unexpected service shells?
- Do PAM and sshd settings match policy?

### Runbook
```bash
getent passwd
awk -F: "$7 !~ /(nologin|false)$/ {print $1, $7}" /etc/passwd
getent group sudo wheel 2>/dev/null
sudo -l -U <user> 2>/dev/null
last -a | head -30
lastlog | head -30
grep -R "^AllowUsers\|^PasswordAuthentication\|^PermitRootLogin" /etc/ssh/sshd_config /etc/ssh/sshd_config.d 2>/dev/null
find ./ -maxdepth 1 -type f -name "authorized_keys*" 2>/dev/null
```

### Interpretation guide
| Check | Healthy result | Concern |
| --- | --- | --- |
| interactive users | limited and documented | orphaned or generic accounts |
| sudo access | least privilege | broad ALL access without review |
| root SSH | disabled unless explicitly required | enabled with password login |
| login history | expected admin access only | unknown source or time |

### What to look for
- Interactive shells on service accounts are a classic drift signal.
- A dormant privileged account is still a risk if it retains keys or sudo rights.
- Policy files may be layered through include directories; audit the whole tree.
- Login history alone is not enough; combine it with key and sudo review.
- Directory-managed accounts may not appear exactly as local accounts do.

### Completion checklist
- You can identify every account that can log in and every account that can escalate.
- You know whether SSH policy matches expectation.
- You found no unexplained keys or stale admin access, or you documented them.
- You have a prioritized remediation list for access issues.

### Extension
- Review PAM lockout and MFA integration if present.
- Check cron and systemd timers for commands executed as privileged users.
- Audit service account ownership against your CMDB or team roster.

## 3. Service and port audit

### Objective
Match every running service and listening port to an owner, purpose, and exposure expectation.

### Safety and setup
- List the expected inbound and outbound services before you look at the host.
- Know whether any local-only admin ports should bind to loopback only.
- Identify the init system and how services are managed.
- If containers are present, decide whether node-level or container-level listeners matter.
- Remember that UDP exposure is easy to miss when focusing on TCP.

### Questions to answer
- Which services are listening on non-loopback interfaces?
- Do any ports exist that are not in the approved architecture?
- Which process owns each socket?
- Are restart policies and service hardening options appropriate?

### Runbook
```bash
ss -tulpen
ss -lntup
systemctl list-unit-files --type=service
systemctl status <service>
lsof -i -P -n | head -40
firewall-cmd --list-all 2>/dev/null
nft list ruleset 2>/dev/null | head -80
grep -R "^Listen" /etc/systemd/system /usr/lib/systemd/system 2>/dev/null | head -40
```

### Interpretation guide
| Finding | Interpretation | Follow-up |
| --- | --- | --- |
| port on 0.0.0.0 | network exposed | confirm firewall and business need |
| loopback only | local admin or sidecar | confirm local dependency |
| unknown process owner | possible drift or compromise | trace package and service file |
| disabled unit but port open | process unmanaged or started elsewhere | inspect parent process |

### What to look for
- Binding scope matters as much as the port number itself.
- A service managed outside systemd deserves extra scrutiny because restarts and limits may differ.
- Port exposure must be checked together with firewall policy to know the real attack surface.
- Unexpected listeners on ephemeral high ports can still be critical if they accept remote traffic.
- Document both the unit name and the binary path for every important service.

### Completion checklist
- Every listener has an owner and an expected reason to exist.
- You know which ports are publicly reachable, internal-only, or local-only.
- You identified services that are unmanaged or weakly supervised.
- You can propose safe removals or tighter bind addresses.

### Extension
- Compare the port list with infrastructure-as-code definitions.
- Review systemd sandboxing options such as ProtectSystem and PrivateTmp.
- Map outbound-only agents that may not listen but still need network review.

## 4. Filesystem and permissions audit

### Objective
Find risky permissions, unusual ownership, and silent capacity problems in filesystems.

### Safety and setup
- Choose the directories that matter most: configs, binaries, data, logs, secrets, and backup paths.
- Know which files are expected to be writable at runtime.
- Avoid recursive scans of the entire system if scope and time are limited; focus first on critical paths.
- Remember to audit inode usage as well as byte usage.
- If containers are in play, distinguish host paths from bind mounts or overlay storage.

### Questions to answer
- Are critical configs writable by too many principals?
- Are there world-writable or group-writable paths that should be tighter?
- Are SUID or SGID binaries expected and documented?
- Is disk space or inode capacity close to exhaustion?

### Runbook
```bash
df -h
df -i
find /etc -xdev -type f -perm -002 2>/dev/null
find /usr/bin /usr/sbin -xdev \( -perm -4000 -o -perm -2000 \) 2>/dev/null
namei -l /etc/ssh/sshd_config
ls -ld /var/log /var/lib /etc
find /var/log -type f -size +100M 2>/dev/null | head -40
lsof +L1 2>/dev/null | head -40
```

### Interpretation guide
| Finding | Meaning | Action |
| --- | --- | --- |
| world-writable config | tamper risk | tighten ownership and mode |
| unexpected SUID binary | privilege escalation risk | confirm package and need |
| deleted-open file | hidden capacity use | restart or rotate writer |
| inode pressure | tiny-file buildup | cleanup directory tree and retention |

### What to look for
- Permissions must be traced through every path component, not just the leaf file.
- Deleted-open files often explain why df and du disagree.
- Log directories deserve special attention because they combine write access and growth risk.
- A legitimate SUID binary is still worth documenting because it affects threat modeling.
- Overlay or container storage can consume host capacity in places the application never references directly.

### Completion checklist
- You found no critical world-writable paths, or you documented and prioritized them.
- You know which filesystems are capacity risks for bytes or inodes.
- You can explain any SUID or SGID binaries left in place.
- You have a cleanup or rotation plan for large and deleted-open files.

### Extension
- Audit secret file permissions and ownership under your service directories.
- Compare runtime writable paths with systemd ReadWritePaths or ProtectSystem rules.
- Track long-term growth rates of log and data directories.

## 5. Security posture audit

### Objective
Review the host for common security drift in packages, services, network exposure, and execution paths.

### Safety and setup
- Clarify whether this is a lightweight host audit or a formal hardening review.
- Collect package inventory and patch age if your distro tooling supports it.
- Know whether an EDR, vulnerability scanner, or policy agent already covers parts of the scope.
- Coordinate with security teams before disabling or modifying controls.
- Treat unknown binaries or startup paths as high priority until explained.

### Questions to answer
- Are there unexpected packages, kernels, or repositories enabled?
- Are any insecure services exposed or enabled unnecessarily?
- Do startup paths include unknown scripts, cron jobs, or timers?
- Are audit logs and security-relevant warnings present and retained?

### Runbook
```bash
crontab -l 2>/dev/null
systemctl list-timers --all
find /etc/cron* -type f 2>/dev/null | head -40
systemctl --failed
journalctl -p err -n 100
rpm -qa 2>/dev/null | head -40
dpkg -l 2>/dev/null | head -40
grep -R "PermitRootLogin\|PasswordAuthentication" /etc/ssh 2>/dev/null
```

### Interpretation guide
| Area | Healthy sign | Concern |
| --- | --- | --- |
| timers and cron | documented jobs only | unknown persistence path |
| packages | approved repos and versions | orphaned or custom binaries |
| failed units | none or understood | security agent disabled or crashing |
| journals | auth and kernel logs present | missing or rapidly truncated logs |

### What to look for
- Operational drift often looks like security drift and vice versa.
- Failed units matter even when unrelated to your main service because they may disable controls.
- Inventory tools differ by distro, so pick the native package manager first.
- Unknown scheduled tasks deserve immediate ownership clarification.
- Package review alone is not enough if binaries are dropped outside package management.

### Completion checklist
- You can explain every recurring scheduled job on the host.
- You know whether security-relevant logs exist and are being retained.
- You identified insecure auth settings or unexpected startup paths.
- You separated urgent remediations from informational findings.

### Extension
- Review auditd or equivalent event collection if installed.
- Compare package inventory with a golden image or baseline host.
- Audit container runtime sockets and permissions if the host runs containers.

## 6. Logs, retention, and recoverability

### Objective
Verify that logs are useful, retained long enough, and not silently consuming or exhausting storage.

### Safety and setup
- List the critical logs for auth, kernel, app, reverse proxy, and security tooling.
- Know which are handled by journald, plain files, or external agents.
- Record current disk and inode usage on log filesystems before deep inspection.
- Identify retention policy and log rotation ownership.
- Check whether compressed archives are stored locally or shipped elsewhere.

### Questions to answer
- Are logs present for the time range needed for incident response?
- Are rotation and retention configured sanely?
- Do any log files grow without bound or stay open after rotation?
- Are time synchronization and timestamps consistent across logs?

### Runbook
```bash
journalctl --disk-usage
journalctl -n 50
ls -lh /var/log | head -40
grep -R "rotate\|compress\|size\|daily\|weekly" /etc/logrotate.conf /etc/logrotate.d 2>/dev/null
find /var/log -type f -size +200M 2>/dev/null | head -40
lsof +L1 2>/dev/null | head -40
timedatectl status 2>/dev/null
chronyc tracking 2>/dev/null
```

### Interpretation guide
| Finding | Risk | Action |
| --- | --- | --- |
| journald uses large space | log partition pressure | tune retention caps |
| rotated file still open | space not reclaimed | restart or signal process |
| no auth logs retained | poor incident response | fix retention and forwarding |
| clock drift | misordered evidence | repair NTP and review timeline confidence |

### What to look for
- Logs are part of production readiness because outages without evidence are harder to recover from.
- Retention must be sized against actual incident discovery windows, not arbitrary defaults.
- Deleted-open logs are a recurring source of silent disk pressure.
- Time sync issues destroy correlation between hosts, traces, and packet captures.
- Review both file-based and journal-based paths; many systems use both.

### Completion checklist
- You know where key logs live and how long they remain available.
- You found no silent disk leaks from open deleted log files, or you documented them.
- You can prove time synchronization is trustworthy enough for incident timelines.
- You have clear remediation for missing or excessive retention.

### Extension
- Practice recovering a timeline using only preserved logs.
- Compare local retention with central log shipping guarantees.
- Audit journal rate limiting if high-volume services are present.

## 7. Kernel security settings and hardening review

### Objective
Check the kernel-level defaults that influence exploitation resistance and operational safety.

### Safety and setup
- Gather the current sysctl settings before comparing them with policy.
- Know whether the host role requires exceptions such as packet forwarding or ptrace access.
- Coordinate with security policy owners before proposing host-wide changes.
- Remember that some settings are namespaced while others are global.
- Treat compatibility risks seriously for older applications.

### Questions to answer
- Are ASLR, core dump handling, ptrace restrictions, and forwarding policies aligned with baseline?
- Are IP forwarding and reverse path filtering configured intentionally?
- Do kernel message exposure settings leak too much information to unprivileged users?
- Are unprivileged BPF or user namespaces restricted as required?

### Runbook
```bash
sysctl kernel.randomize_va_space
sysctl kernel.kptr_restrict
sysctl kernel.dmesg_restrict
sysctl fs.suid_dumpable
sysctl net.ipv4.conf.all.rp_filter
sysctl net.ipv4.ip_forward
sysctl kernel.unprivileged_bpf_disabled 2>/dev/null
sysctl kernel.unprivileged_userns_clone 2>/dev/null
```

### Interpretation guide
| Setting | Why it matters | Typical concern |
| --- | --- | --- |
| randomize_va_space | ASLR for exploit resistance | disabled without strong reason |
| kptr_restrict | kernel pointer exposure | too permissive on multi-user hosts |
| dmesg_restrict | kernel log exposure | info leak to unprivileged users |
| rp_filter | source validation | asymmetric routing edge cases |
| ip_forward | routing behavior | enabled unintentionally on non-router hosts |

### What to look for
- Kernel hardening must be reviewed in the context of the host role; routers and worker nodes differ.
- Some defaults vary by distro, so baseline from policy rather than memory.
- A hardening setting with no exception record is still drift even if it seems harmless.
- Operational tools may rely on settings like ptrace or user namespaces; review carefully.
- Document whether each deviation is required, temporary, or accidental.

### Completion checklist
- You can identify the key kernel security knobs and their current values.
- You know which deviations are justified by host role.
- You have a list of changes that need testing before rollout.
- You recorded the policy source used for comparison.

### Extension
- Audit seccomp, SELinux, or AppArmor state if used in your environment.
- Compare node hardening values with container runtime requirements.
- Add automated conformance checks for these sysctls.

## 8. Production readiness checklist

### Objective
Turn audit findings into a decision about whether the system is safe, supportable, and observable enough for production.

### Safety and setup
- Collect the findings from the earlier sections before scoring readiness.
- Group issues by severity, blast radius, and owner.
- Define what blocks production and what can be follow-up work.
- Include recovery and observability, not just security and performance.
- Seek sign-off from the service owner and platform owner when applicable.

### Questions to answer
- Can operators access the host safely during an incident?
- Are service limits, log retention, monitoring, and restart behavior adequate?
- Is the network exposure intentional and documented?
- Can the team recover from disk, memory, or process-failure scenarios on this host?

### Runbook
```bash
systemctl show <service> -p Restart -p LimitNOFILE -p MemoryMax -p CPUQuota
ss -tulpen
df -h && df -i
journalctl --disk-usage
sysctl fs.file-max vm.max_map_count
cat /proc/pressure/memory 2>/dev/null
systemctl --failed
uptime
```

### Interpretation guide
| Readiness area | Must be true | Example evidence |
| --- | --- | --- |
| access | approved admin path exists | sudo policy and SSH config |
| observability | logs and metrics retained | journal size and exporters |
| capacity | disk, inode, memory headroom | df and MemAvailable |
| recovery | service restarts and ownership clear | systemd policies and runbook |
| security | least privilege and hardened exposure | user audit and firewall review |

### What to look for
- Production readiness is a synthesis exercise; one strong area cannot compensate for several blind spots.
- A host can be performant and still unready because recovery paths are weak.
- Blocking findings should be phrased as risks, not just as missing settings.
- Each readiness call should end with ownership and due dates, not just a score.
- The best checklist is one your team can repeat quickly across many hosts.

### Completion checklist
- You can give a go, no-go, or conditional-go recommendation with evidence.
- Every critical finding has an owner and a remediation path.
- You can explain which gaps affect security, reliability, or operability.
- The checklist is clear enough that another engineer can repeat it.

### Extension
- Turn the manual checklist into an automated compliance job where possible.
- Compare readiness results across hosts in the same service tier.
- Review the checklist after the next incident and add any missing controls.

## 9. Audit output template

- Host role and owner:
- Critical findings:
- Medium findings:
- Acceptable exceptions:
- Immediate remediations:
- Follow-up owners and due dates:

