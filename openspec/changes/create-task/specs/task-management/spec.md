# Spec Delta

## Purpose

Lets users of the to-do application keep track of the things they need to do by
managing tasks. It currently covers creating a task.

## ADDED Requirements

### Requirement: Create a task

The system SHALL allow a client to create a task by sending `POST /api/tasks` with a JSON
body containing a `title`, an optional `description` and an optional `dueDate`. On
success the system MUST respond with HTTP 201 and a JSON body containing the created task.

#### Scenario: Create a task with all fields
- **WHEN** a client creates a task with title "Buy milk", description "Two litres of semi-skimmed" and a due date one day after the current UTC date
- **THEN** the response status is 201
- **AND** the response body has title "Buy milk", description "Two litres of semi-skimmed" and that due date in `YYYY-MM-DD` format

#### Scenario: Create a task with only a title
- **WHEN** a client creates a task with title "Buy milk" and neither description nor due date
- **THEN** the response status is 201
- **AND** the response body has title "Buy milk", description `null` and due date `null`

### Requirement: Created task has an identifier, pending status and creation time

The response body of a created task MUST include a non-empty `id` that identifies the
task, a `status` equal to `PENDING`, and a `createdAt` field with the time the task was
created, as an ISO-8601 instant in UTC. Each created task MUST receive a different `id`.

#### Scenario: New task is pending and records its creation time
- **WHEN** a client creates a task with title "Buy milk"
- **THEN** the response status is 201
- **AND** the response body has a non-empty id
- **AND** the response body has status "PENDING"
- **AND** the response body has a creation time in UTC that is not before the request was sent and not after the response was received

#### Scenario: Each new task receives a different identifier
- **WHEN** a client creates two tasks with title "Buy milk"
- **THEN** both responses have status 201
- **AND** the two response bodies have different ids

### Requirement: Rejected input is reported as a problem detail

When a create-task request is rejected because of invalid input, the system MUST respond
with HTTP 400, content type `application/problem+json`, and an RFC 9457 problem detail
body with `status` 400 and an `errors` array. Each entry of `errors` MUST have a `field`
naming the rejected request field and a non-empty `message`. No task SHALL be created.

#### Scenario: Error response identifies the rejected field
- **WHEN** a client creates a task without a title
- **THEN** the response status is 400
- **AND** the response content type is "application/problem+json"
- **AND** the response body has status 400
- **AND** the response body has an error for field "title" with a non-empty message

### Requirement: Title is required

The `title` MUST be present and MUST contain at least one non-whitespace character.
Otherwise the request SHALL be rejected with an error for field `title`.

#### Scenario: Missing title is rejected
- **WHEN** a client creates a task without a title
- **THEN** the response status is 400
- **AND** the response body has an error for field "title"

#### Scenario: Empty title is rejected
- **WHEN** a client creates a task with title ""
- **THEN** the response status is 400
- **AND** the response body has an error for field "title"

#### Scenario: Whitespace-only title is rejected
- **WHEN** a client creates a task with a title of 3 spaces
- **THEN** the response status is 400
- **AND** the response body has an error for field "title"

### Requirement: Title is trimmed and limited to 100 characters

The system SHALL remove leading and trailing whitespace from the `title` and store and
return the trimmed value. After trimming, the title MUST have between 1 and 100
characters, counted as Unicode code points. A longer title SHALL be rejected with an
error for field `title`.

#### Scenario: Leading and trailing whitespace is removed from the title
- **WHEN** a client creates a task with title "  Buy milk  "
- **THEN** the response status is 201
- **AND** the response body has title "Buy milk"

#### Scenario: Title of 1 character is accepted
- **WHEN** a client creates a task with title "A"
- **THEN** the response status is 201
- **AND** the response body has title "A"

#### Scenario: Title of 100 characters is accepted
- **WHEN** a client creates a task with a title of 100 "a" characters
- **THEN** the response status is 201
- **AND** the response body has a title of 100 "a" characters

#### Scenario: Title of 101 characters is rejected
- **WHEN** a client creates a task with a title of 101 "a" characters
- **THEN** the response status is 400
- **AND** the response body has an error for field "title"

#### Scenario: Title of 100 characters surrounded by spaces is accepted
- **WHEN** a client creates a task with a title of 100 "a" characters preceded by 2 spaces and followed by 2 spaces
- **THEN** the response status is 201
- **AND** the response body has a title of 100 "a" characters

#### Scenario: Title of 100 emoji characters is accepted
- **WHEN** a client creates a task with a title of 100 "😀" characters
- **THEN** the response status is 201
- **AND** the response body has a title of 100 "😀" characters

### Requirement: Description is optional, trimmed and limited to 500 characters

The `description` MAY be omitted or `null`. When present, the system SHALL remove leading
and trailing whitespace; if nothing remains, the task MUST have no description and the
response returns `null`. After trimming, the description MUST have at most 500
characters, counted as Unicode code points, or the request SHALL be rejected with an
error for field `description`.

#### Scenario: Leading and trailing whitespace is removed from the description
- **WHEN** a client creates a task with title "Buy milk" and description "  Two litres  "
- **THEN** the response status is 201
- **AND** the response body has description "Two litres"

#### Scenario: Whitespace-only description is stored as no description
- **WHEN** a client creates a task with title "Buy milk" and a description of 3 spaces
- **THEN** the response status is 201
- **AND** the response body has description `null`

#### Scenario: Description of 500 characters is accepted
- **WHEN** a client creates a task with title "Buy milk" and a description of 500 "d" characters
- **THEN** the response status is 201
- **AND** the response body has a description of 500 "d" characters

#### Scenario: Description of 501 characters is rejected
- **WHEN** a client creates a task with title "Buy milk" and a description of 501 "d" characters
- **THEN** the response status is 400
- **AND** the response body has an error for field "description"

### Requirement: Due date is optional and cannot be in the past

The `dueDate` MAY be omitted or `null`. When present, it MUST be a valid calendar date in
ISO-8601 `YYYY-MM-DD` format and MUST NOT be earlier than the current date in UTC. A due
date equal to the current UTC date SHALL be accepted. An invalid or past due date SHALL
be rejected with an error for field `dueDate`.

#### Scenario: Due date equal to the current date is accepted
- **WHEN** a client creates a task with title "Buy milk" and a due date equal to the current UTC date
- **THEN** the response status is 201
- **AND** the response body has that due date

#### Scenario: Due date in the past is rejected
- **WHEN** a client creates a task with title "Buy milk" and a due date one day before the current UTC date
- **THEN** the response status is 400
- **AND** the response body has an error for field "dueDate"

#### Scenario: Due date that is not a valid calendar date is rejected
- **WHEN** a client creates a task with title "Buy milk" and due date "2026-02-30"
- **THEN** the response status is 400
- **AND** the response body has an error for field "dueDate"

#### Scenario: Due date that is not in YYYY-MM-DD format is rejected
- **WHEN** a client creates a task with title "Buy milk" and due date "tomorrow"
- **THEN** the response status is 400
- **AND** the response body has an error for field "dueDate"
