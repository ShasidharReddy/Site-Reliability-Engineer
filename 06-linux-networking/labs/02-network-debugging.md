# Lab 02: Network Debugging

## Layer 3 (IP)
```bash
ping -c3 <target>
ip route get <target-ip>
traceroute <target>
```

## Layer 4 (TCP)
```bash
nc -zv <host> <port>
timeout 5 bash -c "echo > /dev/tcp/<host>/<port>" && echo open || echo closed
openssl s_client -connect <host>:443 </dev/null 2>&1 | grep -E "subject|issuer|verify"
curl -v -o /dev/null https://<host>/health 2>&1 | grep -E "HTTP|Connected|certificate"
```

## DNS
```bash
nslookup <hostname>; dig <hostname>
dig @8.8.8.8 <hostname>
dig +trace <hostname>
dig -x <ip>        # Reverse lookup
time dig <hostname> # Measure latency
cat /etc/resolv.conf
```

## TLS
```bash
echo | openssl s_client -connect <host>:443 2>/dev/null | openssl x509 -noout -dates
openssl s_client -showcerts -connect <host>:443 </dev/null 2>&1
```

## iptables
```bash
iptables -L -n -v --line-numbers
iptables -L INPUT -n | grep <port>
nft list ruleset    # newer distros
```

## Verification
- [ ] nc confirms port reachable
- [ ] dig returns correct IP
- [ ] TLS cert valid and not expired
- [ ] traceroute shows path
