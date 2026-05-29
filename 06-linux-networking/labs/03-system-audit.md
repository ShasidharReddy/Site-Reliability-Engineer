# Lab 03: System Audit for SRE

## User Audit
```bash
cat /etc/passwd | grep -v nologin | grep -v false
cat /etc/sudoers; ls /etc/sudoers.d/
last | head -20
lastlog | grep -v Never
grep "Failed password" /var/log/auth.log | tail -20
```

## Listening Services
```bash
ss -tlunp
ss -tlunp | grep -v -E "(22|443|80|9090|3000)"
```

## Process Audit
```bash
ps aux | awk '$1=="root" {print $1, $11}' | head -20
find / -perm /4000 2>/dev/null | grep -v proc   # SUID files
find /etc -perm -002 -type f 2>/dev/null         # World-writable
find /etc /usr/bin -mtime -1 -type f 2>/dev/null # Recently modified
```

## Baseline and Drift Detection
```bash
ss -tlunp > /tmp/ports-baseline.txt
ps aux > /tmp/process-baseline.txt
dpkg -l > /tmp/packages-baseline.txt

# Compare later
diff /tmp/ports-baseline.txt <(ss -tlunp)
```

## Verification
- [ ] No unexpected listening ports
- [ ] Login history reviewed
- [ ] SUID files audited
- [ ] Baseline saved
