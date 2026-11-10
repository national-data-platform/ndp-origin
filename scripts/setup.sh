#!/usr/bin/env bash
# One-time local setup: development certificates, the data directory, and
# checks for the files docker compose needs. Development only.
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p certs
mkcert -install
mkcert -cert-file certs/localhost.pem -key-file certs/localhost-key.pem localhost 127.0.0.1 ::1
# Keycloak on this machine is reached as ndp-kc-test (see README.md).
mkcert -cert-file certs/ndp-kc-test.pem -key-file certs/ndp-kc-test-key.pem ndp-kc-test
cp "$(mkcert -CAROOT)/rootCA.pem" certs/ca.crt   # containers trust /certs/*.crt
# Readable by the unprivileged users the services run as (Keycloak: uid 1000). Dev only.
chmod 0644 certs/localhost-key.pem certs/ndp-kc-test-key.pem

# Data exported under /ndp. XRootD runs as its own user inside the container.
mkdir -p data/ndp/climate
[ -f data/ndp/climate/hello.txt ] || echo "hello from /ndp/climate" > data/ndp/climate/hello.txt
chmod -R a+rwX data

grep -qE '[[:space:]]ndp-kc-test([[:space:]]|$)' /etc/hosts ||
  echo "Next: add '127.0.0.1 ndp-kc-test' to /etc/hosts"
[ -f .env ] || { cp .env.example .env; echo "Created .env: set CILOGON_CLIENT_ID."; }
mkdir -p secrets
[ -s secrets/cilogon-client-secret ] ||
  echo "Next: put the origin's CILogon client secret in secrets/cilogon-client-secret"
[ -f "${PELICAN_SRC:-pelican}/images/Dockerfile" ] ||
  echo "Next: clone Pelican into ./pelican and apply the patch (see README.md)"
echo "Setup complete."
