# Lab 02: Network Debugging

This lab is organized from L1 through L7 so you avoid skipping directly to the wrong layer.
Each exercise assumes you can reproduce at least one failing flow or one slow request.

## Guiding principle

- Start cheap: addresses, routes, sockets, counters.
- Add captures only when you need proof of packet behavior.
- Test with the real hostname, SNI, and port used by the application.
- Document the tuple and the namespace before running any command.
- Separate timeout, refusal, reset, TLS alert, and HTTP error in your notes.

## 1. Layer 1 to Layer 3 baseline

### Objective
Start at the bottom of the stack so later L4 to L7 symptoms have a grounded explanation.

### Safety and setup
- Pick a source host, a target host, and one interface path you care about.
- Confirm whether the path is plain Ethernet, VLAN, bond, overlay, or cloud virtual network.
- Write down the expected source IP, target IP, gateway, and DNS resolver.
- If the workload is containerized, identify the pod or namespace before you begin.
- Know whether ICMP is allowed; lack of ping does not always mean path failure.

### Questions to answer
- Is the interface up, error-free, and using the expected MTU?
- Does the host choose the route you expect?
- Is neighbor discovery or ARP failing?
- Is the problem local to one namespace or visible on the host too?

### Runbook
```bash
ip -br addr
ip -s link
ip route
ip route get <target-ip>
ip neigh show
ping -c 3 <gateway-or-target>
tracepath <target-ip>
ethtool <iface>
```

### Interpretation guide
| Signal | Interpretation | Next step |
| --- | --- | --- |
| RX or TX errors | local interface or driver issue | inspect ethtool stats and cabling or vNIC health |
| wrong route selected | policy route or table issue | check ip rule and source address |
| FAILED neighbor entry | ARP or ND problem | verify L2 reachability and VLAN placement |
| tracepath MTU drop | path MTU issue | test DF packets or clamp MSS |

### What to look for
- A healthy interface with a bad route is not a network stack mystery; it is a control-plane issue.
- Cloud and overlay environments often hide L2, so route and neighbor tools matter more than classic switch assumptions.
- If only one namespace fails, enter that namespace before collecting more evidence.
- MTU mismatches often show up as hangs on larger payloads while tiny pings still work.
- The chosen source IP can change firewall and policy outcomes dramatically.

### Completion checklist
- You can identify the exact egress interface and next hop for the flow.
- You can state whether the fault is below TCP or above it.
- You captured at least one counter set before making any changes.
- You know whether the problem is host-specific or namespace-specific.

### Extension
- Repeat the test with a container or pod network namespace.
- Change MTU in a lab overlay and observe tracepath behavior.
- Compare route selection before and after adding policy rules.

## 2. TCP debugging with sockets, backlogs, and retransmits

### Objective
Map connection failures and slowness to concrete TCP states and queue behavior.

### Safety and setup
- Choose one known TCP service and one client that can repeat requests.
- Confirm whether you are debugging a server-side or client-side symptom.
- Know the expected port, TLS requirement, and idle timeout policy.
- If the server is behind a load balancer, note where source IP preservation changes.
- Keep packet capture as a later step unless the cheaper tools are inconclusive.

### Questions to answer
- Are connections stuck in SYN-SENT, SYN-RECV, or CLOSE-WAIT?
- Is the accept queue overflowing?
- Are retransmits or resets growing?
- Is the application reading and writing fast enough to drain socket queues?

### Runbook
```bash
ss -lnt
ss -tan state all | head -60
ss -tinm dst <target-ip>
nstat -az | egrep "Listen|Retrans|Reset|Timeout"
nc -vz <host> <port>
curl -vk --connect-timeout 3 https://<host>:<port>/health
cat /proc/net/netstat | egrep "ListenOverflows|ListenDrops"
sysctl net.core.somaxconn net.ipv4.tcp_max_syn_backlog
```

