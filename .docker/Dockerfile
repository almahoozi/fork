FROM ubuntu:latest

ENV DEBIAN_FRONTEND=noninteractive \
  TZ=Etc/UTC

RUN apt-get update && apt-get install -y --no-install-recommends \
  dash \
  bash \
  mksh \
  git \
  tzdata \
  ca-certificates \
  && rm -rf /var/lib/apt/lists/* \
  && git config --system init.defaultBranch main

WORKDIR /app

COPY --chmod=755 test.sh fork.sh ./
COPY . .

ENTRYPOINT ["/bin/sh", "-c", "\
  rc=0; \
  for sh in /bin/sh /bin/dash /bin/mksh /bin/bash; do \
  echo \"--- Running with $sh ---\"; \
  if $sh -n test.sh && $sh test.sh -n; then \
  echo \"PASS: $sh\"; \
  else \
  echo \"FAIL: $sh\"; \
  rc=1; \
  fi; \
  done; \
  exit $rc"]
