FROM ubuntu:latest

ENV DEBIAN_FRONTEND=noninteractive \
  TZ=Etc/UTC

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
  ca-certificates \
  git \
  tzdata \
  && rm -rf /var/lib/apt/lists/* \
  && git config --system init.defaultBranch main

WORKDIR /app

COPY --chmod=755 test.sh fork.sh ./
COPY . .

ENTRYPOINT ["sh", "test.sh"]