### Interpretation guide
| Pattern | Likely cause | Action |
| --- | --- | --- |
| SYN-SENT grows | path or firewall drop | test route and packet capture |
| SYN-RECV grows | server backlog or return-path issue | inspect listen queue and SYN cookies |
| CLOSE-WAIT grows | app not closing sockets | inspect server handlers |
| Recv-Q high on ESTAB | app is slow to read | profile server or downstream dependency |
| Send-Q high on ESTAB | peer slow or path unhealthy | check retransmits and RTT |

### What to look for
- TCP states are the shortest path from symptom to likely subsystem.
- Listen queue overflow is easy to miss unless you check kernel counters and backlog settings.
- A connection can succeed at the TCP layer while the application still fails on TLS or HTTP.
- Retries in clients can mask short outages while multiplying pressure on the server.
- Backlog tuning does not help if the application thread pool is frozen or out of file descriptors.

### Completion checklist
- You can name the dominant TCP state and why it matters.
- You know whether the next action is app-side, network-side, or kernel-side.
- You collected both counter-based and socket-level evidence.
- You can explain why a timeout differs from a reset or a refusal.

### Extension
- Intentionally reduce backlog in a lab and watch ListenDrops rise.
- Create a CLOSE-WAIT leak with a simple test server that forgets to close.
- Compare nc, curl, and a raw TCP client against the same service.

## 3. DNS debugging from resolver to authority

### Objective
Prove where name resolution fails: local stub, recursive resolver, delegation, or application behavior.

### Safety and setup
- Choose one hostname that should work and one that should fail in a known way.
- Capture the resolver IPs from /etc/resolv.conf or resolvectl first.
- If running in Kubernetes, note search domains and ndots behavior.
- Decide whether the app uses libc, systemd-resolved, or a language-specific resolver.
- Keep response TTLs in your notes because caches affect repeated tests.

### Questions to answer
- Does getent agree with dig?
- Is the issue only with A, AAAA, or SRV lookups?
- Does dig +trace expose an authoritative delegation problem?
- Are search domains causing unexpected lookups or delays?

### Runbook
```bash
cat /etc/resolv.conf
getent hosts example.com
dig example.com A +short
dig example.com AAAA +short
dig @<resolver-ip> example.com
dig +trace example.com
time getent hosts example.com
resolvectl status
```

### Interpretation guide
| Result | Likely meaning | Next step |
| --- | --- | --- |
| getent slow, dig fast | stub or libc path issue | inspect nsswitch and local resolver |
| dig @resolver fails, +trace works | recursive resolver issue | inspect resolver health |
| A works, AAAA hangs | IPv6 path or policy issue | test dual-stack connect path |
| only short name fails | search domain or ndots issue | use FQDN and review search list |

### What to look for
- Resolution success is not enough; latency and TTL behavior also matter.
- Search domain mistakes are especially common in Kubernetes and enterprise networks.
- Negative caching can make recovered records appear still broken for a while.
- Applications with their own DNS cache may continue failing after the system resolver recovers.
- A resolver outage can look like application connection timeouts rather than explicit DNS errors.

### Completion checklist
- You can identify which resolver path the application actually uses.
- You can say whether the issue is authoritative, recursive, or local.
- You recorded TTLs and response codes during the incident.
- You have one safe workaround such as a hosts entry or alternate resolver for a lab only.

### Extension
- Repeat with reverse lookup and compare the effect on logs or auth flows.
- Test a pod using cluster DNS and compare with the node resolver.
- Simulate ndots-related query storms in a lab and observe latency.

## 4. HTTP and HTTPS debugging above a healthy TCP session

### Objective
Separate transport success from protocol failure at HTTP or TLS layers.

### Safety and setup
- Choose one URL that should return quickly and include the exact scheme, host, and path.
- Know whether proxies, service meshes, or ingress controllers sit between client and server.
- Record expected status code, headers, and authentication requirements.
- If HTTPS is involved, know the intended certificate name and trust store.
- Disable client-side retries in a lab if you need cleaner symptoms.

