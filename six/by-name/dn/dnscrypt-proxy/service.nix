{ lib
, six
, pkgs
, targets
, package ? pkgs.dnscrypt-proxy
, listen-addresses ? throw "required"
, bootstrap-resolvers ? throw "required"
, user-name ? "dnscrypt"
}:
let
  bootstrap-resolvers-toml =
    lib.pipe bootstrap-resolvers [
      (map (addr: "'${addr}'"))
      (lib.concatStringsSep ", ")
      (str: "[${str}]")
    ];
  listen-addresses-toml =
    lib.pipe listen-addresses [
      (map (addr: "'${addr}'"))
      (lib.concatStringsSep ", ")
      (str: "[${str}]")
    ];
in
# to do:
#   https://github.com/DNSCrypt/dnscrypt-proxy/wiki/Load-Balancing-Options
#   https://github.com/DNSCrypt/dnscrypt-proxy/wiki/Anonymized-DNS
six.mkFunnel {
  passthru.after = [
    targets.global.coldplug  # for /dev/urandom
  ];
  run = pkgs.writeScript "run"
''
#!${pkgs.runtimeShell}
exec 2>&1
${pkgs.busybox}/bin/busybox mkdir -p /var/cache/dnscrypt-proxy/
${pkgs.busybox}/bin/busybox chown dnscrypt /var/cache/dnscrypt-proxy/

${pkgs.busybox}/bin/busybox mkdir -p /var/log/dnscrypt-proxy/
${pkgs.busybox}/bin/busybox chown dnscrypt /var/log/dnscrypt-proxy/

${pkgs.busybox}/bin/busybox cat /etc/dnscrypt-proxy/eden.hosts | \
  ${pkgs.gnused}/bin/sed 's_\(\S\+\) *\(\S\+\)_\2 \1_' \
  > /etc/dnscrypt-proxy/cloaking_rules.txt

${pkgs.busybox}/bin/busybox cat /etc/dnscrypt-proxy/cloaking_rules.txt | \
  ${pkgs.gnused}/bin/sed 's_ .*__' > /etc/dnscrypt-proxy/whitelist.txt

# "cloaked" entries do not seem to be affected by ip-blacklist
${pkgs.busybox}/bin/busybox cat > /etc/dnscrypt-proxy/ip-blacklist.txt<<\EOF
EOF

${pkgs.busybox}/bin/busybox cat > /etc/dnscrypt-proxy/blacklist.txt<<\EOF
*.eden
*.settings.services.mozilla.com
*.services.mozilla.com
*.gravatar.com

# Localhost rebinding protection
0.0.0.0
127.0.0.*

# RFC1918 rebinding protection
10.*
172.16.*
172.17.*
172.18.*
172.19.*
172.20.*
172.21.*
172.22.*
172.23.*
172.24.*
172.25.*
172.26.*
172.27.*
172.28.*
172.29.*
172.30.*
172.31.*
192.168.*
EOF

${pkgs.busybox}/bin/busybox cat > /etc/dnscrypt-proxy/dnscrypt-proxy.toml+<<\EOF
listen_addresses = ${listen-addresses-toml}
#server_names = ['static-cs-sea', 'static-cs-ore', 'static-cs-vancouver', 'static-cs-tx', 'static-cs-tx2', 'static-cs-tx3']

# aka synthetic domain names
cloaking_rules = '/etc/dnscrypt-proxy/cloaking_rules.txt'

# TTL used when serving entries in cloaking-rules.txt
cloak_ttl = 6000

# server selection
doh_servers = false
dnscrypt_servers = true
require_nolog = true
require_nofilter = true # Server must not enforce its own blacklist (for parental control, ads blocking...)
block_ipv6 = true
blocked_query_response = 'refused'   # instead of a synthetic TXT message
ipv6_servers = false
ipv4_servers = true
bootstrap_resolvers = ${bootstrap-resolvers-toml}
# Skip resolvers incompatible with anonymization instead of using them directly
#skip_incompatible = false

# this feature is not supported?
disabled_server_names = ['quad9-dnscrypt-ip4-nofilter-ecs-pri', 'quad9-dnscrypt-ip4-nofilter-pri']  # don't trust them

#lb_strategy = 'p2'  # randomly alternate between the two fastest servers
lb_strategy = 'ph'  # randomly alternate between the fastest half of servers

cache = true
cache_size = 65536
cache_min_ttl = 2400    # I think this will artificially jack up the ttl
#cache_max_ttl = 86400
cache_neg_min_ttl = 60
#cache_neg_max_ttl = 600

#max_clients = 100

dnscrypt_ephemeral_keys = true
tls_disable_session_tickets = true

[blocked_names]
blocked_names_file = '/etc/dnscrypt-proxy/blacklist.txt'

[whitelist]
whitelist_file = '/etc/dnscrypt-proxy/whitelist.txt'

[blocked_ips]
blocked_ips_file = '/etc/dnscrypt-proxy/ip-blacklist.txt'

# do not cause tons of tiny writes to flash on router devices
#[query_log]
#  file = '/var/log/dnscrypt-proxy/query.log'
#[nx_log]
#  file = '/var/log/dnscrypt-proxy/nx.log'

[sources]
  [sources.'public-resolvers']
  urls = ['https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/public-resolvers.md', 'https://download.dnscrypt.info/resolvers-list/v3/public-resolvers.md']
  cache_file = '/var/cache/dnscrypt-proxy/public-resolvers.md'
  minisign_key = 'RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3'
  refresh_delay = 72
  prefix = ""

[static]

[static.'static-cs-ore']
stamp = 'sdns://AQYAAAAAAAAADTEwNC4yNTUuMTc1LjIgMTNyrVlWMsJBa4cvCY-FG925ZShMbL6aTxkJZDDbqVoeMi5kbnNjcnlwdC1jZXJ0LmNyeXB0b3N0b3JtLmlz'

[static.'static-cs-sea']
stamp = 'sdns://AQIAAAAAAAAADDY0LjEyMC41LjI1MSAxM3KtWVYywkFrhy8Jj4Ub3bllKExsvppPGQlkMNupWh4yLmRuc2NyeXB0LWNlcnQuY3J5cHRvc3Rvcm0uaXM'

[static.'static-cs-tx']
stamp = 'sdns://AQIAAAAAAAAADTIwOS41OC4xNDcuMzYgMTNyrVlWMsJBa4cvCY-FG925ZShMbL6aTxkJZDDbqVoeMi5kbnNjcnlwdC1jZXJ0LmNyeXB0b3N0b3JtLmlz'

[static.'static-cs-tx2']
stamp = 'sdns://AQIAAAAAAAAACzQ1LjM1LjM1Ljk5IDEzcq1ZVjLCQWuHLwmPhRvduWUoTGy-mk8ZCWQw26laHjIuZG5zY3J5cHQtY2VydC5jcnlwdG9zdG9ybS5pcw'

[static.'static-cs-tx3']
stamp = 'sdns://AQIAAAAAAAAACzQ1LjM1LjcyLjQzIDEzcq1ZVjLCQWuHLwmPhRvduWUoTGy-mk8ZCWQw26laHjIuZG5zY3J5cHQtY2VydC5jcnlwdG9zdG9ybS5pcw'

[static.'static-cs-vancouver']
stamp = 'sdns://AQIAAAAAAAAADDcxLjE5LjI1MS4zNCAxM3KtWVYywkFrhy8Jj4Ub3bllKExsvppPGQlkMNupWh4yLmRuc2NyeXB0LWNlcnQuY3J5cHRvc3Rvcm0uaXM'

[static.'dnsforge.de']
stamp = 'sdns://AgMAAAAAAAAADDE3Ni45LjkzLjE5OKDMEGDTnIMptitvvH0NbfkwmGm5gefmOS1c2PpAj02A5iBETr1nu4P4gHs5Iek4rJF4uIK9UKrbESMfBEz18I33zgtkbnNmb3JnZS5kZQovZG5zLXF1ZXJ5'

[static.'libredns']
stamp = 'sdns://AgYAAAAAAAAADjExNi4yMDIuMTc2LjI2oMwQYNOcgym2K2-8fQ1t-TCYabmB5-Y5LVzY-kCPTYDmIEROvWe7g_iAezkh6TiskXi4gr1QqtsRIx8ETPXwjffOD2RvaC5saWJyZWRucy5ncgovZG5zLXF1ZXJ5'

[static.'static-he']
stamp = 'sdns://AgUAAAAAAAAACzc0LjgyLjQyLjQyoDKG_2WmX68yCF7qE4jDc4un43hzyQbM48Sii0zCpYmIoEROvWe7g_iAezkh6TiskXi4gr1QqtsRIx8ETPXwjffOIMwQYNOcgym2K2-8fQ1t-TCYabmB5-Y5LVzY-kCPTYDmDG9yZG5zLmhlLm5ldAovZG5zLXF1ZXJ5'
EOF
${pkgs.busybox}/bin/busybox mv -f /etc/dnscrypt-proxy/dnscrypt-proxy.toml+ /etc/dnscrypt-proxy/dnscrypt-proxy.toml

# allow binding to low port numbers without root
${lib.getBin pkgs.libcap}/bin/setcap cap_net_bind_service=+epi ${pkgs.dnscrypt-proxy}/bin/dnscrypt-proxy

exec \
    ${pkgs.runit}/bin/chpst -u ${user-name} -U ${user-name} \
    ${pkgs.dnscrypt-proxy}/bin/dnscrypt-proxy \
    -config /etc/dnscrypt-proxy/dnscrypt-proxy.toml
'';
}
