#!/usr/bin/env bash
# Pure filter: `ip a` output on stdin -> comma-separated host NIC list on stdout.
# Usage: ip a | detect-interfaces.sh
#
# Why this exists: the vendored agent auto-detects interfaces itself (see the
# `ip a | grep BROADCAST ...` fallback in hetrixtools_agent.sh), but it builds
# that list ONCE per invocation and then samples it for the following minute.
# On a Home Assistant host, Docker creates and destroys `veth*` interfaces
# constantly, so the list goes stale mid-run: the per-NIC counter lookups come
# back empty and get interpolated straight into an awk program, spamming the log
# with syntax errors, while container traffic pollutes the per-NIC figures we
# report. Feeding the agent an explicit `NetworkInterfaces` list of real host
# NICs means its auto-detect never runs.
#
# Deliberately NOT `pipefail`: grep exits 1 when it matches nothing, which would
# abort the pipeline. Falling through to empty output instead makes the caller
# render an empty `NetworkInterfaces`, which the agent treats as "auto-detect" --
# i.e. we degrade to upstream behaviour rather than reporting no NICs at all.
set -eu

# Container/virtualisation plumbing, not host NICs:
#   veth*   Docker's ephemeral peer interfaces (the churn that breaks sampling)
#   br-*    Docker user-defined bridge networks (`br-<hex>`; a user's own `br0`
#           does not match, since the hyphen is Docker's own naming)
#   docker* Docker's default bridge
#   hassio  the Home Assistant Supervisor's bridge
#   virbr*  libvirt bridges
VIRTUAL_RE='^(veth|br-|docker|hassio|virbr)'

# The first six stages mirror the vendored agent's own detection verbatim, so
# real NICs are selected exactly as upstream would; only the exclusion is ours.
grep BROADCAST \
	| grep 'state UP' \
	| grep -v 'SLAVE' \
	| awk '{print $2}' \
	| awk -F ':' '{print $1}' \
	| awk -F '@' '{print $1}' \
	| grep -Ev "$VIRTUAL_RE" \
	| tr '\n' ',' \
	| sed 's/,$//'
