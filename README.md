# kafka-configs

Kafka infrastructure configuration — topics, JMX exporter rules, and Docker Compose for the Kafka stack.

## Structure

```
kafka-configs/
├── topicctl/                    # Topic management (declarative, drift-detecting)
│   ├── cluster.yaml             # Cluster connection config
│   └── topics/
│       ├── bluesky-posts.yaml   # One file per topic
│       └── stress-test.yaml
│
├── topics/                      # Legacy topic creation (replaced by topicctl)
│   ├── topics.yaml
│   └── create_topics.sh
│
├── jmx-exporter/
│   └── config.yaml              # JMX → Prometheus metric mapping rules
│
├── promtail/
│
└── docker-compose/
    └── kafka-compose.yml        # Kafka + JMX exporter + Promtail
```

## Topic Management with topicctl

[topicctl](https://github.com/segmentio/topicctl) is used for declarative topic management. It creates, updates, and diffs topics via the Kafka Admin API — no broker restarts, no downtime.

### Install

```bash
# macOS
brew install segment-io/tap/topicctl

# Linux / Windows (download binary)
# https://github.com/segmentio/topicctl/releases
```

### Usage

All commands are run from the `kafka-configs/` directory.

**Preview changes (dry run):**

```bash
# From a broker VM (via SSH or SSM session)
topicctl apply topicctl/topics/*.yaml \
  --cluster-config topicctl/cluster.yaml \
  --dry-run

# From your local machine (use a broker's public IP on the external listener)
topicctl apply topicctl/topics/*.yaml \
  --cluster-config topicctl/cluster.yaml \
  --broker-addr <broker-public-ip>:9094 \
  --dry-run
```

**Apply changes:**

```bash
# Same as above, without --dry-run
topicctl apply topicctl/topics/*.yaml \
  --cluster-config topicctl/cluster.yaml
```

**Check for drift (compare live state to YAML):**

```bash
topicctl check topicctl/topics/*.yaml \
  --cluster-config topicctl/cluster.yaml
```

**Inspect cluster and topics:**

```bash
# List all topics
topicctl get topics --cluster-config topicctl/cluster.yaml

# Describe a specific topic
topicctl get topic bluesky-posts --cluster-config topicctl/cluster.yaml

# Cluster overview (brokers, partitions, leaders)
topicctl get brokers --cluster-config topicctl/cluster.yaml
```

### Workflow: Editing Topics

1. Edit the topic YAML in `topicctl/topics/` (or create a new file for a new topic)
2. Dry run to preview: `topicctl apply ... --dry-run`
3. Apply: `topicctl apply ...`
4. Commit and push to git

topicctl applies changes via the Kafka Admin API. This is safe to run against a live cluster — it does not restart brokers or interrupt producers/consumers.

**What topicctl can change on existing topics:**
- Topic-level configs (retention, cleanup policy, min ISR, etc.)
- Partition count (increase only — Kafka does not support decreasing partitions)

**What requires a new topic:**
- Replication factor changes (topicctl will warn, not apply)

### Cluster Config

`topicctl/cluster.yaml` defaults to `localhost:9092` for use on broker VMs. When running from your local machine, override with `--broker-addr`:

```bash
topicctl apply ... --broker-addr <broker-public-ip>:9094
```

### Legacy: create_topics.sh

The `topics/` directory contains the old shell-based topic creator. It's kept for reference but has limitations:
- `--if-not-exists` silently skips existing topics (no drift detection)
- Config block values are not applied to existing topics
- No dry-run capability

Use topicctl instead.

## Deployment

Set the required environment variables and run:

```bash
export KAFKA_PUBLIC_IP="<vm-public-ip>"
export KAFKA_CLUSTER_ID="$(uuidgen)"
export KAFKA_USER_HOME="/home/kafkauser"

cd docker-compose
docker compose -f kafka-compose.yml up -d
```

## Required Environment Variables

| Variable | Description |
|---|---|
| `KAFKA_PUBLIC_IP` | VM's public IP for the external Kafka listener |
| `KAFKA_CLUSTER_ID` | Stable KRaft cluster ID (persisted across restarts) |
| `KAFKA_USER_HOME` | Home directory of the deploy user |
