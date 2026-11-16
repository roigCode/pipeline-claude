# Design

## Context

The application is an empty Spring Boot 4.1 skeleton: no features, no Flyway migrations,
a `Clock` bean (`config/ClockConfiguration`, `Clock.systemUTC()`), ProblemDetail support
enabled (`spring.mvc.problemdetails.enabled`), Jackson 3 configured for UTC, and
Hibernate with `ddl-auto: validate`. ArchUnit enforces the hexagonal rules and the
coding rules of `AGENTS.md`; the Cucumber runner excludes `@pending` scenarios.

Motivation and scope: see `proposal.md`. Required behavior: see
`specs/task-management/spec.md`.

## Goals / Non-Goals

**Goals:**

- Put every input rule (trimming, lengths in code points, past due date) in the domain,
  so it is unit- and property-tested and mutation-tested by PIT.
- One error format for every rejected request, produced by a single
  `@RestControllerAdvice`.
- A database schema whose constraints match the domain rules.

**Non-Goals:**

- Any read, update or delete operation, or a `Location` header.
- Collecting the Bean Validation error and the domain errors into a single response
  (see Risks).

## Decisions

### D1. Package layout

Feature package `com.roigcode.app.task`, plus a small shared package for the error model
used by the single exception handler.

```
com.roigcode.app.shared/
├── domain/
│   ├── FieldViolation.java            # record(String field, String message)
│   └── InvalidInputException.java     # extends IllegalArgumentException; List<FieldViolation>
└── adapter/in/web/
    └── ApiExceptionHandler.java       # the single @RestControllerAdvice

com.roigcode.app.task/
├── domain/
│   ├── Task.java                      # record: id, title, description, dueDate, status, createdAt
│   ├── TaskId.java                    # record(UUID value); static generate()
│   ├── TaskTitle.java                 # record(String value); trims and validates
│   ├── TaskDescription.java           # record(String value); static Optional<TaskDescription> from(String)
│   └── TaskStatus.java                # enum { PENDING }
├── application/
│   ├── port/in/
│   │   ├── CreateTaskUseCase.java     # Task create(CreateTaskCommand command)
│   │   └── CreateTaskCommand.java     # record(String title, String description, LocalDate dueDate)
│   ├── port/out/
│   │   └── SaveTaskPort.java          # Task save(Task task)
│   └── service/
│       └── CreateTaskService.java     # implements CreateTaskUseCase; depends on SaveTaskPort and Clock
└── adapter/
    ├── in/web/
    │   ├── TaskController.java        # @RestController, POST /api/tasks
    │   ├── CreateTaskRequest.java     # record, Bean Validation annotations
    │   └── TaskResponse.java          # record
    └── out/persistence/
        ├── TaskJpaEntity.java         # @Entity @Table(name = "task"), implements Persistable<UUID>
        ├── TaskJpaRepository.java     # Spring Data JpaRepository<TaskJpaEntity, UUID>
        ├── TaskPersistenceMapper.java # Task <-> TaskJpaEntity
        └── TaskPersistenceAdapter.java# implements SaveTaskPort
```

The handler lives in `shared` rather than in `task` because `AGENTS.md` requires a single
advice for the whole application; it depends only on `shared.domain`, never on a
feature. Alternative rejected: an advice per feature (breaks the single-advice rule once a
second feature exists).

### D2. Domain rules

- `TaskTitle(String value)`: the compact constructor rejects `null`, applies
  `String.strip()` (removes leading/trailing Unicode whitespace) and requires
  `1 <= codePointCount <= 100`. Violations throw `InvalidInputException` with a single
  `FieldViolation` for field `title`.
- `TaskDescription.from(String raw)`: returns `Optional.empty()` for `null` or for a
  value that is empty after `strip()`; otherwise returns a `TaskDescription` with the
  stripped value, rejecting more than 500 code points (field `description`).
