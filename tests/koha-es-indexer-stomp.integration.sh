#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${KOHA_TEST_IMAGE:?Set KOHA_TEST_IMAGE to the Koha image}"
broker="koha-indexer-retry-$$"
cleanup() { docker rm -f "$broker" >/dev/null 2>&1 || true; }
trap cleanup EXIT
docker run -d --name "$broker" --hostname indexer-retry --add-host indexer-retry:127.0.0.1 \
  --network none --memory 512m --cpus 1 --pids-limit 1024 \
  --tmpfs /var/lib/rabbitmq:rw,nosuid,nodev \
  --mount "type=bind,src=${project_root}/rabbitmq/enabled_plugins,dst=/etc/rabbitmq/enabled_plugins,readonly" \
  -e RABBITMQ_SERVER_ADDITIONAL_ERL_ARGS='+S 2:2 +SDcpu 1 +SDio 1' \
  -e RABBITMQ_CTL_ERL_ARGS='+S 1:1 +SDcpu 1 +SDio 1' \
  -e RABBITMQ_DEFAULT_USER=compatcheck -e RABBITMQ_DEFAULT_PASS=isolated-test-only \
  "${RABBITMQ_TEST_IMAGE:-koha-rabbitmq-stomp-fix:4.4.0}" >/dev/null
ready=false
for attempt in {1..30}; do
  if docker exec --user rabbitmq "$broker" rabbitmq-diagnostics -q check_running >/dev/null 2>&1; then ready=true; break; fi
  sleep 2
done
[[ "$ready" == true ]] || { echo 'Isolated RabbitMQ failed to start' >&2; exit 1; }
docker run --rm --network "container:$broker" --entrypoint perl "$KOHA_TEST_IMAGE" -MNet::Stomp -e '
sub connect_client { my $c=Net::Stomp->new({hostname=>"127.0.0.1",port=>61613}); $c->connect({login=>"compatcheck",passcode=>"isolated-test-only",host=>"/"}); return $c }
sub subscribe { $_[0]->subscribe({destination=>"/queue/indexer-retry",ack=>"client-individual","prefetch-count"=>2}) }
my $p=connect_client(); my $c=connect_client(); subscribe($c);
$p->send_with_receipt({destination=>"/queue/indexer-retry",body=>"one"}) or die "send failed";
$p->send_with_receipt({destination=>"/queue/indexer-retry",body=>"two"}) or die "send failed";
my $a=$c->receive_frame({timeout=>5}); my $b=$c->receive_frame({timeout=>5});
die "missing batch" unless $a && $b && $a->body eq "one" && $b->body eq "two";
$c->ack({frame=>$a}); $c->nack({frame=>$b,requeue=>"true"});
my $retry=$c->receive_frame({timeout=>5});
die "requeue did not redeliver second frame" unless $retry && $retry->body eq "two" && ($retry->headers->{redelivered}//"") eq "true";
$c->disconnect; $c=connect_client(); subscribe($c);
my $after_restart=$c->receive_frame({timeout=>5});
die "unacknowledged message was not redelivered after disconnect" unless $after_restart && $after_restart->body eq "two" && ($after_restart->headers->{redelivered}//"") eq "true";
$c->ack({frame=>$after_restart});
print "PASS: individual ACK, requeue, redelivery header and disconnect recovery\n";
'
