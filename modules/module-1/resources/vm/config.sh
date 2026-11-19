#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
id justin >/dev/null 2>&1 || useradd -m -s /bin/bash justin
install -d -m 700 -o justin -g justin /home/justin/.ssh
curl --fail --retry 8 --retry-delay 5 "https://${URL}/shared/files/.ssh/keys/justin.pub" -o /home/justin/.ssh/authorized_keys
chmod 600 /home/justin/.ssh/authorized_keys
chown -R justin:justin /home/justin/.ssh
apt-get update -o Acquire::Retries=5
apt-get install -y -o DPkg::Lock::Timeout=300 apache2
curl --fail --retry 5 -sL https://aka.ms/InstallAzureCLIDeb | bash
