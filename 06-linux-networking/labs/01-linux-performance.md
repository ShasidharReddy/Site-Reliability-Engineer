# Lab 01: Linux Performance Troubleshooting

## CPU
```bash
uptime; nproc; top; vmstat 1 5; mpstat -P ALL 1 3
ps aux --sort=-%cpu | head -10
pidstat -u 1 5
```
- Load > nproc: CPU/IO bound
- high %wa: IO wait
- high %us: user-space CPU

## Memory
```bash
free -h; vmstat -s
dmesg | grep -i "out of memory" | tail -10
journalctl -k | grep -i oom | tail -20
```

## Disk IO
```bash
iostat -x 1 5       # %util, await per device
iotop -a            # IO per process
df -h; df -i        # Disk space and inodes
lsof +L1            # Deleted-but-open files eating disk
```

## Network
```bash
ss -tuln; ss -s
netstat -i          # Interface errors
ip -s link
mtr --report 8.8.8.8
ss -an | grep TIME_WAIT | wc -l
```

## Verification
- [ ] Load average vs nproc understood
- [ ] OOM check in dmesg
- [ ] High IO process found with iotop
- [ ] Deleted-file disk space found with lsof +L1
