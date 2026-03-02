ARG ES_VERSION=8.19.6
FROM docker.io/elasticsearch:${ES_VERSION}
RUN /usr/share/elasticsearch/bin/elasticsearch-plugin install --batch analysis-icu
USER elasticsearch
