---
name: release-notes
description:
  Draft or review React Native Bottom Sheet release notes from Git history, pull
  requests, issues, and previous releases.
---

# Release notes

## Style

- Start with `## Overview`, followed by lowercase metadata bullets in this
  order:
  - `addressed: #123, #456` (ascending issue numbers)
  - `external contributors: @username, @username`
- Omit inapplicable metadata bullets.
- Follow with `## Changes`. Use bullets for independent changes; use a numbered
  list when related API changes build on one another.
- Start change entries with verbs such as `Added`, `Fixed`, or `Improved`.
- Format API symbols, props, values, and package names in backticks. Identify
  Android-only or iOS-only behavior explicitly.
- Describe the observable behavior and relevant trigger, not implementation
  mechanics. Explain deprecation replacements and migration steps where needed.
- Exclude routine dependency bumps, formatting, release commits, tests, CI work,
  and internal refactors unless they affect consumers.
- Avoid marketing language, commit hashes, and contributor thanks outside the
  overview metadata.

## Evidence and comparison

1. Determine the requested target and baseline. Use the root `package.json` for
   the current version and inspect tags and published releases. Honor an
   explicit comparison such as `next.2` versus `next.1`; otherwise use the
   previous published version. Compare the baseline tag with the target tag, or
   with `HEAD` if the target tag does not exist yet.
2. Review all commits in that range, relevant diffs, and associated PRs. Check
   public TypeScript APIs, native behavior, and documentation as appropriate.
3. Identify addressed issues from both explicit PR links and a search of
   relevant open and closed issues. Read matching reports and comments: a fix
   may resolve an issue that its PR never mentions, and a resolved issue may
   remain open. Include issues resolved by the shipped changes, not merely
   related reports or PR numbers.
4. Verify external contributors using PR authorship and available repository or
   affiliation context. Do not infer external status solely from GitHub's
   `CONTRIBUTOR` label. Exclude bots.

## Stable releases after prereleases

For a stable release preceded by same-version `next` releases, read their
release notes in version order and combine the user-visible changes. Deduplicate
overlapping entries, preserve verified addressed issues and external
contributors. Inspect the diff from the final prerelease to the stable target
for additional changes. Use raw history to fill gaps in the prerelease notes.