- `Task.create(TaskId id, String title, String description, LocalDate dueDate, Instant createdAt)`:
  builds title and description, rejects a `dueDate` earlier than
  `LocalDate.ofInstant(createdAt, ZoneOffset.UTC)` (field `dueDate`), and sets status
  `PENDING`. All violations of one call are collected and thrown together in one
  `InvalidInputException`, so the client sees every invalid domain field at once.
- `Task` record components `description` (`TaskDescription`) and `dueDate`
  (`LocalDate`) are nullable; `Task` exposes `Optional` accessors
  (`descriptionValue()`, `dueDateValue()`) for callers.
- `TaskId.generate()` uses `UUID.randomUUID()`. Alternative rejected: database-generated
  identifiers, which would make the domain object incomplete before persistence.
- Code points are counted with `String.codePointCount`, not `String.length()`, as decided
  in the proposal (Open question 3). Bean Validation `@Size` is therefore not used for
  lengths: it counts UTF-16 units and runs before trimming.

Error messages (literal, used by tests):

| Field | Condition | Message |
|---|---|---|
| `title` | missing, empty or blank | `must not be blank` |
| `title` | more than 100 characters after trimming | `must have at most 100 characters` |
| `description` | more than 500 characters after trimming | `must have at most 500 characters` |
| `dueDate` | before the current UTC date | `must not be in the past` |
| `dueDate` | not a valid `YYYY-MM-DD` date | `must be a valid date in YYYY-MM-DD format` |

### D3. Application service and time

`CreateTaskService.create(command)`:

1. `createdAt = clock.instant().truncatedTo(ChronoUnit.MICROS)`. Truncation makes the
   returned value identical to what PostgreSQL `timestamptz` stores (microsecond
   precision).
2. `Task.create(TaskId.generate(), command.title(), command.description(), command.dueDate(), createdAt)`.
3. Returns `saveTaskPort.save(task)`.

The "today" used for the due date rule is derived from the same `createdAt` instant, so
both values are consistent within one request. `LocalDate.now(...)` is never called
(ArchUnit rule on `now()`); the clock is injected.

### D4. HTTP contract

`POST /api/tasks`, request `Content-Type: application/json`.

Request body (`CreateTaskRequest`):

| Field | Type | Required | Bean Validation |
|---|---|---|---|
| `title` | string | yes | `@NotBlank` |
| `description` | string or null | no | none (domain rule) |
| `dueDate` | string `YYYY-MM-DD` or null | no | none; deserialized by Jackson to `LocalDate` |

```json
{ "title": "Buy milk", "description": "Two litres of semi-skimmed", "dueDate": "2026-11-16" }
```

Responses:

- **201 Created**, `Content-Type: application/json`, body `TaskResponse`:

  ```json
  {
    "id": "0b8f6a52-6d0e-4a59-9d3e-2f1f6f5d8c11",
    "title": "Buy milk",
    "description": "Two litres of semi-skimmed",
    "dueDate": "2026-11-16",
    "status": "PENDING",
    "createdAt": "2026-11-15T09:30:12.345678Z"
  }
  ```

  `description` and `dueDate` are present with value `null` when absent. `id` is a UUID
  string. `createdAt` is an ISO-8601 instant in UTC. No `Location` header.

- **400 Bad Request**, `Content-Type: application/problem+json`, RFC 9457 body:

  ```json
  {
    "type": "about:blank",
    "title": "Bad Request",
    "status": 400,
    "detail": "The request contains invalid fields.",
    "instance": "/api/tasks",
    "errors": [ { "field": "title", "message": "must not be blank" } ]
  }
  ```

`ApiExceptionHandler` extends `ResponseEntityExceptionHandler` (so every framework error is
also a `ProblemDetail`) and builds the 400 body above from three sources:

| Source | Exception | `errors` |
|---|---|---|
| Bean Validation on `CreateTaskRequest` | `MethodArgumentNotValidException` (override `handleMethodArgumentNotValid`) | one entry per field error |
| Domain rules | `InvalidInputException` (`@ExceptionHandler`) | the exception's violations |
| Unparseable `dueDate` | `HttpMessageNotReadableException` whose cause is a Jackson `DatabindException` with a property path (override `handleHttpMessageNotReadable`) | one entry for the last property name in the path, message `must be a valid date in YYYY-MM-DD format` when the target type is `LocalDate` |

