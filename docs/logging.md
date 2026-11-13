---
review_status: self_reviewed
approval_status: not_approved
---

# Logging

## Locations

Upshot writes application events to `~/Library/Logs/Upshot/upshot.log` and Apple's unified log. The subsystem is `co.chrisyork.upshot`. Categories identify application, capture, annotation, recording, library, quick_access, settings, automation, rendering, crash, logging, and verification events.

Crash records use a separate preopened file, `~/Library/Logs/Upshot/upshot-crash-<pid>-<session_id>.log`. This descriptor is independent of the background event writer and its process lock.

The file rotates before an append would exceed 5 MiB. Three backups, `upshot.log.1` through `upshot.log.3`, retain earlier events. The newest backup is `.1`. Crash files retain the independently written exception and breadcrumbs; ordinary log rotation does not move or remove their descriptors. Files use owner-only permissions. A process lock coordinates concurrent writers and rotation.

```bash
/usr/bin/log show --last 30m --style compact --predicate 'subsystem == "co.chrisyork.upshot"'
tail -200 "$HOME/Library/Logs/Upshot/upshot.log"
```

## Event Format

Each event occupies one physical line:

```text
2026-11-13T05:45:23.497Z area=capture event=capture_completed duration="0.04 seconds" operation_id="..." outcome="success" pid="123" session_id="..." type="area"
```

Timestamps use ISO 8601 in UTC. Fields use `key="value"`. Backslashes, quotes, tabs, carriage returns, and newlines are escaped. `session_id` identifies one process execution; `pid` identifies the operating system process. Home-directory paths use `~`. Library identifiers are hashed because recording identifiers can contain paths.

`AppLog.event` attempts one try-lock and enqueues the event in a queue with capacity for 1,024 events. A serial background queue formats the event and writes the same public, sanitized line to both destinations. The caller never waits for the file writer or a lock. A full or contended queue drops the event and increments atomic counters; `event=log_events_dropped` records the count when the writer resumes. Scrolling frame events use `AppLog.unifiedEvent` and produce no file append. Explicit `flush` calls wait at most five seconds. Each area has its own `Logger`. Failure events use the error level, and other queued events use the notice level. Crash records bypass unified logging and write directly to the independent crash descriptor. Dynamic values use explicit public privacy after the caller selects non-sensitive fields. Capture processing and automation completion events include outcome, duration, and operation identifier. Existing feature events provide progress, configuration, counts, geometry, and failure context.

Screenshot pixels, recognized text, clipboard contents, keystroke contents, credentials, user-selected filenames, and raw error descriptions are excluded. Errors contain the NSError domain and code. Exception reasons preserve recognized Foundation nil-dictionary messages and the verification exception. Other exception reasons are reduced to a category or `redacted_exception_reason`, because framework reasons can embed document or clipboard contents. MetricKit records include numeric exception details and the call-stack tree; the full diagnostic payload and exception arguments are excluded.

## Crash Records

`UpshotApplication.reportException` routes AppKit-caught event and drawing exceptions to `event=appkit_exception`. The application principal class and normal startup instantiate this subclass. The override records the exception without invoking the default raw NSLog dump.

`event=uncaught_exception` contains the Objective-C exception name, sanitized reason, call stack, and `crash_id`. The handler attempts its own try-lock, snapshots breadcrumbs with a try-lock, and writes the crash record directly to the preopened crash descriptor. It never waits for the event writer, its process lock, or a flush. A 25 ms cooperative budget limits breadcrumb formatting and write retries. A kernel write can exceed that budget; the handler uses no fsync. `breadcrumb_status` records an unavailable snapshot or exceeded formatting budget. The uncaught exception handler leaves normal termination unchanged. AppKit retains its exception recovery behavior after reportException returns.

The process retains its last 200 persistent events in memory. The exception handler copies these events into `event=crash_breadcrumb` lines with the same `crash_id`. The breadcrumb `index` increases from oldest to newest. The `original` field contains the original event with its original timestamp, session identifier, and process identifier.

On launch, `event=system_crash_report` summarizes new regular Upshot or Upshot Dev `.ips` and `.crash` reports from `~/Library/Logs/DiagnosticReports`. Each report must identify an Upshot bundle identifier. `crash-report-checkpoint.json` records the completed scan time. `system_crash_scan_completed` records the number imported. Reports from other applications are ignored.

MetricKit registration occurs before application startup. The subscriber processes past diagnostic payloads and later diagnostic deliveries. `event=metrickit_crash` includes a diagnostic identifier, reporting period, signal, exception codes, available exception name, sanitized reason, and call-stack tree. `metrickit-checkpoint.json` prevents repeated imports of the same diagnostic. System delivery determines when diagnostics become available.

A signal, Swift trap, or process kill does not invoke the Objective-C handler. Accepted events reach the ordinary file asynchronously; an interrupted process can leave pending events unwritten. The background writer also retains the latest 200 persistent events in one JSON archive per process session under `~/Library/Logs/Upshot/Breadcrumbs`. Each archive records the process identifier, kernel-reported process start time, session identifier, and event timestamps. Archives are skipped if the process start time cannot be obtained. Unified-only events produce neither file appends nor archive entries.

