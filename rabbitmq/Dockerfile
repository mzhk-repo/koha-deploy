ARG RABBITMQ_VERSION=3-management
FROM docker.io/rabbitmq:${RABBITMQ_VERSION}
RUN rabbitmq-plugins enable --offline rabbitmq_stomp rabbitmq_web_stomp
USER rabbitmq