### Questions to answer
- Is the failure before TLS, during TLS, or after HTTP request dispatch?
- Does SNI or Host header routing affect the result?
- Are redirects, proxies, or auth middleware changing the path unexpectedly?
- Is the issue on one method, one path, or every request?

### Runbook
```bash
curl -v http://<host>:<port>/health
curl -vkI https://<host>/health
curl -vk --resolve example.com:443:<ip> https://example.com/health
openssl s_client -connect <host>:443 -servername <host> </dev/null
openssl x509 -noout -dates -subject -issuer -in cert.pem
nghttp -nv https://example.com/health
date -u
grep -i "ssl\|tls\|handshake" ./app.log 2>/dev/null | tail -20
```

### Interpretation guide
| Symptom | Layer | Next step |
| --- | --- | --- |
| connection refused | TCP listener absent | inspect bind and firewall |
| TLS alert | handshake policy | check cert, SNI, protocol version |
| HTTP 301 or 302 loop | application or proxy config | inspect Host and X-Forwarded headers |
| HTTP 503 | upstream unavailable or overload | trace request path through proxies |
| works with --resolve only | DNS or load balancer issue | inspect DNS and VIP routing |

### What to look for
- curl -v gives phase-by-phase clues: DNS, connect, TLS, headers, and body.
- SNI and Host header mistakes can make the same IP behave differently for different names.
- Time skew breaks TLS in ways that look like app outages.
- HTTP errors may be generated by proxies rather than the origin service.
- Record exact status code and response headers because generic dashboards often hide them.

### Completion checklist
- You can say which layer first failed and which layer remained healthy.
- You know whether the response came from the app, a proxy, or a load balancer.
- You can reproduce the error with a single deterministic command.
- You preserved the cert chain or verbose output if TLS was involved.

### Extension
- Compare HTTP/1.1 and HTTP/2 behavior if the service supports ALPN.
- Break a certificate chain intentionally in a lab and compare client errors.
- Add proxy headers one by one to see how routing changes.

## 5. Packet capture and evidence hygiene

### Objective
Use tcpdump surgically so packets answer a precise question instead of generating noise.

### Safety and setup
- Know the namespace and interface where the packet should appear.
- Define the narrowest host, port, and protocol filter that still captures the symptom.
- Synchronize time between systems if you plan to compare captures.
- Use a short capture window around a known reproduction if possible.
- Avoid collecting sensitive payloads unless policy and scope explicitly allow it.

### Questions to answer
- Did the packet leave the source host?
- Did it arrive at the target host?
- Was there a reply, retransmit, reset, or ICMP error?
- Do offload features make the capture look larger or smaller than wire reality?

### Runbook
```bash
tcpdump -ni any host <target-ip> and port <port>
tcpdump -ni <iface> -c 100 tcp and host <target-ip>
tcpdump -ni any "icmp or icmp6"
tcpdump -nnvvXSs 0 -ni <iface> host <target-ip> and tcp port <port>
ethtool -k <iface>
ss -tinm
date
echo "Reproduce one request now"
```

### Interpretation guide
| Capture result | Interpretation | Next step |
| --- | --- | --- |
| outbound SYN only | packet left but no reply | investigate path or remote side |
| SYN and RST back | listener absent or firewall reject | check target service |
| full handshake, no app data | stall above TCP | inspect TLS or app logs |
| retransmits only | loss or delayed ACK path issue | compare both ends if possible |

### What to look for
- Packet capture is strongest when paired with a single known request ID or timestamp.
- Capturing on any can hide interface-specific behavior such as missing VLAN tags.
- Checksum offload can make outbound packets look invalid in captures taken before NIC correction.
- pcap files are evidence; name them clearly and note the filter used.
- A short, focused capture is usually more useful than a long generic one.

