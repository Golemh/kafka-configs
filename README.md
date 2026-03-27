# kafka-configs

Kafka infrastructure configuration — topics, JMX exporter rules, and Docker Compose for the Kafka stack.

## Structure

```
kafka-configs/
├── topics/
│   ├── topics.yaml          # Topic definitions (name, partitions, replication, retention)
│   └── create_topics.sh     # Entrypoint script for the topic-creator container
│
├── jmx-exporter/
│   └── config.yaml          # JMX → Prometheus metric mapping rules
│
└── docker-compose/
    └── kafka-compose.yml    # Kafka + topic-creator + producer + JMX exporter
```

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
| `BLUESKY_PRODUCER_IMAGE` | Optional — container registry image for the producer |
