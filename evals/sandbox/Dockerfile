# The Claude Code arm's workspace: a clone of posit-dev/devrel-io, plus enough
# tooling to query velocirepo's JSONL and DuckDB. The image carries no data
# dictionary, no registered measures, and no crawled site prose -- the raw repo
# is the whole context, which is the point of the comparison.
#
# Built from inst/devrel-io as the build context; see compose.yaml.
FROM python:3.12-bookworm

RUN apt-get update \
  && apt-get install -y --no-install-recommends jq \
  && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir duckdb pandas

# The velocirepo views read JSONL through read_json(), so the json extension is
# load-bearing; installing it here keeps the agent off the network for it.
RUN python -c "import duckdb; duckdb.sql('INSTALL json; LOAD json;')"

COPY . /workspace/devrel-io
WORKDIR /workspace/devrel-io

# Orientation only, and load-bearing: an appended data-analyst system prompt
# loses to Claude Code's own ~28k characters of software-engineering
# instruction, and without this the agent doesn't open the repository at all.
# Says nothing about schema, metric definitions, or the coverage and
# deduplication traps -- that is the semantic layer under comparison.
COPY <<'EOF' CLAUDE.md
# devrel-io

This repository is Posit's developer relations metrics collection: daily
adoption and engagement data for Posit's open source projects, gathered by
velocirepo from GitHub, PyPI, CRAN, Plausible, OpenVSX, and YouTube.

Your job here is to answer questions about that data. This repository is the
only source available to you -- there is no network access, and you should not
report figures from your own knowledge of these projects. If the collected data
can't answer a question, say so and say what is missing.
EOF

RUN echo CLAUDE.md >> .git/info/exclude