### Completion checklist
- You can explain why you chose that interface and filter.
- You can align packet timestamps with application or proxy logs.
- You saw either proof of loss, proof of refusal, or proof that the issue sits above TCP.
- You kept the capture narrow enough to review quickly.

### Extension
- Capture from both client and server in a lab to compare sequence and timing.
- Observe how GRO or TSO change what the host capture shows.
- Add ICMP filters to catch fragmentation-needed or unreachable responses.

## 6. Firewall and policy debugging

### Objective
Track a blocked flow across host rules, cloud policy, and container policy.

### Safety and setup
- Document the full tuple: source IP, source port range, destination IP, destination port, and protocol.
- Identify every policy layer between endpoints before touching rules.
- Collect current packet counters before reproducing the problem.
- Know whether NAT changes the tuple mid-path.
- Prefer read-only inspection until you are sure where the packet is blocked.

### Questions to answer
- Is the packet dropped or explicitly rejected?
- Which rule counter increases when the flow is attempted?
- Does conntrack state make established traffic pass while new traffic fails?
- Is the problem on ingress, egress, or forwarding path?

### Runbook
```bash
nft list ruleset
iptables -L -n -v --line-numbers
iptables -t nat -L -n -v --line-numbers
conntrack -S
conntrack -L | head -40
ip rule show
kubectl get networkpolicy -A
kubectl describe networkpolicy <name> -n <ns>
```

### Interpretation guide
| Observation | Meaning | Response |
| --- | --- | --- |
| DROP counter rises | rule matched silently | confirm rule intent and tuple |
| REJECT seen by client | host actively refused | narrow to host or policy engine |
| no host rule hit | blocked upstream or wrong path | inspect cloud or router policy |
| conntrack full | stateful policy breakdown | raise limit or reduce churn with care |

### What to look for
- Packet counters are often faster and safer than changing rules experimentally.
- A successful ping does not validate the TCP or UDP policy for the real service.
- Kubernetes policy may allow pod-to-pod but not pod-to-external or vice versa.
- NAT can make the tuple you debug differ from the tuple the firewall actually sees.
- One blocked dependency can make an entire service appear down.

### Completion checklist
- You can point to the exact layer blocking the flow.
- You know whether the fix is a rule change, a route change, or a service bind change.
- You preserved rule counters before and after the test.
- You can explain why the client saw timeout, refusal, or unreachable.

### Extension
- Add a temporary log-only rule in a lab and compare the evidence quality.
- Observe how conntrack timeouts influence long-lived idle connections.
- Compare nftables and iptables output on a mixed-compat system.

## 7. Network performance testing with latency and throughput context

### Objective
Measure network capacity without confusing bandwidth tests with application health.

### Safety and setup
- Use iperf3 or a similar tool only on hosts where you are allowed to generate test traffic.
- Record link speed, MTU, RTT, and whether TLS or proxies normally sit in the path.
- Run tests in both directions because asymmetry is common.
- Measure latency during throughput tests so you can see queueing side effects.
- Avoid saturating shared production links with synthetic traffic.

### Questions to answer
- Is throughput limited by RTT, TCP windowing, CPU, or packet loss?
- Does bandwidth testing inflate latency for real traffic?
- Do multiple parallel streams improve throughput, implying a per-flow bottleneck?
- Is the host or the path the limiting factor?

### Runbook
```bash
iperf3 -s
iperf3 -c <server> -t 30
iperf3 -c <server> -P 4 -t 30
ping -c 20 <server>
ss -tinm
nstat -az | egrep "Retrans|Timeout"
mpstat -P ALL 1 10
ethtool <iface>
```

### Interpretation guide
| Result | Likely cause | Next action |
| --- | --- | --- |
| single stream slow, multi stream good | window or per-flow limitation | check BDP and socket buffers |
| throughput fine, latency spikes | queueing under load | inspect qdisc and bufferbloat |
| throughput low and CPU high | host CPU bottleneck | inspect softirq and copy costs |
| retransmits rise during test | loss path issue | inspect interface and network errors |

