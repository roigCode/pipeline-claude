# Proposal

Source request: `requests/0001-create-a-task.md`

## Why

Users of the to-do application need to record the things they have to do. There is
currently no way to create a task, so this is the first capability the application
offers.

## What Changes

- New HTTP endpoint to create a task with a title, an optional description and an
  optional due date.
- The title is required; leading and trailing whitespace is removed and the result must
  have between 1 and 100 characters.
- The description is optional, has a maximum of 500 characters and is trimmed; a
  description that is empty after trimming is treated as absent.
- The due date is optional, is a calendar date and cannot be earlier than the current
  date in UTC.
- A created task starts with status `PENDING` and records its creation time.
- The response returns the created task, including its generated identifier.
- Invalid input is rejected with HTTP 400 and a `ProblemDetail` body that lists which
  fields were rejected.
- New database table to persist tasks.

## Capabilities

### New Capabilities

- `task-management`: lifecycle of to-do tasks. This change introduces only task
  creation; later requests (listing, viewing, editing, completing, deleting) will extend
  the same capability.

### Modified Capabilities

None.

## Impact

- New feature package `com.roigcode.app.task` (domain, application, web and persistence
  adapters).
- New public API: `POST /api/tasks`.
- New Flyway migration creating the `task` table.
- New acceptance feature file `src/test/resources/features/task-management/task-management.feature`.
- No new dependencies.

## Out of scope

Taken from the request:

- Listing, viewing, editing, deleting or completing tasks.
- Priorities, tags, categories, users and authentication.

Also not included, because the request does not ask for them:

- A `Location` header pointing to the created task (there is no endpoint to view a task).
- Statuses other than `PENDING`.

## Open questions

The following ambiguities in the request were raised with the requester during analysis
and answered. They are recorded here so reviewers can verify the specs against them.

1. **What is the due date: a calendar date or a point in time?**
   Answer: a calendar date (ISO-8601 `YYYY-MM-DD`). "In the past" means earlier than the
   current date in UTC; a due date equal to today is valid.
2. **How is an empty or whitespace-only description handled?**
   Answer: the description is trimmed like the title. If nothing remains, the task has no
   description (`null` in the response). The 500-character limit applies after trimming.
3. **How are characters counted for the 100 and 500 limits?**
   Answer: as Unicode code points (one emoji counts as one character).
4. **What does a "clear error" contain?**
   Answer: an HTTP 400 `ProblemDetail` with an additional `errors` array of
   `{field, message}` entries identifying each rejected field.

Remaining items, not blocking, to confirm during review:

5. "Leading and trailing spaces" is interpreted as leading and trailing whitespace
   (spaces, tabs, line breaks), the same rule for title and description.
6. A `dueDate` value that is not a valid calendar date (for example `2026-02-30` or
   `tomorrow`) is rejected with the same 400 error format, identifying the `dueDate` field.