System and MetricKit imports select archived breadcrumbs by process identifier or by a reporting interval containing archived event timestamps. The selection must identify exactly one archive. A supplied process start time disambiguates reused process identifiers. `breadcrumb_status` records `matched_process_identifier`, `matched_time_range`, `no_identity`, `no_match`, or `ambiguous_match`. Unmatched and ambiguous records contain zero breadcrumbs. `breadcrumb_pid`, `breadcrumb_process_start`, and `breadcrumb_session_id` identify a matched archive. MetricKit’s MXCrashDiagnostic does not supply a process identifier through the used API, so its payload’s reporting interval supplies the match constraint. A broad reporting interval spanning several process sessions produces no attached breadcrumbs.

To investigate a crash, locate its `crash_id`, read the associated breadcrumbs in increasing index order, and correlate the original `session_id` and `pid` with completion events. The system report filename locates the complete operating system report for symbolication. Keep all rotated files when collecting evidence.

## Offline Verification

These commands compile a separate executable with the production logger and crash subscriber. They do not launch Upshot or create windows.

```bash
mkdir -p .local/crash-logging
xcrun swiftc -swift-version 6 -default-isolation MainActor -parse-as-library \
  Upshot/AppLog.swift Upshot/CrashLogWriter.swift Upshot/ProcessBreadcrumbStore.swift Upshot/CrashDiagnostics.swift scripts/verify-logging.swift \
  -o .local/crash-logging/verify-logging
.local/crash-logging/verify-logging file verification-marker
/usr/bin/log show --last 3m --style compact --predicate 'subsystem == "co.chrisyork.upshot"'
.local/crash-logging/verify-logging queue .local/crash-logging/queue
.local/crash-logging/verify-logging rotation .local/crash-logging/rotation
.local/crash-logging/verify-logging scan .local/crash-logging/scan
.local/crash-logging/verify-logging metrickit .local/crash-logging/metrickit
.local/crash-logging/verify-logging blocked-crash .local/crash-logging/blocked-crash
.local/crash-logging/verify-logging exception
```

The file command verifies a readable marker and a home-directory path written with `~`. Rotation verifies concurrent writes and four readable files at a reduced threshold. Scan verifies modern and legacy report imports, bundle filtering, malformed input, and duplicate prevention; use a fresh scan directory for each run. The MetricKit command registers the production subscriber and consumes available past payloads. An empty payload array verifies registration without exercising crash ingestion.

The exception command intentionally exits with SIGABRT. The crash file’s `uncaught_exception` line must contain `name="NSInvalidArgumentException"`, `reason="Upshot logging verification exception"`, a call stack, and `breadcrumb_count="200"`. Its 200 breadcrumb lines must contain original event indices 25 through 224. This verifies that the oldest 25 events were discarded.

## References

- Apple. (n.d.). [Logger](https://developer.apple.com/documentation/os/logger).
- Apple. (n.d.). [OSLogPrivacy](https://developer.apple.com/documentation/os/oslogprivacy).
- Apple. (n.d.). [NSSetUncaughtExceptionHandler](https://developer.apple.com/documentation/foundation/nssetuncaughtexceptionhandler(_:)).
- Apple. (n.d.). [MXDiagnosticPayload](https://developer.apple.com/documentation/metrickit/mxdiagnosticpayload).
- Apple. (n.d.). [MXCrashDiagnostic](https://developer.apple.com/documentation/metrickit/mxcrashdiagnostic).
- Apple. (n.d.). [CTLineGetTypographicBounds](https://developer.apple.com/documentation/coretext/ctlinegettypographicbounds(_:_:_:_:)).
- Tane, B. (n.d.). [Logging sucks](https://loggingsucks.com/).
- Stripe. (2019). [Fast and flexible observability with canonical log lines](https://stripe.com/blog/canonical-log-lines).

## AppKit Exception Verification

```bash
xcrun swiftc -swift-version 6 -default-isolation MainActor -parse-as-library \
  Upshot/AppLog.swift Upshot/CrashLogWriter.swift Upshot/ProcessBreadcrumbStore.swift Upshot/UpshotApplication.swift \
  scripts/verify-appkit-exception.swift -o .local/crash-logging/verify-appkit-exception
.local/crash-logging/verify-appkit-exception
```

This separate executable posts an application-defined event and raises an Objective-C exception from sendEvent. AppKit’s event loop catches the exception and invokes the production reportException override. The executable checks the persisted appkit_exception and 200 breadcrumbs. It asserts a prohibited activation policy and zero windows.

## Process Correlation Verification

Run these commands with a fresh correlation directory:

```bash
.local/crash-logging/verify-logging archive .local/crash-logging/correlation first
.local/crash-logging/verify-logging archive .local/crash-logging/correlation second
.local/crash-logging/verify-logging correlation .local/crash-logging/correlation
```

The first two commands execute as distinct operating system processes and retain their own process start times and breadcrumbs. The third command exercises the production diagnostic recording path. It verifies historical PID and interval matches, unrelated intervals, ambiguous intervals, unknown process identifiers, missing identity, reused process identifiers, matching process start times, and incorrect process start times. Matching records contain the older process’s marker and exclude the newer process’s marker. Every rejected match contains zero breadcrumbs and its rejection status.