### What to look for
- A fast iperf result does not guarantee application success through proxies, TLS, or auth layers.
- RTT and packet loss shape TCP far more than raw link speed alone.
- Parallel stream gains often indicate per-flow constraints rather than total path capacity.
- Look at CPU and softirq time during tests because packet processing itself can bottleneck.
- Always state test direction and stream count when sharing results.

### Completion checklist
- You can explain whether the limit is host, flow, or path related.
- You measured latency as well as throughput.
- You know whether more streams help and why.
- You can connect the synthetic result back to application relevance.

### Extension
- Repeat with TLS-enabled application traffic and compare the bottleneck.
- Change socket buffer settings in a lab and re-run the same test.
- Measure qdisc latency with tc in a controlled environment.

## 8. Container and Kubernetes network debugging

### Objective
Translate host networking skills into pods, services, CNIs, and overlay paths.

### Safety and setup
- Identify the pod, node, namespace, service, and CNI plugin involved.
- Know whether traffic is pod-to-pod, pod-to-service, pod-to-external, or ingress-to-pod.
- Collect both Kubernetes objects and node-level Linux evidence.
- Enter the pod network namespace only when necessary; sometimes node-level data is enough.
- Map the veth pair or overlay interface before capturing packets.

### Questions to answer
- Does the pod have the expected IP, route, and DNS config?
- Is kube-proxy, CNI, or NetworkPolicy altering the path?
- Does the problem reproduce from the node but not from the pod, or vice versa?
- Are service endpoints healthy and reachable?

### Runbook
```bash
kubectl get pod -o wide -n <ns>
kubectl describe pod <pod> -n <ns>
kubectl exec -n <ns> <pod> -- ip addr
kubectl exec -n <ns> <pod> -- ip route
kubectl exec -n <ns> <pod> -- cat /etc/resolv.conf
kubectl get svc,endpoints,endpointslice -n <ns>
kubectl get networkpolicy -A
ip netns identify <pid>
```

### Interpretation guide
| Symptom | Likely layer | Action |
| --- | --- | --- |
| pod cannot resolve service | cluster DNS or ndots | inspect CoreDNS and resolv.conf |
| service IP works from node not pod | NetworkPolicy or CNI path | inspect pod namespace and policy |
| pod to external fails only | SNAT or egress policy | inspect node NAT and route |
| endpoint ready false | app not healthy despite network | inspect readiness and container logs |

### What to look for
- Cluster networking adds abstraction layers but still ends in Linux routes, veth pairs, and netfilter.
- Service debugging must include endpoint selection; a healthy VIP with zero healthy backends still fails.
- CoreDNS issues often masquerade as generic app timeouts.
- A node-local packet capture can be easier than capturing inside a minimal container image.
- Always record the node name because pod placement changes the path.

### Completion checklist
- You can draw the packet path from pod to destination.
- You know which Kubernetes object and which Linux primitive correspond to the failure.
- You collected evidence from both cluster and node layers.
- You can explain whether the fix belongs to the app, CNI, DNS, or policy layer.

### Extension
- Compare overlay and hostNetwork pods in the same cluster.
- Delete one endpoint in a lab and observe how service behavior changes.
- Trace a pod-to-service connection with tcpdump on the veth and node interface.

## 9. Wrap-up checklist

- [ ] I can isolate a failure to L1-L3, L4, TLS, HTTP, or policy layers.
- [ ] I know when ss and nstat are enough and when tcpdump is necessary.
- [ ] I can prove whether DNS, SNI, or the Host header is the true problem.
- [ ] I can debug one pod networking issue without guessing how Kubernetes works internally.
- [ ] I preserve packet capture filters, timestamps, and interfaces with every piece of evidence.

