#!/bin/sh

VAULT_ADDR="http://127.0.0.1:8200"
INIT_FILE="/vault/file/.vault-init"

# Start vault server in background
vault server -config=/vault/config/config.hcl &
VAULT_PID=$!

echo "==> Waiting for Vault API..."

# Wait until vault API responds (exit 1 = unreachable, any other code = up)
while true; do
  vault status -address="$VAULT_ADDR" > /dev/null 2>&1
  if [ "$?" -ne 1 ]; then
    break
  fi
  sleep 1
done

echo "==> Vault API is up"

# Initialize on first boot (INIT_FILE not present = never initialized)
if [ ! -f "$INIT_FILE" ]; then
  echo "==> Initializing Vault..."
  INIT_OUTPUT=$(vault operator init \
    -key-shares=1 \
    -key-threshold=1 \
    -address="$VAULT_ADDR" \
    -format=json)

  # Parse JSON using sed (no jq available in vault image)
  # Vault pretty-prints with spaces, so patterns allow optional spaces around : [ "
  UNSEAL_KEY=$(echo "$INIT_OUTPUT" | tr -d '\n' | sed 's/.*"unseal_keys_b64": *\[ *"\([^"]*\)".*/\1/')
  ROOT_TOKEN=$(echo "$INIT_OUTPUT" | tr -d '\n' | sed 's/.*"root_token": *"\([^"]*\)".*/\1/')

  if [ -z "$UNSEAL_KEY" ] || [ -z "$ROOT_TOKEN" ]; then
    echo "ERROR: Failed to parse vault init output"
    echo "$INIT_OUTPUT"
    exit 1
  fi

  printf '{"unseal_key":"%s","root_token":"%s"}\n' "$UNSEAL_KEY" "$ROOT_TOKEN" > "$INIT_FILE"
  chmod 600 "$INIT_FILE"
  echo "==> Vault initialized, keys saved"
fi

# Read stored init data
UNSEAL_KEY=$(sed 's/.*"unseal_key":"\([^"]*\)".*/\1/' "$INIT_FILE")
ROOT_TOKEN=$(sed 's/.*"root_token":"\([^"]*\)".*/\1/' "$INIT_FILE")

# Unseal vault
echo "==> Unsealing Vault..."
vault operator unseal -address="$VAULT_ADDR" "$UNSEAL_KEY" > /dev/null
echo "==> Vault unsealed"

# Enable KV v2 secrets engine at "secret/" — check first so a restart never
# retries the mount (which Vault logs as a server [ERROR], even though the
# outcome is harmless and previously only worked around by discarding stderr).
if VAULT_TOKEN="$ROOT_TOKEN" vault secrets list -address="$VAULT_ADDR" 2>/dev/null | grep -q '^secret/'; then
  echo "==> KV v2 engine already enabled"
else
  VAULT_TOKEN="$ROOT_TOKEN" vault secrets enable \
    -address="$VAULT_ADDR" \
    -path=secret \
    kv-v2 && echo "==> KV v2 engine enabled"
fi

# Create a client token for other services.
# Re-use the existing one if it was already generated on a previous boot.
CLIENT_TOKEN_FILE="/vault/shared/token"
if [ -f "$CLIENT_TOKEN_FILE" ]; then
  CLIENT_TOKEN=$(cat "$CLIENT_TOKEN_FILE")
  echo "==> Re-using existing client token"
else
  CLIENT_TOKEN=$(head -c 32 /dev/urandom | od -A n -t x1 | tr -d ' \n')
  echo "==> Generated random client token"
fi

VAULT_TOKEN="$ROOT_TOKEN" vault token create \
  -address="$VAULT_ADDR" \
  -id="${CLIENT_TOKEN}" \
  -policy=root \
  -orphan \
  -renewable=false \
  > /dev/null 2>&1 && echo "==> Client token created" || echo "==> Client token already exists"

printf '%s' "$CLIENT_TOKEN" > "$CLIENT_TOKEN_FILE"
chmod 600 "$CLIENT_TOKEN_FILE"

echo "==> Vault is ready"

wait "$VAULT_PID"
