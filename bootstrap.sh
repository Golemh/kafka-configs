#!/bin/bash
# bootstrap.sh — Kafka broker setup
# Called by cloud-init after packages, Docker, and disk mount are ready.
# Reads configuration from /opt/bootstrap-config.json.

set -euo pipefail

CONFIG_FILE="/opt/bootstrap-config.json"
USERNAME=$(jq -r '.username' "$CONFIG_FILE")
NODE_ID=$(jq -r '.node_id' "$CONFIG_FILE")
CLUSTER_ID=$(jq -r '.cluster_id' "$CONFIG_FILE")
QUORUM_VOTERS=$(jq -r '.quorum_voters' "$CONFIG_FILE")
PRIVATE_IP=$(jq -r '.private_ip' "$CONFIG_FILE")
REPLICATION_FACTOR=$(jq -r '.replication_factor' "$CONFIG_FILE")
MIN_ISR=$(jq -r '.min_isr' "$CONFIG_FILE")
KAFKA_MEMORY_LIMIT=$(jq -r '.kafka_memory_limit' "$CONFIG_FILE")
KAFKA_CPU_LIMIT=$(jq -r '.kafka_cpu_limit' "$CONFIG_FILE")
LOG_RETENTION_BYTES=$(jq -r '.log_retention_bytes' "$CONFIG_FILE")
LOG_SEGMENT_BYTES=$(jq -r '.log_segment_bytes' "$CONFIG_FILE")
LOKI_ENDPOINT=$(jq -r '.loki_endpoint' "$CONFIG_FILE")
HOME_DIR="/home/${USERNAME}"

echo "=== Kafka bootstrap: broker ${NODE_ID} ==="

# --- Data directory ---
mkdir -p /data/kafka
chown -R 1000:1000 /data/kafka

# --- Docker Compose setup ---
cp "${HOME_DIR}/kafka-configs/docker-compose/kafka-compose.yml" "${HOME_DIR}/docker-compose.yml"

# --- Detect public IP (AWS IMDSv2, then Azure IMDS fallback) ---
PUBLIC_IP=""
TOKEN=$(curl -sf -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null || true)
if [ -n "$TOKEN" ]; then
  PUBLIC_IP=$(curl -sf -H "X-aws-ec2-metadata-token: $TOKEN" \
    "http://169.254.169.254/latest/meta-data/public-ipv4" 2>/dev/null || true)
fi
if [ -z "$PUBLIC_IP" ]; then
  PUBLIC_IP=$(curl -sf -m 2 -H "Metadata:true" \
    "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/publicIpAddress?api-version=2021-02-01&format=text" 2>/dev/null || true)
fi
echo "  Public IP: ${PUBLIC_IP:-unknown}"

# --- Write .env ---
cat > "${HOME_DIR}/.env" <<ENVEOF
KAFKA_NODE_ID=${NODE_ID}
KAFKA_QUORUM_VOTERS=${QUORUM_VOTERS}
KAFKA_PRIVATE_IP=${PRIVATE_IP}
KAFKA_PUBLIC_IP=${PUBLIC_IP}
KAFKA_CLUSTER_ID=${CLUSTER_ID}
KAFKA_REPLICATION_FACTOR=${REPLICATION_FACTOR}
KAFKA_MIN_ISR=${MIN_ISR}
KAFKA_MEMORY_LIMIT=${KAFKA_MEMORY_LIMIT}
KAFKA_CPU_LIMIT=${KAFKA_CPU_LIMIT}
KAFKA_USER_HOME=${HOME_DIR}
KAFKA_LOG_RETENTION_BYTES=${LOG_RETENTION_BYTES}
KAFKA_LOG_SEGMENT_BYTES=${LOG_SEGMENT_BYTES}
LOKI_ENDPOINT=${LOKI_ENDPOINT}
ENVEOF

# --- Fix ownership ---
chown -R "${USERNAME}:${USERNAME}" "${HOME_DIR}"

# --- Start Kafka ---
echo "  Starting Kafka..."
cd "${HOME_DIR}" && docker compose up -d

# --- Node exporter ---
install_node_exporter() {
  local version="1.10.2"
  echo "  Installing node_exporter v${version}..."
  curl -sL "https://github.com/prometheus/node_exporter/releases/download/v${version}/node_exporter-${version}.linux-amd64.tar.gz" \
    -o /tmp/node_exporter.tar.gz
  tar xzf /tmp/node_exporter.tar.gz -C /tmp
  mv "/tmp/node_exporter-${version}.linux-amd64/node_exporter" /usr/local/bin/
  rm -rf /tmp/node_exporter*

  cat > /etc/systemd/system/node-exporter.service <<'SVCEOF'
[Unit]
Description=Prometheus Node Exporter
After=network-online.target
[Service]
Type=simple
User=nobody
ExecStart=/usr/local/bin/node_exporter
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
SVCEOF
  systemctl enable --now node-exporter.service
}

# --- Spot watcher ---
install_spot_watcher() {
  echo "  Installing spot-watcher daemon..."
  cat > /opt/spot-watcher.sh <<WATCHEREOF
#!/bin/bash
TOKEN=\$(curl -sf -X PUT "http://169.254.169.254/latest/api/token" \\
  -H "X-aws-ec2-metadata-token-ttl-seconds: 30")
ACTION=\$(curl -sf -H "X-aws-ec2-metadata-token: \$TOKEN" \\
  "http://169.254.169.254/latest/meta-data/spot/instance-action" 2>/dev/null)
if [ \$? -eq 0 ] && [ -n "\$ACTION" ]; then
  logger -t spot-watcher "Interruption warning received: \$ACTION"
  cd /home/${USERNAME} && docker compose stop
  sync
  logger -t spot-watcher "Graceful shutdown complete"
fi
WATCHEREOF
  chmod +x /opt/spot-watcher.sh

  cat > /etc/systemd/system/spot-watcher.service <<'SVCEOF'
[Unit]
Description=EC2 Spot Interruption Watcher
After=network-online.target
[Service]
Type=simple
ExecStart=/bin/bash -c 'while true; do /opt/spot-watcher.sh; sleep 5; done'
Restart=always
[Install]
WantedBy=multi-user.target
SVCEOF
  systemctl enable --now spot-watcher.service
}

install_node_exporter
install_spot_watcher

echo "=== Kafka bootstrap complete ==="
