#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${KOHA_TEST_IMAGE:?Set KOHA_TEST_IMAGE to the Koha image to test}"
broker="koha-rmq44-compat-$$"
cleanup() { docker rm -f "$broker" >/dev/null 2>&1 || true; }
trap cleanup EXIT
trap 'exit 130' INT TERM
docker run -d --name "$broker" --hostname rmq44-compat --add-host rmq44-compat:127.0.0.1 \
  --ulimit nofile=65536:65536 --network none --memory 512m --cpus 1 --pids-limit 1024 \
  --tmpfs /var/lib/rabbitmq:rw,nosuid,nodev \
  --mount "type=bind,src=${project_root}/rabbitmq/enabled_plugins,dst=/etc/rabbitmq/enabled_plugins,readonly" \
  --mount "type=bind,src=${project_root}/rabbitmq/rabbitmq.conf,dst=/etc/rabbitmq/rabbitmq.conf,readonly" \
  -e RABBITMQ_SERVER_ADDITIONAL_ERL_ARGS='+S 2:2 +SDcpu 1 +SDio 1' \
  -e RABBITMQ_CTL_ERL_ARGS='+S 1:1 +SDcpu 1 +SDio 1' \
  -e RABBITMQ_DEFAULT_USER=compatcheck -e RABBITMQ_DEFAULT_PASS=isolated-test-only \
  "${RABBITMQ_TEST_IMAGE:-koha-rabbitmq-stomp-fix:4.4.0}" >/dev/null
ready=false
for attempt in {1..30}; do
 if docker exec --user rabbitmq "$broker" rabbitmq-diagnostics -q check_running >/dev/null 2>&1; then ready=true; break; fi
 sleep 2
done
[[ "$ready" == true ]] || { echo "Broker was not ready after ${attempt} attempts" >&2; docker logs --tail 20 "$broker"; exit 1; }
docker exec --user rabbitmq "$broker" rabbitmq-diagnostics -q server_version
docker exec "$broker" id rabbitmq
docker run --rm --network "container:$broker" --entrypoint perl "${KOHA_TEST_IMAGE:?Set KOHA_TEST_IMAGE to the Koha image to test}" -MNet::Stomp -MHTTP::Tiny -MJSON::PP -MMIME::Base64 -e '
 $|=1; my @clients;
 my $publisher=Net::Stomp->new({hostname=>"127.0.0.1",port=>61613});
 $publisher->connect({login=>"compatcheck",passcode=>"isolated-test-only",host=>"/"});
 my $h=HTTP::Tiny->new(timeout=>5);
 my $auth={Authorization=>"Basic ".MIME::Base64::encode_base64("compatcheck:isolated-test-only","")};
 for my $q (qw(default long_tasks elastic_index)) {
   my $c=Net::Stomp->new({hostname=>"127.0.0.1",port=>61613});
   my $f=$c->connect({login=>"compatcheck",passcode=>"isolated-test-only",host=>"/"});
   die "CONNECT failed" unless $f->command eq "CONNECTED";
   $c->subscribe({destination=>"/queue/koha_compat-$q",ack=>"client","prefetch-count"=>1});
   $publisher->send_with_receipt({destination=>"/queue/koha_compat-$q",body=>"{\"compatibility_probe\":true}",persistent=>"true","content-type"=>"application/json"}) or die "SEND receipt failed";
   my $msg=$c->receive_frame({timeout=>5});
   die "MESSAGE missing" unless $msg && $msg->command eq "MESSAGE";
   $c->ack({frame=>$msg});
   push @clients,$c;
   print "$q: CONNECT SUBSCRIBE SEND RECEIPT MESSAGE ACK ok\n";
 }
 sleep 8;
 for my $q (qw(default long_tasks elastic_index)) {
   my $r=$h->get("http://127.0.0.1:15672/api/queues/%2F/koha_compat-$q",{headers=>$auth});
   die "Queue API $r->{status}" unless $r->{success};
   my $d=decode_json($r->{content});
   die "Unexpected queue properties for $q" unless $d->{consumers} == 1 && $d->{durable} && $d->{type} eq "classic";
   print "$q: consumers=$d->{consumers} durable=$d->{durable} type=$d->{type}\n";
 }
 my $r=$h->get("http://127.0.0.1:15672/api/consumers/%2F",{headers=>$auth});
 die "Consumers API $r->{status}" unless $r->{success};
 my $consumers=decode_json($r->{content});
 die "Expected three consumers" unless @$consumers == 3;
 for my $c (@$consumers) {
   my $name=$c->{channel_details}{connection_name} // die "Missing connection name";
   $name =~ s/([^A-Za-z0-9_.~-])/sprintf("%%%02X",ord($1))/eg;
   my $url="http://127.0.0.1:15672/api/connections/$name";
   my $denied=$h->request("DELETE",$url);
   die "Unauthenticated close was not denied" unless $denied->{status} == 401 || $denied->{status} == 403;
   my $closed=$h->request("DELETE",$url,{headers=>$auth});
   die "Close API $closed->{status}" unless $closed->{success};
   print "$c->{queue}{name}: stale connection close HTTP $closed->{status}\n";
 }
 for my $q (qw(default long_tasks elastic_index)) {
   my $r=$h->get("http://127.0.0.1:15672/api/queues/%2F/koha_compat-$q",{headers=>$auth});
   die "Queue API after close failed" unless $r->{success};
   my $d=decode_json($r->{content});
   for my $attempt (1..12) {
     last if $d->{consumers} == 0;
     sleep 5;
     $r=$h->get("http://127.0.0.1:15672/api/queues/%2F/koha_compat-$q",{headers=>$auth});
     die "Queue API while waiting failed" unless $r->{success};
     $d=decode_json($r->{content});
     print "$q: consumers=$d->{consumers} after ",5*$attempt,"s\n";
   }
   die "Consumer remained after close" unless $d->{consumers} == 0;
   print "$q: consumer cleanup confirmed\n";
 }
 @clients=();
 my $replacement=Net::Stomp->new({hostname=>"127.0.0.1",port=>61613});
 $replacement->connect({login=>"compatcheck",passcode=>"isolated-test-only",host=>"/"});
 $replacement->subscribe({destination=>"/queue/koha_compat-default",ack=>"client","prefetch-count"=>1});
 $publisher->send_with_receipt({destination=>"/queue/koha_compat-default",body=>"replacement-probe",persistent=>"true"}) or die "Replacement publish failed";
 my $m=$replacement->receive_frame({timeout=>5});
 die "Replacement consumer failed" unless $m && $m->command eq "MESSAGE" && $m->body eq "replacement-probe";
 $replacement->ack({frame=>$m});
 print "Replacement consumer received and acknowledged a new message\n";
 $replacement->disconnect;
 $publisher->disconnect;
'
