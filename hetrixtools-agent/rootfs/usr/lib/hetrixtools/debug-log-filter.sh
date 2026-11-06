#!/usr/bin/env bash
# Pure filter: the agent's debug.log on stdin -> what the Log tab may show.
# Usage: debug-log-filter.sh SID < debug.log
#
# The run script pipes debug.log through this before it reaches the Log tab,
# which DOCS.md asks users to paste into public issues. Two things are made
# safe on the way:
#
# - The SID, the server's only credential, is shortened to its first six
#   characters. The agent's own patch already does this for the JSON it logs;
#   this also covers lines the patch does not own and keeps working after a
#   re-vendor that drops the patch.
# - Control characters other than tab and newline become "?". debug.log holds
#   raw probe output, which comes from the network: an escape sequence would
#   otherwise reach the reader's terminal, and a carriage return could
#   overwrite the start of a line. That includes the C1 controls as UTF-8
#   encodes them (U+0080-U+009F, such as CSI). A CRLF line end just loses its
#   carriage return.
set -euo pipefail

SID="${1:-}"
# The SID becomes a sed pattern, which is only safe because it is plain
# alphanumerics. Refuse anything else rather than pass the input through.
if [[ ! "$SID" =~ ^[A-Za-z0-9]{32}$ ]]; then
	echo "debug-log-filter: refusing a malformed SID; diagnostics suppressed" >&2
	exit 2
fi

# Byte-wise (LC_ALL=C), so the C1 pattern matches the two UTF-8 bytes and
# other UTF-8 passes through untouched.
LC_ALL=C sed -e "s/${SID}/${SID:0:6}…/g" -e $'s/\r$//' -e $'s/\xc2[\x80-\x9f]/?/g' \
	| tr '\000-\010\013-\037\177' '?'
