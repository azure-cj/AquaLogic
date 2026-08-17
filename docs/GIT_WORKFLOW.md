# AquaLogic Git Workflow

Status: Team workflow
Last reviewed: 2026-08-15

This repository uses `main` as the shared stable branch. Groupmates should work
on short-lived branches and open pull requests for review. Do not push directly
to `main` once more than one person is contributing.

## One-time setup for a groupmate

```powershell
git clone https://github.com/azure-cj/AquaLogic.git
cd AquaLogic
git switch main
git pull --ff-only origin main
```

They should configure their Git identity on their own machine:

```powershell
git config user.name "Their Name"
git config user.email "their-email@example.com"
```

Never commit passwords, API keys, `.env` files, or personal access tokens.

## Starting a task

Always branch from the latest `main`:

```powershell
git switch main
git pull --ff-only origin main
git switch -c feat/short-task-name
```

Recommended branch names:

- `feat/backend-device-ingestion`
- `feat/web-alert-history`
- `feat/mobile-api-client`
- `feat/esp32-temperature-reading`
- `fix/alert-deduplication`
- `chore/workspace-docs`

## Commit and push workflow

Inspect before staging:

```powershell
git status --short
git diff
```

Stage only the files belonging to the task. Avoid `git add .` when the working
tree contains work from multiple tasks or teammates:

```powershell
git add backend/app/routes/sensors.py backend/tests/test_sensors_alerts_public.py
git diff --cached
git commit -m "feat: add device sensor ingestion"
git push -u origin feat/backend-device-ingestion
```

Use focused commits with conventional prefixes such as `feat:`, `fix:`,
`docs:`, `test:`, `refactor:`, and `chore:`. A commit should explain one
coherent change and should include its tests or documentation when relevant.

## Pull request workflow

1. Push the branch and open a pull request into `main`.
2. Describe the behavior changed, files affected, validation run, and any
   hardware/environment assumptions.
3. Ask the relevant teammate to review: software changes need software review;
   device protocol or wiring changes need hardware review.
4. Resolve review comments and push additional commits to the same branch.
5. Merge only after checks pass and the relevant review is complete.
6. Delete the branch after merging.

Do not force-push `main`. Force-push is only acceptable on your own unpublished
feature branch, using `--force-with-lease` after a rebase.

## Updating a feature branch

If the branch is only yours:

```powershell
git fetch origin
git rebase origin/main
git push --force-with-lease
```

If multiple people share the branch, avoid rebasing it; merge the updated main
branch instead and coordinate before resolving conflicts.

## Software and hardware collaboration

Keep hardware and software changes independently reviewable:

1. Agree on [`HARDWARE_INTEGRATION_CONTRACT.md`](HARDWARE_INTEGRATION_CONTRACT.md)
   before implementing a live connection.
2. The software side adds a simulator, validation, and backend contract tests.
3. The hardware side adds firmware sensor reads and sends the agreed payload.
4. Run both sides against one test tank/device before any physical actuator
   test; the current v1 bridge does not require firmware changes.
5. Use a dedicated integration branch or pull request only when both sides are
   ready to connect.

The backend should own tank mapping, authentication, validation, persistence,
threshold evaluation, and alerts. The firmware should own sensor access,
calibration, retry buffering, and safe actuator behavior. Do not duplicate
business rules in both places without recording the reason.

## Current workspace warning

The current local tree contains mixed existing application changes. Do not run
`git add .` or commit the entire tree without first separating backend, web,
mobile, firmware, generated evidence, and documentation work. The current local
branch `chore/workspace-docs` was created for the workspace setup; it has not
been pushed yet.
