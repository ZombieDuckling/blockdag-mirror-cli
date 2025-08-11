# BlockDAG Repository Mirroring MVP

This repository contains a **minimal viable product (MVP)** implementation of the
BlockDAG mirroring system described in the design documents and diagram.  Its
purpose is to mirror all repositories from a single **source GitHub organisation**
into three separate **destination organisations** on a regular schedule.  This
MVP focuses on correctness and clarity rather than performance or
completeness—it implements the core CRUD operations and basic logging but
omits advanced features like soft deletion, weekly deep resync and
notification hooks.  The code is extensively commented to explain each step.

## Overview

At a high level, the mirroring process looks like this:

1. **List repositories** in the source organisation using the GitHub CLI (`gh`).
2. **Create** missing repositories in each destination organisation (preserving
   visibility).  The script uses Personal Access Tokens (PATs) with admin
   privileges to create repositories.
3. **Fetch** the latest changes from the source and **push** a `--mirror`
   (force) update into each destination.  This propagates all branches, tags
   and other refs.
4. **Log** the outcome of each run into a timestamped log file under the
   `cache` directory for auditing.

The script is idempotent—running it repeatedly will not create duplicate
repositories or diverging histories.  You can schedule it with systemd or
cron (e.g. every 8 hours) to keep the destinations in sync.

Below is the architecture diagram for the full system, including
components that are not yet part of the MVP:

![BlockDAG Mirroring Diagram]({{file:diagram.png}})

## Prerequisites

Before you can run the script, you need:

* A Linux machine with **Git**, **gh** (GitHub CLI) and **jq** installed.
* Four **GitHub Personal Access Tokens (PATs)** with admin scopes:
  - `SRC_GH_TOKEN` – token for the **source** organisation (read‑only by
    convention; however it must allow `repo` scope so the script can list
    private repos).
  - `DST_STRAT_TOKEN` – token for the **Strattice** destination.
  - `DST_BRAIN_TOKEN` – token for the **BrainstormOnline** destination.
  - `DST_ENG_TOKEN` – token for the **BlockDAG Engineering** destination.
* Optional: adjust organisation names via environment variables if you are
  using different names.

## Running the script

1. Clone or copy this repository onto your runner machine.
2. Export the required environment variables in your shell.  For example:

   ```bash
   export SRC_GH_TOKEN=ghs_your_source_pat
   export DST_STRAT_TOKEN=ghs_your_strattice_pat
   export DST_BRAIN_TOKEN=ghs_your_brain_pat
   export DST_ENG_TOKEN=ghs_your_eng_pat
   export SRC_ORG=my-source-org            # optional override
   export DST_STRAT_ORG=my-strattice-org   # optional override
   export DST_BRAIN_ORG=my-brain-org       # optional override
   export DST_ENG_ORG=my-engineering-org   # optional override
   export ROOT=/var/mirror-root            # optional override
   ```

3. Make the script executable and run it:

   ```bash
   chmod +x mirror.sh
   ./mirror.sh
   ```

   The script will log its progress to a file under `cache/` (e.g.
   `run-20250811T120000Z.log`).  You can monitor this file to verify that
   repositories are being mirrored.

4. **Scheduling:**  To mirror automatically every 8 hours, create a systemd
   timer unit.  An example service and timer is included in the documentation
   of the original design (not in this MVP).  Alternatively, add a cron entry
   such as:

   ```cron
   0 */8 * * * /path/to/mirror.sh >> /srv/mirrors/cache/cron.log 2>&1
   ```

## Structure

```
blockdag_mirror_mvp/
├─ mirror.sh       # main script, documented and idempotent
├─ README.md       # this file
└─ diagram.png     # architecture overview
```

* `mirror.sh` – a Bash script implementing the core CRUD operations.
  Internally, it calls helper functions to ensure repositories exist,
  clone/fetch/push mirrors and log the results.  The script uses `gh` and
  `jq` rather than direct API calls for simplicity.
* `diagram.png` – the BlockDAG mirroring architecture in clear layout, used
  for reference.

## Limitations and next steps

This MVP is intentionally minimal.  The following features are planned but
not yet implemented:

* **Soft deletion**: when a repository is removed from the source, archive the
  corresponding destinations and add a `MIRROR_TOMBSTONE.md` pointing back to
  history rather than deleting outright.
* **Weekly deep resync**: periodically re‑clone all bare mirrors, fetch all
  Git LFS objects and verify branch protection settings.
* **State caching**: use a SQLite or JSON file to record the last mirrored
  commit and other metadata.  This can make incremental runs faster and
  enable drift detection.
* **Branch protection enforcement**: after pushing the mirror, call the
  GitHub API to enforce branch protection rules (require pull requests,
  disallow force pushes, etc.).
* **Notifications**: integrate with Slack or email so that errors or drift
  repair events trigger alerts.  Cursor AI’s agent to‑do lists and Slack
  integration could also be used here【840176998988316†L185-L190】.

## Using Cursor AI during development

If you use [Cursor](https://cursor.com), an AI‑assisted code editor, it can
streamline development:

* **Improved agent tools**: Cursor’s agent can read full files and explore
  directory trees, making it easier to understand large codebases【840176998988316†L36-L47】.
* **GitHub pull request support**: you can tag `@Cursor` in a PR comment to
  have the agent apply fixes and push a commit【840176998988316†L78-L82】.  This
  allows you to iterate on the script collaboratively.
* **To‑do lists and planning**: Cursor’s agent can plan long tasks by
  breaking them into steps and updating a structured to‑do list【840176998988316†L185-L190】.
  You can use this to manage outstanding features (soft delete, state
  caching, etc.).

While Cursor is not required to run this script, its latest features make it
a productive environment for extending and maintaining the system.

## License

This MVP is provided as an example and is released into the public domain.