A body that is not valid JSON at all keeps Spring's default 400 `ProblemDetail` without an
`errors` property; this case is not covered by the specs.

Jackson 3 (default in Spring Boot 4) writes `LocalDate` and `Instant` as ISO-8601
strings and includes `null` properties; no Jackson configuration change is needed.
`LocalDate` deserialization uses `ISO_LOCAL_DATE` (strict), so `2026-02-30` is rejected.

### D5. Persistence and Flyway migration

Migration `src/main/resources/db/migration/V1__create_task_table.sql`:

```sql
CREATE TABLE task (
    id          uuid          PRIMARY KEY,
    title       varchar(100)  NOT NULL CHECK (char_length(title) >= 1),
    description varchar(500)  NULL     CHECK (description IS NULL OR char_length(description) >= 1),
    due_date    date          NULL,
    status      varchar(20)   NOT NULL CHECK (status IN ('PENDING')),
    created_at  timestamptz   NOT NULL
);
```

- PostgreSQL `varchar(n)` and `char_length` count characters (code points), matching the
  domain limits.
- The "not in the past" rule is not a database constraint: it depends on the time of
  creation and must not fail for existing rows as time passes.
- `TaskJpaEntity` maps the columns one-to-one (`status` as `@Enumerated(EnumType.STRING)`
  or a plain `String`, `created_at` as `Instant`). It implements `Persistable<UUID>` with
  a transient `isNew` flag set when built from a new domain object, so `save` issues a
  single `INSERT` instead of a `SELECT` + `INSERT` (`merge`) for an assigned identifier.
- `TaskPersistenceAdapter.save` maps the domain `Task` to the entity, saves it and maps
  the result back. JPA entities never leave the package.

### D6. Dependencies

None. Everything uses starters already in `pom.xml` (webmvc, validation, data-jpa,
flyway, PostgreSQL driver) and the existing test stack.

### D7. Testing approach

- Unit + jqwik: `TaskTitle`, `TaskDescription`, `Task` (due date and status),
  `CreateTaskService` (fixed `Clock`, mocked `SaveTaskPort`).
- `@WebMvcTest(TaskController.class)` with `@MockitoBean CreateTaskUseCase`, importing
  `ApiExceptionHandler`, for the HTTP contract and every error source.
- `@DataJpaTest` with `TestcontainersConfiguration` for the migration, the adapter and
  the database constraints.
- Cucumber step definitions in `com.roigcode.app.acceptance` using `RestTestClient`.
  Relative dates in the feature file ("1 day before the current UTC date") are computed
  from the application's `Clock` bean, injected into the step definitions.

## Risks / Trade-offs

- [Bean Validation runs before the domain, so a request with a blank title and a
  501-character description reports only `title`] → Accepted: the specs require each
  rejected field to be identified, not all fields at once. The domain collects its own
  violations together.
- [Title presence is checked twice: `@NotBlank` at the boundary and in `TaskTitle`] →
  Intentional: `AGENTS.md` asks for Bean Validation at the boundary, and the domain must
  remain valid when called from elsewhere. Both produce the same message.
- [An acceptance scenario that runs exactly at UTC midnight could compute "today" in the
  step and "today" in the service on different dates] → Step definitions read the date
  from the same `Clock` bean immediately before the request; the window is a few
  milliseconds once a day and is accepted.
- [Field names in `FieldViolation` (`title`, `description`, `dueDate`) couple the domain
  to the API names] → They are the domain attribute names as well; if they ever diverge,
  the web adapter will map them.

## Migration Plan

First migration of the project (`V1`). Deploying runs it on startup through Flyway;
`ddl-auto: validate` checks the entity against it. Rollback: redeploy the previous
version and drop the empty `task` table manually if needed.
