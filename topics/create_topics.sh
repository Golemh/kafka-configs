#!/bin/bash
# Topic Creator Script
# Reads topics.yaml and creates topics in Kafka, including per-topic configs.

set -e

BOOTSTRAP_SERVER="${KAFKA_BOOTSTRAP_SERVER:-kafka:9092}"
TOPICS_FILE="/topics/topics.yaml"

echo "Waiting for Kafka to be ready..."
until /opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server "$BOOTSTRAP_SERVER" > /dev/null 2>&1; do
  echo "Kafka not ready, waiting..."
  sleep 2
done
echo "Kafka is ready!"

# Parse YAML and create topics
# Using grep/awk since yq may not be available in kafka image
echo "Creating topics from $TOPICS_FILE..."

current_topic=""
partitions=""
replication=""
configs=""
in_config=false

while IFS= read -r line; do
  # Detect config block
  if echo "$line" | grep -q "^[[:space:]]*config:"; then
    in_config=true
    continue
  fi

  # Extract topic name (new topic resets state)
  if echo "$line" | grep -q "^[[:space:]]*- name:"; then
    # Create previous topic if we have all info
    if [ -n "$current_topic" ] && [ -n "$partitions" ] && [ -n "$replication" ]; then
      echo "Creating topic: $current_topic (partitions=$partitions, replication=$replication, configs=$configs)"
      config_args=""
      if [ -n "$configs" ]; then
        config_args="$configs"
      fi
      /opt/kafka/bin/kafka-topics.sh --create --if-not-exists \
        --bootstrap-server "$BOOTSTRAP_SERVER" \
        --topic "$current_topic" \
        --partitions "$partitions" \
        --replication-factor "$replication" \
        $config_args || true
    fi

    current_topic=$(echo "$line" | sed 's/.*name: *//' | tr -d '"' | tr -d "'")
    partitions=""
    replication=""
    configs=""
    in_config=false
    continue
  fi

  # Extract partitions
  if echo "$line" | grep -q "^[[:space:]]*partitions:"; then
    partitions=$(echo "$line" | sed 's/.*partitions: *//')
    in_config=false
    continue
  fi

  # Extract replication factor
  if echo "$line" | grep -q "^[[:space:]]*replication_factor:"; then
    replication=$(echo "$line" | sed 's/.*replication_factor: *//' | awk '{print $1}')
    in_config=false
    continue
  fi

  # Extract config key-value pairs
  if [ "$in_config" = true ]; then
    config_key=$(echo "$line" | sed 's/^[[:space:]]*//' | cut -d: -f1)
    config_val=$(echo "$line" | cut -d: -f2- | sed 's/^[[:space:]]*//' | awk '{print $1}')
    if [ -n "$config_key" ] && [ -n "$config_val" ]; then
      configs="$configs --config ${config_key}=${config_val}"
    fi
  fi
done < "$TOPICS_FILE"

# Create the last topic
if [ -n "$current_topic" ] && [ -n "$partitions" ] && [ -n "$replication" ]; then
  echo "Creating topic: $current_topic (partitions=$partitions, replication=$replication, configs=$configs)"
  config_args=""
  if [ -n "$configs" ]; then
    config_args="$configs"
  fi
  /opt/kafka/bin/kafka-topics.sh --create --if-not-exists \
    --bootstrap-server "$BOOTSTRAP_SERVER" \
    --topic "$current_topic" \
    --partitions "$partitions" \
    --replication-factor "$replication" \
    $config_args || true
fi

echo "Topic creation complete!"
/opt/kafka/bin/kafka-topics.sh --list --bootstrap-server "$BOOTSTRAP_SERVER"
