#!/usr/bin/env bash
set -euo pipefail

BOOTSTRAP=kafka-service.kafka.svc:9092
BIN=${BIN:-/opt/bitnami/kafka/bin}

RETENTION_MS=604800000           # 7d
TOTAL_RETENTION_BYTES=1000000000 # 1GB per topic, split across partitions
SEGMENT_MS=86400000              # 1d
SEGMENT_BYTES=100000000          # 100MB

# desired partition count per topic; topics are scaled up if smaller
declare -A PARTITIONS=(
  [data.to_predict]=4
  [players.banned]=4
  [players.not_found]=8
  [players.scraped]=4
  [players.to_scrape]=4
  [predictions.to_insert]=1
  [reports.to_insert]=4
)

DESCRIBE="$("$BIN"/kafka-topics.sh --bootstrap-server "$BOOTSTRAP" --describe)"

while IFS= read -r LINE; do
  # only topic-level lines carry PartitionCount
  [[ "$LINE" == *"PartitionCount:"* ]] || continue

  TOPIC=$(printf '%s' "$LINE" | sed -n 's/.*Topic: \([^[:space:]]*\).*/\1/p')
  [[ "$TOPIC" == __* || -z "$TOPIC" ]] && continue

  CURRENT=$(printf '%s' "$LINE" | sed -n 's/.*PartitionCount: \([0-9]*\).*/\1/p')

  if [[ -n "${PARTITIONS[$TOPIC]:-}" && "$CURRENT" -lt "${PARTITIONS[$TOPIC]}" ]]; then
    echo "scaling $TOPIC: $CURRENT -> ${PARTITIONS[$TOPIC]} partitions"
    "$BIN"/kafka-topics.sh --bootstrap-server "$BOOTSTRAP" \
      --alter --topic "$TOPIC" --partitions "${PARTITIONS[$TOPIC]}"
    CURRENT="${PARTITIONS[$TOPIC]}"
  fi

  # retention.bytes is enforced per partition: split the topic budget
  PER_PARTITION=$((TOTAL_RETENTION_BYTES / CURRENT))
  CONFIG="retention.ms=${RETENTION_MS},retention.bytes=${PER_PARTITION},segment.ms=${SEGMENT_MS},segment.bytes=${SEGMENT_BYTES}"
  echo "applying retention to $TOPIC ($CURRENT partitions): $CONFIG"
  "$BIN"/kafka-configs.sh --bootstrap-server "$BOOTSTRAP" \
    --alter --entity-type topics --entity-name "$TOPIC" \
    --add-config "$CONFIG"
done <<< "$DESCRIBE"
