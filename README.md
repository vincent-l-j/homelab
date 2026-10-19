# Homelab

Docker Compose stacks for Nextcloud AIO, Caddy, and WireGuard with Pi-hole DNS.
DDNS is not configured here.

## Layout

| Stack | Purpose |
| --- | --- |
| [edge](edge/compose.yaml) | Host-networked Caddy providing HTTPS and reverse proxying |
| [nextcloud](nextcloud/compose.yaml) | Nextcloud AIO, with Apache bound to `127.0.0.1:11000` |
| [vpn](vpn/compose.yaml) | wg-easy v15 and Pi-hole on a shared Docker bridge |

Run these on the same Linux Docker host with Docker Compose supporting inline
`configs.content` and multiple `--env-file` arguments. WireGuard needs kernel
support and the container capabilities declared in its stack.

## Configuration

Run all commands below from the repository root:

```sh
cp .env.example .env
cp vpn/.env.example vpn/.env
cp nextcloud/.env.example nextcloud/.env
```

For existing installations, keep existing local environment files and data.
Move shared values from the old `edge/.env` and `vpn/.env` into the root `.env`,
then remove those duplicate values from the stack-local files. The commands
below no longer read `edge/.env`. Later `--env-file` arguments override earlier
ones, and exported shell variables override both.

Edit the files before starting:

- [Root environment example](.env.example): set `DOMAIN_NAME` to the **existing
  Nextcloud hostname**, without `https://` or a path. Set `HOST_IP` to the Docker
  host's reserved LAN IPv4 address, not a container IP or public IP. Adjust the
  Docker subnets and container addresses if they overlap other networks.
- [VPN environment example](vpn/.env.example): set a strong Pi-hole password and
  the timezone. Keep `WG_EASY_INSECURE=true`: Caddy terminates HTTPS and talks
  HTTP to wg-easy over loopback only.
- [Nextcloud environment example](nextcloud/.env.example): set the data path on
  a new installation. **Do not change the data path on an existing installation.**

Local `.env` files are gitignored. Keep secrets out of the example files.
Compose's `--env-file` supplies interpolation values; it does not inject all
of them into every container.

## Start the stacks

```sh
docker compose --env-file .env --env-file vpn/.env -f vpn/compose.yaml up -d --build
docker compose --env-file .env --env-file nextcloud/.env -f nextcloud/compose.yaml up -d
docker compose --env-file .env -f edge/compose.yaml up -d
```

Use the same flags with `config --quiet` to validate configuration, or with
`logs`, `ps`, and subsequent `up -d` commands. After changing shared values,
reapply both the VPN and edge stacks. Changing network addresses may require
recreating the VPN network and updating client settings.

Nextcloud AIO's setup interface is `https://HOST_IP:8080` (self-signed
certificate). Complete AIO setup using the configured Nextcloud hostname.
The proxy configuration preserves the existing Nextcloud site and internal TLS.

## Hostnames and routing

For `DOMAIN_NAME=family.cloud`:

| URL | Caddy upstream |
| --- | --- |
| `https://family.cloud` | Nextcloud at `localhost:11000` |
| `https://pihole.family.cloud` | Pi-hole at `127.0.0.1:PIHOLE_UI_PORT`, redirecting `/` to `/admin/` |
| `https://wg.family.cloud` | wg-easy at `127.0.0.1:WG_UI_PORT` |

Pi-hole's `FTLCONF_dns_hosts` supplies all three A records, pointing at `HOST_IP`,
so browsers reach Caddy rather than individual containers. These records are
managed through Compose; edit `FTLCONF_dns_hosts` rather than the local DNS
records in the Pi-hole UI, since environment-managed settings are read-only there.

The two admin sites reject clients outside Caddy's `private_ranges` (private
IPv4, IPv6 ULA, and loopback ranges). They still require their normal application
logins. Nextcloud's access policy is unchanged. Caddy is intended to receive
client connections directly, not through another reverse proxy.

### Make clients use Pi-hole

- **LAN:** configure your router's DHCP DNS server as `HOST_IP`, then renew
  client leases. Pi-hole publishes TCP and UDP port 53 on this LAN address.
  Ensure no other service already occupies that address and port.
- **WireGuard:** in wg-easy, set client DNS to the shared `PIHOLE_IP` value
  (default `10.42.42.3`). Ensure client routes include both that address and
  `HOST_IP`; a full-tunnel profile normally does. Refresh/reimport existing
  client profiles after changing DNS or routes. The container IP
  `WG_CONTAINER_IP` is not the WireGuard client gateway or VPN endpoint.
- Browser secure DNS/DoH, OS private DNS, or an alternate public DNS server can
  bypass Pi-hole. Configure them appropriately if these names do not resolve.

Do not forward DNS port 53 or either UI backend port from your router to the
internet. Limit host firewall DNS access to your LAN and intended VPN clients.
Allow LAN/VPN clients to reach Caddy on TCP 443 (and TCP 80 for its HTTPS
redirects). Forward UDP 51820 only if remote WireGuard access is needed.
The WireGuard tunnel itself still uses its configured public endpoint and UDP
51820; `wg.DOMAIN_NAME` is the management UI, not a replacement tunnel endpoint.
Do not use a Pi-hole-only hostname to bootstrap the VPN from outside your LAN.

### Trust HTTPS certificates

All Caddy sites use `tls internal`, not public ACME certificates. Install
Caddy's root CA as a trusted certificate on each client (and in browsers with
separate trust stores). Copy the public root certificate from the running
container:

```sh
docker cp caddy:/data/caddy/pki/authorities/local/root.crt ./caddy-root.crt
```

Transfer and trust this certificate securely; do not copy the CA private key.
Remove the exported copy when finished. Keep the Caddy data volume so the CA
remains stable across container recreation. An existing device that already
trusts this Caddy CA should also trust the new sites.

## Verification

Replace the sample address and domain with your configured values:

```sh
# LAN DNS path; all three should return the host's LAN address.
dig @192.168.1.10 family.cloud +short
dig @192.168.1.10 pihole.family.cloud +short
dig @192.168.1.10 wg.family.cloud +short

# Check the client's default DNS path too.
dig pihole.family.cloud +short

# Test Caddy independently of client DNS, using the exported CA.
curl --cacert ./caddy-root.crt --resolve pihole.family.cloud:443:192.168.1.10 \
  -I https://pihole.family.cloud/
curl --cacert ./caddy-root.crt --resolve wg.family.cloud:443:192.168.1.10 \
  -I https://wg.family.cloud/
```

Expect a redirect to `/admin/` for Pi-hole and a wg-easy response or login
redirect. Open both sites in a browser on the LAN, then repeat over WireGuard.
If DNS works but HTTPS does not, check VPN routes, firewall rules, CA trust,
and the edge/VPN stack logs.
