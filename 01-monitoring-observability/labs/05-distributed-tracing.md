# Lab 05: Distributed Tracing with Tempo
Distributed tracing explains where time is spent across a request path. In this lab you will deploy Grafana Tempo, provision it into Grafana, run a three-service app, instrument Go and Python code, and correlate traces with metrics and logs.
## Objectives
- deploy Tempo into the `monitoring` namespace on a `kind` cluster
- receive spans by OTLP gRPC, OTLP HTTP, Jaeger, and Zipkin
- provision Grafana with a Tempo datasource YAML file
- run `frontend -> api-gateway -> backend`
- set `OTEL_EXPORTER_OTLP_ENDPOINT` on each service
- propagate W3C TraceContext headers end to end
- connect traces to metrics with exemplars
- connect traces to logs with Loki derived fields
- use TraceQL to find slow spans
## Lab architecture
```text
client -> frontend -> api-gateway -> backend
              \            |            /
               \-----------+-----------/
                           |
                           v
                         Tempo
                      /    |                         /     |                   Grafana  Prometheus  Loki
```
## Prerequisites
- working `kind` cluster
- Helm installed
- `monitoring` namespace from previous labs
- Grafana and Prometheus already running there
- optional Loki for Part 6
Quick checks:
```bash
kubectl config current-context
kubectl get nodes
kubectl get ns monitoring
kubectl get pods -n monitoring
helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true
helm repo update
```
## Part 1: Deploy Grafana Tempo via Helm
For a lab, the monolithic `grafana/tempo` chart is the simplest choice. The values below enable persistence, OTLP/Jaeger/Zipkin receivers, retention, and an object storage option.
### 1.1 Create `tempo-values.yaml`
```yaml
fullnameOverride: tempo
serviceAccount: {create: true}
persistence:
  enabled: true
  accessModes: [ReadWriteOnce]
  size: 20Gi
  storageClassName: standard
service: {type: ClusterIP}
resources:
  requests: {cpu: 200m, memory: 512Mi}
  limits: {cpu: "1", memory: 2Gi}
tempo:
  multitenancyEnabled: false
  reportingEnabled: false
  metricsGenerator: {enabled: true}
  storage:
    trace:
      backend: local
      local: {path: /var/tempo/traces}
      wal: {path: /var/tempo/wal}
      # Optional S3/MinIO object storage:
      # backend: s3
      # s3: {bucket: tempo-traces, endpoint: minio.monitoring.svc.cluster.local:9000, access_key: tempo, secret_key: tempo12345, insecure: true}
  retention: 24h
  receivers:
    otlp:
      protocols:
        grpc: {endpoint: 0.0.0.0:4317}
        http: {endpoint: 0.0.0.0:4318}
    jaeger:
      protocols:
        grpc: {endpoint: 0.0.0.0:14250}
        thrift_http: {endpoint: 0.0.0.0:14268}
        thrift_compact: {endpoint: 0.0.0.0:6831}
        thrift_binary: {endpoint: 0.0.0.0:6832}
    zipkin: {endpoint: 0.0.0.0:9411}
  ingester: {max_block_duration: 5m, trace_idle_period: 10s}
  compactor:
    compaction: {block_retention: 24h, compacted_block_retention: 1h}
  distributor:
    receivers:
      otlp: {protocols: {grpc: {}, http: {}}}
      jaeger: {protocols: {grpc: {}, thrift_http: {}, thrift_compact: {}, thrift_binary: {}}}
      zipkin: {}
  server: {http_listen_port: 3200}
  overrides:
    defaults:
      global: {max_bytes_per_trace: 5000000}
```
### 1.2 Install Tempo
```bash
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install tempo grafana/tempo -n monitoring -f tempo-values.yaml
kubectl get pods -n monitoring -l app.kubernetes.io/name=tempo
kubectl get svc -n monitoring tempo
kubectl get pvc -n monitoring
```
### 1.3 Verify endpoints and readiness
```bash
kubectl port-forward -n monitoring svc/tempo 3200:3200 4318:4318
curl -s http://127.0.0.1:3200/ready
curl -s http://127.0.0.1:3200/status/endpoints
kubectl logs -n monitoring deploy/tempo | tail -n 20
```
Expected ports are `3200`, `4317`, `4318`, `14250`, `14268`, `6831`, `6832`, and `9411`.
### 1.4 Key settings
| Setting | Purpose |
|---|---|
| `persistence.enabled` | keeps traces across pod restarts |
| `backend: local` | simple lab storage on PVC |
| `backend: s3` | production-style durable object storage |
| `otlp.grpc` and `otlp.http` | standard OTEL ingestion |
| `jaeger` | legacy Jaeger client support |
| `zipkin` | Zipkin client support |
| `retention` | trace lifecycle control |
| `metricsGenerator.enabled` | service graph and span metrics |
### 1.5 Object storage override example
```yaml
tempo:
  storage:
    trace:
      backend: s3
      s3:
        bucket: tempo-traces
        endpoint: minio.monitoring.svc.cluster.local:9000
        access_key: tempo
        secret_key: tempo12345
        insecure: true
```
```bash
helm upgrade --install tempo grafana/tempo -n monitoring -f tempo-values.yaml -f tempo-objectstore.yaml
```
## Part 2: Configure Grafana datasource for Tempo
Provisioning keeps the Tempo datasource reproducible.
### 2.1 Create `grafana-datasources-tempo.yaml`
```yaml
apiVersion: 1
datasources:
  - name: Tempo
    uid: tempo
    type: tempo
    access: proxy
    url: http://tempo.monitoring.svc.cluster.local:3200
    jsonData:
      tracesToLogsV2:
        datasourceUid: loki
        filterByTraceID: true
        filterBySpanID: true
        customQuery: true
        query: '{namespace="$${__span.tags.namespace}"} |= "$${__trace.traceId}"'
      tracesToMetrics:
        datasourceUid: prometheus
        spanStartTimeShift: -5m
        spanEndTimeShift: 5m
        tags:
          - key: service.name
            value: service
      serviceMap: {datasourceUid: prometheus}
      nodeGraph: {enabled: true}
```
### 2.2 Apply and verify
```bash
kubectl create configmap grafana-tempo-datasource -n monitoring --from-file=grafana-datasources-tempo.yaml --dry-run=client -o yaml | kubectl apply -f -
kubectl rollout restart deployment/grafana -n monitoring
kubectl logs -n monitoring deploy/grafana | grep -i tempo
```
Open Grafana and confirm `Tempo` appears in **Connections -> Data sources** and **Explore**.
## Part 3: Deploy a sample microservices app
Use any OTEL-enabled images you prefer. The YAML below assumes a simple public image per service. The important part is the trace endpoint and consistent propagation settings.
### 3.1 Create the namespace
```bash
kubectl create namespace tracing-lab --dry-run=client -o yaml | kubectl apply -f -
```
### 3.2 Apply `tracing-lab.yaml`
```yaml
apiVersion: apps/v1
kind: Deployment
metadata: {name: frontend, namespace: tracing-lab}
spec:
  selector: {matchLabels: {app: frontend}}
  template:
    metadata: {labels: {app: frontend}}
    spec:
      containers:
        - name: frontend
          image: ghcr.io/example-sre/otel-frontend:v1
          ports: [{containerPort: 8080}]
          env:
            - {name: API_GATEWAY_URL, value: http://api-gateway.tracing-lab.svc.cluster.local:8081}
            - {name: OTEL_SERVICE_NAME, value: frontend}
            - {name: OTEL_EXPORTER_OTLP_ENDPOINT, value: http://tempo.monitoring.svc.cluster.local:4317}
            - {name: OTEL_EXPORTER_OTLP_PROTOCOL, value: grpc}
            - {name: OTEL_PROPAGATORS, value: tracecontext,baggage}
---
apiVersion: v1
kind: Service
metadata: {name: frontend, namespace: tracing-lab}
spec: {selector: {app: frontend}, ports: [{name: http, port: 8080, targetPort: 8080}]}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: api-gateway, namespace: tracing-lab}
spec:
  selector: {matchLabels: {app: api-gateway}}
  template:
    metadata: {labels: {app: api-gateway}}
    spec:
      containers:
        - name: api-gateway
          image: ghcr.io/example-sre/otel-api-gateway:v1
          ports: [{containerPort: 8081}]
          env:
            - {name: BACKEND_URL, value: http://backend.tracing-lab.svc.cluster.local:8082}
            - {name: OTEL_SERVICE_NAME, value: api-gateway}
            - {name: OTEL_EXPORTER_OTLP_ENDPOINT, value: http://tempo.monitoring.svc.cluster.local:4317}
            - {name: OTEL_EXPORTER_OTLP_PROTOCOL, value: grpc}
            - {name: OTEL_PROPAGATORS, value: tracecontext,baggage}
---
apiVersion: v1
kind: Service
metadata: {name: api-gateway, namespace: tracing-lab}
spec: {selector: {app: api-gateway}, ports: [{name: http, port: 8081, targetPort: 8081}]}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: backend, namespace: tracing-lab}
spec:
  selector: {matchLabels: {app: backend}}
  template:
    metadata: {labels: {app: backend}}
    spec:
      containers:
        - name: backend
          image: ghcr.io/example-sre/otel-backend:v1
          ports: [{containerPort: 8082}]
          env:
            - {name: OTEL_SERVICE_NAME, value: backend}
            - {name: OTEL_EXPORTER_OTLP_ENDPOINT, value: http://tempo.monitoring.svc.cluster.local:4317}
            - {name: OTEL_EXPORTER_OTLP_PROTOCOL, value: grpc}
            - {name: OTEL_PROPAGATORS, value: tracecontext,baggage}
---
apiVersion: v1
kind: Service
metadata: {name: backend, namespace: tracing-lab}
spec: {selector: {app: backend}, ports: [{name: http, port: 8082, targetPort: 8082}]}
```
Apply and test:
```bash
kubectl apply -f tracing-lab.yaml
kubectl get pods -n tracing-lab
kubectl get svc -n tracing-lab
kubectl port-forward -n tracing-lab svc/frontend 8080:8080
for i in {1..20}; do curl -s http://127.0.0.1:8080/ >/dev/null; done
```
Then search Tempo for `service.name="frontend"`. If you want a faster demo instead, `jaegertracing/example-hotrod` is a valid alternative trace source.
## Part 4: Instrument application code
The critical concepts are exporter setup, stable `service.name`, and downstream context propagation.
### 4.1 Go example with `opentelemetry-go`
```go
package main
import (
  "context"; "net/http"; "os"
  "go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
  "go.opentelemetry.io/otel"
  "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
  "go.opentelemetry.io/otel/propagation"
  sdktrace "go.opentelemetry.io/otel/sdk/trace"
)
func initTracer(ctx context.Context) error {
  exp, err := otlptracegrpc.New(ctx, otlptracegrpc.WithEndpoint("tempo.monitoring.svc.cluster.local:4317"), otlptracegrpc.WithInsecure())
  if err != nil { return err }
  tp := sdktrace.NewTracerProvider(sdktrace.WithBatcher(exp))
  otel.SetTracerProvider(tp)
  otel.SetTextMapPropagator(propagation.TraceContext{})
  return nil
}
func main() {
  _ = initTracer(context.Background())
  c := http.Client{Transport: otelhttp.NewTransport(http.DefaultTransport)}
  http.Handle("/", otelhttp.NewHandler(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
    req, _ := http.NewRequestWithContext(r.Context(), http.MethodGet, os.Getenv("BACKEND_URL")+"/work", nil)
    _, _ = c.Do(req)
    w.Write([]byte("ok"))
  }), "gateway-root"))
  http.ListenAndServe(":8081", nil)
}
```
### 4.2 Python example with `opentelemetry-python`
```python
import os, requests
from flask import Flask
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.instrumentation.requests import RequestsInstrumentor
from opentelemetry.propagate import inject
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
provider = TracerProvider(resource=Resource.create({"service.name": "backend"}))
provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter(endpoint="http://tempo.monitoring.svc.cluster.local:4317", insecure=True)))
trace.set_tracer_provider(provider)
app = Flask(__name__); FlaskInstrumentor().instrument_app(app); RequestsInstrumentor().instrument()
@app.route("/work")
def work(): return {"status": "ok"}
@app.route("/call")
def call():
    headers = {}; inject(headers)
    return requests.get(os.environ["DOWNSTREAM_URL"], headers=headers, timeout=2).text
app.run(host="0.0.0.0", port=8082)
```
Install packages:
```bash
pip install flask requests opentelemetry-api opentelemetry-sdk opentelemetry-exporter-otlp-proto-grpc opentelemetry-instrumentation-flask opentelemetry-instrumentation-requests
```
### 4.3 W3C TraceContext propagation
`traceparent` is the key header:
```text
traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
```
It encodes version, trace ID, parent span ID, and trace flags.
Manual propagation test:
```bash
curl -H 'traceparent: 00-11111111111111111111111111111111-2222222222222222-01' http://frontend.tracing-lab.svc.cluster.local:8080/
```
If propagation is correct, the same trace ID appears across frontend, gateway, and backend spans.
## Part 5: Link traces to metrics with Exemplars
Exemplars let a metric sample point back to a trace.
### 5.1 Prometheus configuration
```yaml
global: {scrape_interval: 15s}
enable_features: [exemplar-storage]
storage:
  exemplars:
    max_exemplars: 100000
```
Restart Prometheus after changing the config:
```bash
kubectl rollout restart statefulset/prometheus-kube-prometheus-prometheus -n monitoring
kubectl logs -n monitoring statefulset/prometheus-kube-prometheus-prometheus | grep -i exemplar
```
### 5.2 PromQL queries that surface exemplars
```promql
histogram_quantile(0.95, sum by (le, service) (rate(http_server_request_duration_seconds_bucket{service="api-gateway"}[5m])))
```
```promql
sum by (service) (rate(http_server_request_duration_seconds_count[5m]))
```
```promql
sum by (service) (rate(http_server_request_duration_seconds_bucket{le="0.5"}[5m])) / sum by (service) (rate(http_server_request_duration_seconds_count[5m]))
```
### 5.3 Grafana dashboard config for exemplar dots
```json
{"type":"timeseries","title":"Gateway latency p95","datasource":{"type":"prometheus","uid":"prometheus"},"targets":[{"expr":"histogram_quantile(0.95, sum by (le) (rate(http_server_request_duration_seconds_bucket{service="api-gateway"}[5m])))","legendFormat":"p95"}]}
```
Use a time-series panel and enable exemplars in the panel editor.
## Part 6: Link traces to logs with Loki + Tempo correlation
A useful JSON log line includes the current trace ID:
```json
{"level":"error","service":"api-gateway","traceID":"4bf92f3577b34da6a3ce929d0e0e4736","msg":"downstream timeout"}
```
### 6.1 Loki datasource with derived fields
```yaml
apiVersion: 1
datasources:
  - name: Loki
    uid: loki
    type: loki
    access: proxy
    url: http://loki-gateway.monitoring.svc.cluster.local
    jsonData:
      derivedFields:
        - name: TraceID
          matcherRegex: 'traceID":"([a-f0-9]{32})"'
          datasourceUid: tempo
          url: '$${__value.raw}'
```
### 6.2 Demo flow
1. open Grafana Explore with Loki
2. run `{namespace="tracing-lab", app="api-gateway"} |= "traceID"`
3. click the derived field value
4. Grafana opens Tempo with that trace
Do not index `trace_id` as a Loki label in production; it is too high-cardinality.
## Part 7: Trace-based alerting
TraceQL is excellent for investigation and for turning slow-span patterns into alert ideas.
### 7.1 Example TraceQL queries
```traceql
{ resource.service.name = "api-gateway" }
```
```traceql
{ resource.service.name = "api-gateway" && duration > 1s }
```
```traceql
{ resource.service.name = "backend" && status = error }
```
```traceql
{ span.http.target = "/checkout" }
```
```traceql
{ resource.service.name = "frontend" } && { resource.service.name = "api-gateway" && duration > 2s }
```
### 7.2 Metric alert idea from span metrics
```promql
histogram_quantile(0.95, sum by (le) (rate(traces_spanmetrics_latency_bucket{service="api-gateway",span_name="GET /checkout"}[5m]))) > 1.5
```
Workflow: detect with metrics, investigate with TraceQL, pivot to logs for error detail.
## Verification checklist
- [ ] `kind` cluster is reachable and `monitoring` exists
- [ ] Grafana and Prometheus are healthy
- [ ] Tempo pod is Ready and PVC is Bound
- [ ] Tempo exposes query, OTLP, Jaeger, and Zipkin ports
- [ ] Grafana shows Tempo as a datasource
- [ ] TraceQL works in Explore
- [ ] `tracing-lab` namespace exists
- [ ] frontend, gateway, and backend pods are Ready
- [ ] all deployments set `OTEL_EXPORTER_OTLP_ENDPOINT`
- [ ] test traffic creates traces in Tempo
- [ ] trace IDs remain consistent across services
- [ ] Prometheus exemplar storage is enabled
- [ ] latency charts show exemplar dots
- [ ] clicking an exemplar opens Tempo
- [ ] Loki logs include trace IDs
- [ ] clicking a log-derived trace ID opens Tempo
## Troubleshooting
### No traces appear
Check `OTEL_EXPORTER_OTLP_ENDPOINT`, exporter protocol, and TLS mode.
```bash
kubectl logs -n tracing-lab deploy/frontend | grep -i otlp
kubectl logs -n monitoring deploy/tempo | grep -Ei 'receiver|error|otlp'
```
### Traces are incomplete
Look for dropped spans, missing graceful shutdown, or per-trace size limits.
### Queries are empty
Check Grafana time range and Tempo retention.
### Logs do not open traces
Fix the Grafana derived-field regex to match the real log format.
### Exemplars are missing
Enable exemplar storage and use histogram metrics with a compatible Grafana panel.
### Service graph is empty
Enable metrics generation and set `service.name` correctly.
## Advanced challenge: deploy OpenTelemetry Collector as a sidecar
Direct export is fine for a lab, but a sidecar collector adds batching, retries, processors, and easier fan-out.
### Sidecar ConfigMap
```yaml
apiVersion: v1
kind: ConfigMap
metadata: {name: otel-sidecar-config, namespace: tracing-lab}
data:
  collector.yaml: |
    receivers:
      otlp:
        protocols:
          grpc: {}
          http: {}
    processors:
      batch: {}
      memory_limiter: {check_interval: 1s, limit_mib: 256}
    exporters:
      otlp:
        endpoint: tempo.monitoring.svc.cluster.local:4317
        tls: {insecure: true}
    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [memory_limiter, batch]
          exporters: [otlp]
```
### Sidecar pod snippet
```yaml
spec:
  containers:
    - name: app
      env:
        - {name: OTEL_EXPORTER_OTLP_ENDPOINT, value: http://127.0.0.1:4317}
    - name: otel-collector
      image: otel/opentelemetry-collector:0.104.0
      args: ["--config=/conf/collector.yaml"]
      volumeMounts:
        - {name: otel-config, mountPath: /conf}
  volumes:
    - name: otel-config
      configMap: {name: otel-sidecar-config}
```
### Challenge tasks
- add a `cluster=kind` attribute processor
- simulate a short Tempo outage and observe retries
- add a second exporter to fan out traces
- compare direct export versus sidecar export overhead
## Cleanup
```bash
kubectl delete namespace tracing-lab --ignore-not-found
helm uninstall tempo -n monitoring
kubectl delete configmap grafana-tempo-datasource -n monitoring --ignore-not-found
```
Metrics tell you something is wrong, logs explain nearby events, and traces connect the path across services.
