# Cursor Operational Rules

This document defines operational rules for the Cursor AI agent used with the BlockDAG mirroring program. The goal is to ensure safe, reliable automation without hallucinations or unintended side effects.

1. **Clarify missing information**  
   - When a required detail (e.g. organisation slug, token name, branch name) is missing, Cursor must ask for it rather than guessing.  
   - If multiple defaults are possible, state an assumption and invite correction.

2. **No hallucinated actions**  
   - Do not invent repository names, tokens or endpoints.  
   - Only operate on repos discovered via the GitHub API or specified by the user.

3. **Source vs destination**  
   - Treat the source organisation (BlockDAG Network Labs) as **read-only**. Never push to, modify or delete source repos.  
   - Use the designated destination orgs (Strattice, BrainstormOnline, BlockDAG Engineering) for all create, update, delete and resync operations.  
   - Maintain separate PATs for each org; do not reuse a token across orgs.

4. **Context preservation**  
   - Remember which repositories have been processed in the current run and skip unchanged repos.  
   - Respect the state cache and policies defined in `state.py` (e.g. `delete_mode` and `include_archived`).  
   - Log all actions with timestamps and outcomes to aid debugging.

5. **Ask before destructive changes**  
   - Soft deletes (archiving and adding tombstone) are safe by default. Hard deletes must be gated behind a config flag and explicit user confirmation.  
   - Branch protection changes, visibility changes and default-branch renames should be logged and, if possible, confirmed by policy.

6. **Environmental separation**  
   - Do not leak secrets. Load tokens from environment variables or the `.env` file; never print them or commit them to the repository.  
   - When running via GitHub Actions, expect tokens to be provided via `secrets.*`.

7. **Error handling**  
   - On API failures or git errors, retry with exponential backoff.  
   - If still failing, mark the repo as degraded in the state cache and continue with others.  
   - At the end of the run, emit a summary of degraded repos and reasons.

Following these rules helps Cursor act autonomously and safely, ensuring the mirror stays in sync without unintended side effects.
