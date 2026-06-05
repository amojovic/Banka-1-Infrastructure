# Banka-1-Infrastructure

Kubernetes manifesti za deploy Banka 1 platforme na fakultetski klaster
(`banka-1.radenkovic.rs`). Sve resurse zive u namespace-u `banka-1`.

Deploy-ready varijanta zasnovana na klaster operatorima: **Crunchy PostgreSQL
operator** (jedan fizicki PG cluster, vise logickih baza) + **Envoy Gateway**
(path-based routing). Modelovano na Banka-2-Infrastructure.

## Arhitektura

Backend je Go monorepo (go.work) sa **8 aktivnih servisa** (Java `*-service/`
dirovi su mrtav izvor — NE deploy-uju se). Frontend je Angular SPA (nginx).

| Servis | HTTP port | gRPC | Logicka baza | Crunchy user / Secret | Probe path |
|--------|-----------|------|--------------|------------------------|------------|
| user-service | 8081 | — | `user_service` | `user-service` / `db-pguser-user-service` | `/actuator/health/{liveness,readiness}` |
| banking-core-service | 8084 | — | `banking_core` | `banking-core` / `db-pguser-banking-core` | `/actuator/health/{liveness,readiness}` |
| market-service | 8085 | 9085 | `market_service` | `market-service` / `db-pguser-market-service` | `/actuator/health/{liveness,readiness}` |
| trading-service | 8088 | 9088 | `trading` | `trading` / `db-pguser-trading` | `/actuator/health/{liveness,readiness}` |
| credit-service | 8089 | — | `credit_db` | `credit` / `db-pguser-credit` | `/health` |
| notification-service | 8006 | — | `notification_db` | `notification` / `db-pguser-notification` | `/health` |
| saga-orchestrator-service | 8095 | — | `saga_db` | `saga` / `db-pguser-saga` | `/health` |
| interbank-service | 8091 | 9091 | `interbank_service` | `interbank` / `db-pguser-interbank` | `/health` |
| frontend | 80 | — | — | — | `/healthz` |

> **Probe asimetrija (verifikovano u kodu, ne pretpostavka):** user/banking-core/
> market/trading koriste Spring-style `/actuator/health/*` (go-platform/health), dok
> credit/notification/saga/interbank serviraju bare `/health`. Pogresan path = 404 =
> CrashLoop, pa je per-servis tacno postavljen.

## Manifesti

| Fajl | Sadrzaj |
|------|---------|
| `00-namespace.yaml` | Namespace `banka-1` |
| `db.yaml` | Crunchy `PostgresCluster` (PG 17, 3 instance + pgBouncer + pgbackrest). 8 logickih baza, jedan non-superuser user po bazi |
| `redis.yaml` | Redis (market-service price cache) |
| `rabbitmq.yaml` | RabbitMQ broker (notif + saga.events) |
| `influxdb.yaml` | InfluxDB (OHLCV time-series; org `banka1`, bucket `market_data`) |
| `user-service.yaml` | user-service Deployment + Service (8081) |
| `banking-core-service.yaml` | banking-core Deployment + Service (8084) |
| `market-service.yaml` | market-service Deployment + Service (8085 + gRPC 9085) |
| `trading-service.yaml` | trading-service Deployment + Service (8088 + gRPC 9088) |
| `credit-service.yaml` | credit-service Deployment + Service (8089) |
| `notification-service.yaml` | notification-service Deployment + Service (8006) |
| `saga-orchestrator-service.yaml` | saga-orchestrator Deployment + Service (8095) |
| `interbank-service.yaml` | interbank-service Deployment + Service (8091 + gRPC 9091) |
| `frontend.yaml` | frontend Deployment + Service (80) + nginx ConfigMap |
| `route.yaml` | Envoy `HTTPRoute` — path routing za `banka-1.radenkovic.rs` (3 objekta zbog 16-rules/objekat limita) |
| `secrets.yaml.example` + `SECRETS.md` | Secret template + `kubectl create` recepti |

## Routing

`route.yaml` definise 3 `HTTPRoute` objekta na zajednickom parentRef-u
(`banka-gw` u `envoy-gateway-system`), hostname `banka-1.radenkovic.rs`. Envoy
kombinuje sva pravila po longest-prefix-match. Reprodukuje nginx api-gateway path mapu:

- **STRIP prefix** (URLRewrite → `/`): `/exchange`, `/stock` → market-service;
  `/order` → trading-service; `/credit` → credit-service.
- **Bez rewrite-a** (Go controlleri ocekuju bare path): sve ostalo — `/auth /employees
  /clients` → user; `/accounts /api/cards /transactions /transfers /verification
  /payment-recipients` → banking-core; `/stocks /price-alerts /watchlists` → market;
  16 trading prefiksa (`/orders /portfolio /tax /otc /options /funds /margin ...`);
  `/api/loans` → credit; `/notifications` → notification; `/saga` → saga; interbank.
- **Catch-all `/`** → frontend (SPA).

> **Inter-bank inbound asimetrija:** Banka 1 inbound je BARE (`/interbank`,
> `/public-stock`, `/negotiations`, `/user/{rn}/{id}` — bez `/api`), dok je Banka 2
> inbound pod `/api`. Tako Banka 2 stize do Banke 1 na bare putanjama; route.yaml ih
> rutira na interbank-service bez strip-a.

## Deploy

```bash
kubectl apply -f 00-namespace.yaml
# Secret-i PRE Deployment-a (vidi SECRETS.md):
kubectl apply -f secrets.yaml -n banka-1     # ili kubectl create secret ...
kubectl apply -f db.yaml -f redis.yaml -f rabbitmq.yaml -f influxdb.yaml
# Sacekaj da Crunchy cluster + db-pguser-* secret-i budu ready, pa:
kubectl apply -f user-service.yaml -f banking-core-service.yaml -f market-service.yaml \
  -f trading-service.yaml -f credit-service.yaml -f notification-service.yaml \
  -f saga-orchestrator-service.yaml -f interbank-service.yaml -f frontend.yaml
kubectl apply -f route.yaml
```

Deployment-i koriste `imagePullPolicy: Always` i povlace GHCR `:latest`, pa
`kubectl rollout restart deployment/<name> -n banka-1` povlaci najnoviji image.

> **Migracije/seed:** interbank/saga/credit/notification rade Goose / in-app migracije
> na startu (nema zaseban seed Job). user/banking-core/market/trading rade migracije
> u svom Go runtime-u; `LIQUIBASE_CONTEXTS=prod` drzi demo seed van prod baze.

## Tim

Banka 1, Racunarski fakultet 2025/26.
