# HealthVault TLS Configuration

## Overview

Caddy handles all TLS termination for HealthVault. Three modes are supported, configured by editing `proxy/Caddyfile`. Only one mode can be active at a time.

---

## Mode 1: Internal CA (Default)

Caddy generates a local certificate authority and signs a certificate for your `INSTANCE_HOSTNAME`. This is the default and works on LAN or home servers without any external connectivity.

```
tls internal
```

**Pros:** No internet required, automatic renewal, works with any hostname.
**Cons:** Browsers will show a certificate warning until you trust the CA.

---

## Mode 2: ACME / Let's Encrypt

Caddy obtains a trusted certificate from Let's Encrypt automatically.

**Requirements:**
- Port 80 must be reachable from the internet (for HTTP-01 challenge).
- `INSTANCE_HOSTNAME` must resolve to your server's public IP.
- `ACME_EMAIL` must be set in `.env`.

Edit `proxy/Caddyfile`:

```
# Comment out:
# tls internal

# Uncomment:
tls {$ACME_EMAIL}
```

Restart the proxy:

```bash
docker compose restart proxy
```

Caddy will automatically obtain and renew the certificate. No further action is needed.

---

## Mode 3: Custom Certificate

Use your own certificate and private key (e.g., from a corporate CA or purchased certificate).

Edit `proxy/Caddyfile`:

```
# Comment out:
# tls internal

# Uncomment and set paths:
tls /custom/server.crt /custom/server.key
```

Mount the files into the proxy container by adding to `docker-compose.yml` under the `proxy` service:

```yaml
volumes:
  - ./certs/server.crt:/custom/server.crt:ro
  - ./certs/server.key:/custom/server.key:ro
```

Restart after changes:

```bash
docker compose restart proxy
```

---

## Trust Store Setup

When using **Mode 1 (Internal CA)**, you must add Caddy's root CA certificate to your devices so browsers and apps trust the connection.

### Extract the CA certificate

```bash
docker compose exec proxy caddy trust
```

This installs the CA into the container's trust store. To export the CA certificate for other devices:

```bash
docker compose cp proxy:/data/caddy/pki/authorities/local/root.crt ./caddy-root-ca.crt
```

### macOS

```bash
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain caddy-root-ca.crt
```

Or open Keychain Access, import `caddy-root-ca.crt`, and set it to "Always Trust."

### Windows

```powershell
certutil -addstore -f "ROOT" caddy-root-ca.crt
```

Or double-click the `.crt` file, select "Install Certificate," choose "Local Machine," and place it in "Trusted Root Certification Authorities."

### Linux

```bash
# Debian/Ubuntu
sudo cp caddy-root-ca.crt /usr/local/share/ca-certificates/caddy-root-ca.crt
sudo update-ca-certificates

# Fedora/RHEL
sudo cp caddy-root-ca.crt /etc/pki/ca-trust/source/anchors/caddy-root-ca.crt
sudo update-ca-trust
```

### iOS

1. Transfer `caddy-root-ca.crt` to your device (AirDrop, email, or file share).
2. Open the file and follow the prompts to install the profile.
3. Go to **Settings > General > About > Certificate Trust Settings**.
4. Enable full trust for the Caddy root certificate.

### Android

1. Transfer `caddy-root-ca.crt` to your device.
2. Go to **Settings > Security > Encryption & Credentials > Install a certificate**.
3. Select **CA certificate** and choose the file.
4. Confirm the installation.

---

## The `caddy trust` Command

Run inside the proxy container to install the internal CA into the system trust store:

```bash
docker compose exec proxy caddy trust
```

This is useful for the container itself and for CI/CD pipelines. For end-user devices, export the CA certificate and install it manually (see above).

---

## Certificate Expiry Monitoring

### Internal CA mode

Caddy automatically renews internal certificates before they expire. No monitoring is typically required, but you can inspect the current certificate:

```bash
docker compose exec proxy caddy list-certs 2>/dev/null || \
  openssl s_client -connect localhost:443 -servername your-host </dev/null 2>/dev/null \
  | openssl x509 -noout -dates
```

### ACME mode

Caddy renews Let's Encrypt certificates automatically (30 days before expiry). Monitor renewal by checking Caddy logs:

```bash
docker compose logs proxy | grep -i "certificate\|renew\|acme"
```

### Custom certificate mode

You are responsible for renewal. Set a calendar reminder or use a monitoring tool to alert before expiry:

```bash
echo | openssl s_client -connect localhost:443 -servername your-host 2>/dev/null \
  | openssl x509 -noout -enddate
```

---

## Troubleshooting

### Browser shows "Not Secure" or certificate warning

- **Internal CA mode:** You need to trust the CA certificate on your device (see Trust Store Setup above).
- **ACME mode:** Verify that port 80 is open and `INSTANCE_HOSTNAME` resolves to your server. Check `docker compose logs proxy` for ACME errors.

### Certificate does not match hostname

- Ensure `INSTANCE_HOSTNAME` in `.env` matches the hostname you use in the browser.
- Restart the proxy after changing the hostname: `docker compose restart proxy`.

### Connection refused on port 443

- Verify the proxy container is running: `docker compose ps proxy`.
- Check for port conflicts: `ss -tlnp | grep 443`.

### ACME rate limits

- Let's Encrypt enforces rate limits (50 certificates per registered domain per week).
- Use the staging environment for testing by adding `acme_ca https://acme-staging-v02.api.letsencrypt.org/directory` to the Caddyfile global options block.

### Caddy fails to start

- Validate the Caddyfile: `docker compose exec proxy caddy validate --config /etc/caddy/Caddyfile`.
- Check logs: `docker compose logs proxy`.
