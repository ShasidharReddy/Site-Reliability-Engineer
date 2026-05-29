# Lab 05: Distributed Tracing with Tempo

## Deploy Tempo
```bash
helm upgrade --install tempo grafana/tempo \
  --namespace monitoring \
  --set tempo.storage.trace.backend=local \
  --set tempo.storage.trace.local.path=/var/tempo/traces
```

## Configure OTLP Receiver (tempo-values.yaml)
```yaml
tempo:
  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: 0.0.0.0:4317
        http:
          endpoint: 0.0.0.0:4318
```

## Instrument Application (Go)
```go
exporter, _ := otlptracegrpc.New(ctx,
    otlptracegrpc.WithEndpoint("tempo.monitoring.svc:4317"),
    otlptracegrpc.WithInsecure(),
)
tp := sdktrace.NewTracerProvider(
    sdktrace.WithBatcher(exporter),
    sdktrace.WithResource(resource.NewWithAttributes(
        semconv.SchemaURL,
        semconv.ServiceNameKey.String("my-service"),
    )),
)
otel.SetTracerProvider(tp)
```

## Enable Exemplars in Prometheus
```yaml
# prometheus.yaml
feature_flags:
  - exemplar-storage
storage:
  exemplars:
    max_exemplars: 100000
```

## Verification
- [ ] Tempo running in monitoring namespace
- [ ] App sending traces (visible in Grafana Explore -> Tempo)
- [ ] Exemplar dots on histogram panels in Grafana
- [ ] Click exemplar -> opens trace in Tempo
