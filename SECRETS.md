# Banka-1 Infrastructure — Secrets & Security (namespace `banka-1`)

Sve tajne su izdvojene iz Deployment manifesta u K8s `Secret` resurse. Deployment-i
ih citaju preko `valueFrom.secretKeyRef`. Secret-i MORAJU postojati u klasteru PRE
Deployment-a (bez njih pod ne startuje — env var se ne resolve-uje).

Template: [`secrets.yaml.example`](./secrets.yaml.example).

---

## 1. Secret-i koje deploy-er kreira

| Secret | Kljucevi | Cita ga |
|--------|----------|---------|
| `app-secrets` | `JWT_SECRET`, `ALPHA_VANTAGE_API_KEY`, `TWELVE_DATA_API_KEY` | svi servisi (JWT) + market-service (feed kljucevi) |
| `interbank-partners` | `INTERBANK_PARTNERS_JSON` | interbank-service |
| `rabbitmq-credentials` | `RABBITMQ_DEFAULT_USER`, `RABBITMQ_DEFAULT_PASS` | rabbitmq + svi producer/consumer servisi |
| `influxdb-credentials` | `INFLUX_ADMIN_USERNAME`, `INFLUX_ADMIN_PASSWORD`, `INFLUX_ADMIN_TOKEN` | influxdb + market-service (write token) |
| `mail-credentials` | `MAIL_USERNAME`, `MAIL_PASSWORD` | notification-service |

> **DB lozinke (Crunchy):** NISU ovde. PostgreSQL operator ih auto-generise u
> Secret-e `db-pguser-<user>` (`user-service`, `banking-core`, `market-service`,
> `trading`, `credit`, `notification`, `saga`, `interbank`). Deployment-i ih citaju
> preko `secretKeyRef` (keys `user` / `password`).

---

## 2. Deploy workflow — `kubectl create secret` (preporuceno; vrednosti ne diraju disk)

```bash
# app-secrets — JWT (deljen kroz sve servise) + market feed kljucevi.
# JWT_SECRET MORA biti ne-dev i ne-prazan (saga/interbank PROFILE=prod fail-fast-uju).
kubectl create secret generic app-secrets \
  --from-literal=JWT_SECRET="$(openssl rand -base64 64)" \
  --from-literal=ALPHA_VANTAGE_API_KEY="" \
  --from-literal=TWELVE_DATA_API_KEY="" \
  -n banka-1

# interbank-partners — registar partnerskih banaka (Banka 2 / routing 222).
# INTERBANK_PARTNERS_JSON je JEDINI env koji loader cita za partnere.
# InboundToken  = sto Banka 1 ocekuje na pozivima OD Banke 2 (= sto Banka 2 salje).
# OutboundToken = sto Banka 1 salje kad zove Banku 2.
# BaseURL = https://banka-2.radenkovic.rs/api  (Banka 2 inbound je POD /api).
# NAPOMENA: REPLACE_ME-* su placeholder-i — prave 64-hex token vrednosti i tacan
# smer (koji je inbound a koji outbound) drzi interni deploy dokument; NE commit-uj
# realne tokene u ovaj repo.
kubectl create secret generic interbank-partners \
  --from-literal=INTERBANK_PARTNERS_JSON='[{"Routing":222,"DisplayName":"Banka 2","BaseURL":"https://banka-2.radenkovic.rs/api","InboundToken":"REPLACE_ME-interbank-inbound-token-64hex","OutboundToken":"REPLACE_ME-interbank-outbound-token-64hex"}]' \
  -n banka-1

# rabbitmq-credentials
kubectl create secret generic rabbitmq-credentials \
  --from-literal=RABBITMQ_DEFAULT_USER="banka1" \
  --from-literal=RABBITMQ_DEFAULT_PASS="$(openssl rand -hex 16)" \
  -n banka-1

# influxdb-credentials  (token MORA biti min 32 bajta; ista vrednost = market write token)
kubectl create secret generic influxdb-credentials \
  --from-literal=INFLUX_ADMIN_USERNAME="banka1-admin" \
  --from-literal=INFLUX_ADMIN_PASSWORD="$(openssl rand -hex 16)" \
  --from-literal=INFLUX_ADMIN_TOKEN="$(openssl rand -hex 32)" \
  -n banka-1

# mail-credentials  (Gmail App password, ne regular pwd — zahteva 2FA)
kubectl create secret generic mail-credentials \
  --from-literal=MAIL_USERNAME="banka1.notifications@gmail.com" \
  --from-literal=MAIL_PASSWORD="xxxx xxxx xxxx xxxx" \
  -n banka-1
```

### Opcija B — popuni template fajl

```bash
cp secrets.yaml.example secrets.yaml      # secrets.yaml u .gitignore
# rucno zameni sve REPLACE_ME-* vrednosti
kubectl apply -f secrets.yaml -n banka-1
rm secrets.yaml
```

---

## 3. Inter-bank handshake (Banka 1 <-> Banka 2) — detalji

`interbank-service` cita `INTERBANK_PARTNERS_JSON` (iz `interbank-partners` Secret-a).
Za partnera Banka 2 (routing 222):

| Polje | Vrednost | Znacenje |
|-------|----------|----------|
| `Routing` | `222` | routing broj Banke 2 |
| `BaseURL` | `https://banka-2.radenkovic.rs/api` | Banka 2 inbound je POD `/api` |
| `InboundToken` | `REPLACE_ME-interbank-inbound-token-64hex` | token koji Banka 1 ocekuje na pozivima OD Banke 2 |
| `OutboundToken` | `REPLACE_ME-interbank-outbound-token-64hex` | token koji Banka 1 SALJE kad zove Banku 2 |

`INTERBANK_PROFILE=prod` odbija token koji pocinje sa `dev-` ili je prazan — gornje
64-hex vrednosti su prave.

> **Asimetrija inbound-a:** Banka 1 inbound je BARE (`/interbank`, `/public-stock`,
> `/negotiations`, `/user/{rn}/{id}` — bez `/api`), dok je Banka 2 inbound pod `/api`.
> Zato Banka 1 `OutboundToken` ide na `https://banka-2.radenkovic.rs/api/...`, a
> Banka 2 zove Banku 1 na bare `https://banka-1.radenkovic.rs/interbank/...`.
> HTTPRoute (`route.yaml`) rutira te bare path-eve na interbank-service bez `/api` strip-a.

---

## 4. Verifikacija (posle apply-a)

```bash
# Svi secret-i postoje:
kubectl get secret -n banka-1 \
  app-secrets interbank-partners rabbitmq-credentials influxdb-credentials mail-credentials

# Crunchy auto-generisani DB secret-i:
kubectl get secret -n banka-1 | grep db-pguser-

# YAML validan:
for f in *.yaml; do kubectl apply --dry-run=client -f "$f" -n banka-1; done
```
