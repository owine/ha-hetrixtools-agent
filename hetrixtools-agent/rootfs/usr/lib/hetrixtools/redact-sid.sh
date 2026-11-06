#!/usr/bin/env bash
# Pure filter: text on stdin -> the same text on stdout, with every occurrence
# of the SID shortened to its first six characters.
# Usage: redact-sid.sh SID < debug.log
#
# The run script pipes the agent's debug.log through this before it reaches
# the Log tab, which DOCS.md asks users to paste into public issues. The SID is
# the server's only credential. The agent's own patch already shortens it in
# the JSON it logs; this also covers lines the patch does not own and keeps
# working after a re-vendor that drops the patch.
set -euo pipefail

SID="${1:-}"
# The SID becomes a sed pattern, which is only safe because it is plain
# alphanumerics. Refuse anything else rather than pass the input through.
if [[ ! "$SID" =~ ^[A-Za-z0-9]{32}$ ]]; then
	echo "redact-sid: refusing a malformed SID; diagnostics suppressed" >&2
	exit 2
fi

exec sed "s/${SID}/${SID:0:6}…/g"
