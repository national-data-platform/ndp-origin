# NDP Origin : local development stack

Runs a Pelican origin in standalone mode, with no federation to join,
for testing various features from your Keycloak realm for Pelican tokens
when Keycloak and Pelican both sign users in with CILogon. Your realm needs a
few changes first; they are in [KEYCLOAK.md](KEYCLOAK.md).

| Service | What it is | URL |
|---|---|---|
| `origin` | web UI, embedded issuer, token exchange, and the `/ndp` data | https://localhost:8444 |

Everything here is for local development only.

## Prerequisites

- Docker with Compose v2 (BuildKit is required by Pelican's Dockerfile)
- [mkcert](https://github.com/FiloSottile/mkcert) and `jq`
- A confidential CILogon client for the origin, from
  https://cilogon.org/oauth2/register, with callback
  `https://localhost:8444/api/v1.0/auth/oauth/callback` and scopes
  `openid email profile org.cilogon.userinfo`
- Your Keycloak realm, brokering CILogon, with the changes in KEYCLOAK.md,
  reachable from this machine over HTTPS (see "Reaching your Keycloak")

## 1. Work of from a specific branch

```bash
git clone https://github.com/PelicanPlatform/pelican.git
#or
#This will require for changing PELICAN_SRC to PELICAN_SRC=pelican-bbockelm
git clone https://github.com/bbockelm/pelican.git pelican-bbockelm
git -C pelican-bbockelm checkout issuer-token-exchange
#or
#This will require for changing PELICAN_SRC to PELICAN_SRC=pelican-ndp
git clone https://github.com/national-data-platform/pelican.git pelican-ndp
git -C pelican checkout feature/ndp-token-exchange
```

## 2. Certificates, secrets and data

```bash
./scripts/setup.sh                       # dev certs, data dir, .env from the example
$EDITOR .env                             # set CILOGON_CLIENT_ID
printf '%s' '<origin client secret>' > secrets/cilogon-client-secret
```

## 3. Point the origin at your realm

In `config/origin.yaml`, replace values in
`TokenExchangeTrustedIssuers` with your realm's values (KEYCLOAK.md, step 5).
The issuer is already set for a Keycloak at `https://ndp-kc-test:9443`.

## 4. Build and start

```bash
docker compose build  # first build compiles Pelican, its web UI and XRootD packages
docker compose up -d
docker compose logs -f origin
```

## 5. Sign in to the origin once

Open https://localhost:8444, sign in through CILogon and accept the acceptable
use policy. This creates your Pelican account and records your CILogon
identity (issuer `https://cilogon.org`), which exchanges are matched against.
Use the same institution you use when logging in through Keycloak: a different
one gives a different CILogon subject.

## 6. Issuer client and access

Create the client your application (JupyterHub, or curl below) authenticates
with:

```bash
docker compose exec origin pelican-server origin issuer client create \
  --server https://localhost:8444 --namespace /ndp \
  --grant-types urn:ietf:params:oauth:grant-type:token-exchange
```

Put the printed client ID in `AllowedClients` in `config/origin.yaml`, keep
the secret, then `docker compose restart origin`.

Give yourself read access to `/ndp/climate`:

```bash
docker compose exec origin pelican-server origin collection create --name climate --namespace /ndp/climate
```
In the UI:
- create a group and add the users
- add the group to the collection

This cli command was suppose to work but didnt:
```
docker compose exec origin pelican-server origin collection acl grant <collection-id> \
  --group-id user-<your-pelican-username> --role read
```

Each collection command prints a link: open it in your browser and approve
with your origin account. The commands log in to the origin named by
`Server.ExternalWebUrl` (here https://localhost:8444) with a device-code flow.

## 7. Try the exchange

Get keycloak token with the device flow:

```bash
bash scripts/test-token-exchange.sh
```

Make sure that .env has the following vars:
```
KC_REALM_URL=https://ndp-kc-test:9443/realms/NDP
KC_CLIENT_ID=jupyterhub_local
KC_CLIENT_SECRET=<fillin>

PELICAN_ID=<fillin>
PELICAN_SECRET=<fillin>

PELICAN_ORIGIN=https://localhost:8444
```

The shell script asks for all of `/ndp` on purpose: the token should come back narrowed
to `storage.read:/climate`.

## Reaching your Keycloak

The origin calls Keycloak's discovery document and signing keys over HTTPS,
outbound only.

- **Publicly trusted certificate:** nothing to do.
- **Private CA:** copy the CA certificate to `certs/<name>.crt` and
  `docker compose restart`; the containers trust every `/certs/*.crt`.
- **Keycloak on this machine:** run it as `ndp-kc-test`, as below. Inside the
  containers `localhost` means the containers themselves, so
  `docker-compose.yml` maps `ndp-kc-test` to the host. If your Keycloak runs
  elsewhere, remove that `extra_hosts` entry.

## Notes

- Configuration changes need `docker compose restart <service>`.
- State (keys, accounts, issuer clients, collections) lives in named volumes;
  `docker compose down -v` resets everything.
- To see why an exchange was rejected, add `PELICAN_LOGGING_LEVEL: debug` to
  the origin's `environment` and read `docker compose logs origin`.