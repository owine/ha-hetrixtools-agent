#!/usr/bin/env bash
# Decide whether a release may be built and pushed; print its version if so.
# Usage: release-gate.sh   (from a `release` event run)
# Env: TAG_NAME, PRERELEASE (the event's release.tag_name / release.prerelease),
#      GITHUB_SHA (the tagged commit), REPO (owner/name), GH_TOKEN for gh.
#
# Every job in build.yaml that pushes an image runs this first, not just init:
# "Re-run failed jobs" re-runs only the failed jobs and the ones after them,
# reusing init's old outputs. A failed release re-run after a newer one has
# shipped would otherwise push its image as `latest` again.
#
# This file comes from the tagged commit, so it stops mistakes; the
# release-tags ruleset is what stops anyone else tagging.
set -euo pipefail

semver='^[0-9]+\.[0-9]+\.[0-9]+$'

[[ "${TAG_NAME}" == hetrixtools-agent-v* ]] || {
	echo "::error::tag ${TAG_NAME} is not a release tag (hetrixtools-agent-vX.Y.Z)" >&2
	exit 1
}
version="${TAG_NAME#hetrixtools-agent-v}"
[[ "${version}" =~ ${semver} ]] || {
	echo "::error::tag ${TAG_NAME} gives version '${version}', expected X.Y.Z" >&2
	exit 1
}

# `latest` must never point at a prerelease.
[ "${PRERELEASE}" = false ] || {
	echo "::error::${TAG_NAME} is a prerelease; only full releases are built" >&2
	exit 1
}

# Only reviewed code is published: the tagged commit must already be on main.
# main is resolved to a SHA first, as promote does: a bare `main` in the
# compare would be ambiguous if a tag named main ever existed.
main_sha="$(gh api "repos/${REPO}/git/ref/heads/main" --jq .object.sha)"
status="$(gh api "repos/${REPO}/compare/${GITHUB_SHA}...${main_sha}" --jq .status)"
if [ "${status}" != identical ] && [ "${status}" != ahead ]; then
	echo "::error::release commit ${GITHUB_SHA} is not on main (${status}); not building it" >&2
	exit 1
fi

# `latest` only moves forward. config.yaml on that same main commit holds the
# version HA offers now (promote bumps it once a release ships), so an older
# release, re-run or published late, must not push `latest` back over it. The
# same version passes: promote then leaves config.yaml alone, as it already
# does.
current="$(gh api -H "Accept: application/vnd.github.raw" \
		"repos/${REPO}/contents/hetrixtools-agent/config.yaml?ref=${main_sha}" \
	| sed -nE 's/^version: "([^"]+)".*/\1/p')"
[[ "${current}" =~ ${semver} ]] || {
	echo "::error::no 'version: \"X.Y.Z\"' line in config.yaml on main (got '${current}')" >&2
	exit 1
}
newest="$(printf '%s\n%s\n' "${current}" "${version}" | sort -V | tail -n1)"
if [ "${newest}" != "${version}" ]; then
	echo "::error::release ${version} is older than ${current}, which HA already offers; not building it" >&2
	exit 1
fi

echo "${version}"
