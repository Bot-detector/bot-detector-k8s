#!/usr/bin/env bash
set -euo pipefail

BOOTSTRAP=kafka-service.kafka.svc:9092
BIN=${BIN:-/opt/bitnami/kafka/bin}

# retention: 7d, 1GB per topic split across partitions, segments 1d / 100MB

"$BIN"/kafka-topics.sh --bootstrap-server "$BOOTSTRAP" --alter --topic data.to_predict --partitions 4 \
  --config retention.ms=604800000,retention.bytes=250000000,segment.ms=86400000,segment.bytes=100000000

"$BIN"/kafka-topics.sh --bootstrap-server "$BOOTSTRAP" --alter --topic players.banned --partitions 4 \
  --config retention.ms=604800000,retention.bytes=250000000,segment.ms=86400000,segment.bytes=100000000

"$BIN"/kafka-topics.sh --bootstrap-server "$BOOTSTRAP" --alter --topic players.not_found --partitions 8 \
  --config retention.ms=604800000,retention.bytes=125000000,segment.ms=86400000,segment.bytes=100000000

"$BIN"/kafka-topics.sh --bootstrap-server "$BOOTSTRAP" --alter --topic players.scraped --partitions 4 \
  --config retention.ms=604800000,retention.bytes=250000000,segment.ms=86400000,segment.bytes=100000000

"$BIN"/kafka-topics.sh --bootstrap-server "$BOOTSTRAP" --alter --topic players.to_scrape --partitions 4 \
  --config retention.ms=604800000,retention.bytes=250000000,segment.ms=86400000,segment.bytes=100000000

"$BIN"/kafka-topics.sh --bootstrap-server "$BOOTSTRAP" --alter --topic predictions.to_insert --partitions 1 \
  --config retention.ms=604800000,retention.bytes=1000000000,segment.ms=86400000,segment.bytes=100000000

"$BIN"/kafka-topics.sh --bootstrap-server "$BOOTSTRAP" --alter --topic reports.to_insert --partitions 4 \
  --config retention.ms=604800000,retention.bytes=250000000,segment.ms=86400000,segment.bytes=100000000
