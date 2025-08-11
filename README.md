# BlockDAG Mirror CLI

This repository contains a Python CLI tool for mirroring all repositories from a source GitHub organization to multiple destination organizations. It implements the CRUD + RESYNC model described in our design document.

## Features

- Enumerates all repositories in the source org.
- For each destination org:
  - Ensures a repo of the same name exists with matching visibility and default branch.
  - Clones a bare mirror and pushes all refs using `git push --mirror --prune`.
- Soft-deletes repos removed from the source by archiving them and creating a `MIRROR_TOMBSTONE.md`.
- Optional state store (SQLite/JSON) to speed up runs.
- Extensible via subcommands and branch protection enforcement (placeholders included).

## Quick Start

1. **Install dependencies**:

   ```bash
   pip install -r requirements.txt
   ```

2. **Create a configuration file**:

   Copy `config.example.yaml` to `config.yaml` and edit the organization slugs and environment variable names used for tokens.

3. **Export tokens**:

   Create personal access tokens for the source and each destination org and export them using the names specified in the config file (e.g. `SRC_GH_TOKEN`, `DST_STRAT_TOKEN`, etc.).

4. **Run once**:

   ```bash
   python -m blockdag_mirror.cli run-once --config config.yaml
   ```

5. **Schedule**:

   Use a systemd timer or cron to run the `run-once` command every 8 hours. Alternatively, use GitHub Actions by creating a workflow file similar to `.github/workflows/mirror.yml`.

## Usage

The CLI is built with [Typer](https://typer.tiangolo.com/) and supports the following commands:

- `run-once` – Perform one full CRUD + RESYNC cycle.
- `crud read|create|update|delete` (planned) – Fine-grained control over each CRUD step.
- `resync full` (planned) – Force a complete re-clone and push of all repositories.

Detailed instructions can be found in the comments of each module.

## License

MIT License
