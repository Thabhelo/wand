# Finishing every task

The owner requires cleanup after every job, including testing and release verification.

- Track every temporary file, test window/tab, process, and changed setting as it is created. Keep disposable fixtures in a named task directory.
- Before reporting completion, close confirmed task-created test windows/tabs, stop task-owned temporary servers, and remove files created solely for that test. This routine cleanup is authorized by the owner; do not repeatedly ask for permission for known disposable artifacts.
- Inspect modified documents before closing. Discard only confirmed disposable test content; preserve user edits and ambiguous windows/files.
- Keep the installed app, the current signed release artifacts, source-controlled test fixtures, useful regression tests, credentials, audit logs, and persistent permissions. Never use broad process termination or delete unrelated temporary directories.
- Verify cleanup completed. If anything cannot safely be cleaned up, report its exact location and reason rather than claiming completion.

# Current status and documentation

- Read `docs/BUILD_STATUS.md` before reporting what is shipped or blocked. Verify drift-prone facts against current source, the published release and relevant tests.
- Keep `README.md` and `docs/BUILD_STATUS.md` aligned when releases, deployment or submission status changes. Put exact acceptance evidence in `docs/DESKTOP_ACCEPTANCE.md` and the current release note.
- Remove superseded status/checklist Markdown files and repair their references. Git history preserves old plans; do not append contradictory “current” status to them.
- Distinguish implementation, local testing, production-relay testing, simulation, published artifacts and native Muse integration. An untested path is not an unimplemented feature; a submitted application is not an approved connector.
