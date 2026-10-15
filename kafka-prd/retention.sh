#!/usr/bin/env bash
set -euo pipefail

BOOTSTRAP=kafka-service.kafka.svc:9092
BIN=${BIN:-/opt/bitnami/kafka/bin}

MB=1000000
GB=$((1000*MB))
HOUR=$((60*60*1000))
DAY=$((24*HOUR))

# retention: 7d, 1GB per topic split across partitions, segments 1d / 100MB

"$BIN"/kafka-topics.sh --bootstrap-server "$BOOTSTRAP" --alter --topic data.to_predict --partitions 4 \
  --config retention.ms=$((7*DAY)),retention.bytes=$((GB/4)),segment.ms=$DAY,segment.bytes=$((100*MB))

"$BIN"/kafka-topics.sh --bootstrap-server "$BOOTSTRAP" --alter --topic players.banned --partitions 4 \
  --config retention.ms=$((7*DAY)),retention.bytes=$((GB/4)),segment.ms=$DAY,segment.bytes=$((100*MB))

"$BIN"/kafka-topics.sh --bootstrap-server "$BOOTSTRAP" --alter --topic players.not_found --partitions 8 \
  --config retention.ms=$((7*DAY)),retention.bytes=$((GB/8)),segment.ms=$DAY,segment.bytes=$((100*MB))

"$BIN"/kafka-topics.sh --bootstrap-server "$BOOTSTRAP" --alter --topic players.scraped --partitions 4 \
  --config retention.ms=$((7*DAY)),retention.bytes=$((GB/4)),segment.ms=$DAY,segment.bytes=$((100*MB))

"$BIN"/kafka-topics.sh --bootstrap-server "$BOOTSTRAP" --alter --topic players.to_scrape --partitions 4 \
  --config retention.ms=$((7*DAY)),retention.bytes=$((GB/4)),segment.ms=$DAY,segment.bytes=$((100*MB))

"$BIN"/kafka-topics.sh --bootstrap-server "$BOOTSTRAP" --alter --topic predictions.to_insert --partitions 1 \
  --config retention.ms=$((7*DAY)),retention.bytes=$GB,segment.ms=$DAY,segment.bytes=$((100*MB))

"$BIN"/kafka-topics.sh --bootstrap-server "$BOOTSTRAP" --alter --topic reports.to_insert --partitions 4 \
  --config retention.ms=$((7*DAY)),retention.bytes=$((GB/4)),segment.ms=$DAY,segment.bytes=$((100*MB))
