# Registry cleanup

Wand uses one SQLite Durable Object alarm (`CLEANUP`, instance `registry`), not a Cron Trigger. This works on the existing Workers Free plan and uses its normal request/storage allowances.

- Every hour: delete expired consent requests and pairing records, plus abandoned, unclaimed device registrations.
- Paired devices are retained, including offline devices. Audit-log retention stays with each device's existing alarm.
- Each run processes at most 500 records per category. A backlog schedules another run in one minute.
- Database failures retry after 5 minutes, doubling to a maximum of one hour. Retries continue until recovery. Cleanup is safe to repeat.

`GET https://api.getwand.app/healthz` starts the singleton if needed and reports `cleanup.last_success`, `cleanup.next_run` (Unix milliseconds), and `cleanup.failures`. It returns 503 after a failed run or when the last success is more than three hours old. New pairing requests also ensure the alarm is scheduled.

After deploying, call `/healthz`, wait a few seconds, and call it again. Confirm `last_success` is populated, `failures` is zero, and `next_run` is in the future. An initial 200 response without `last_success` means the first run has not yet been observed.

The config deliberately omits `triggers`, so deployment does not call Cloudflare's schedule API. An earlier attempt to delete Wand's legacy cron failed at the account limit (`PUT []`, error 10072). The retained `scheduled` callback only ensures the alarm exists; it does not perform cleanup or replace an existing alarm. Cleanup does not depend on that schedule. If its deletion is retried successfully, remove the compatibility callback too, leaving other projects' schedules untouched.
