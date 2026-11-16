# Tasks

Each task is one commit and must leave `./mvnw verify` passing. Class names, packages,
messages and the HTTP contract are defined in `design.md`; behavior in
`specs/task-management/spec.md`. In each task, write the named test first, see it fail,
then write the production code.

## 1. Domain

- [ ] 1.1 Create the shared error model `shared.domain.FieldViolation` and `shared.domain.InvalidInputException` (D1). Test first: `InvalidInputExceptionTest` (unit) asserting the exception exposes the violations it was built with, in order, and that its list cannot be modified. Verify: `./mvnw verify`.
- [ ] 1.2 Create `task.domain.TaskTitle` (D2). Test first: `TaskTitleTest` (unit) with literal boundary cases: `null`, `""`, 3 spaces, `"  Buy milk  "` → `"Buy milk"`, 1, 100 and 101 `a` characters, 100 `a` characters surrounded by 2 spaces on each side, 100 `😀` characters, 101 `😀` characters, each rejection with field `title` and the message from the D2 table. Plus `TaskTitlePropertiesTest` (jqwik): any string whose stripped form has 1–100 code points is accepted and equals its stripped form; any whose stripped form has 0 or more than 100 code points is rejected. Verify: `./mvnw verify`.
- [ ] 1.3 Create `task.domain.TaskDescription` (D2). Test first: `TaskDescriptionTest` (unit): `null`, `""` and 3 spaces → empty; `"  Two litres  "` → `"Two litres"`; 500 `d` characters accepted; 501 `d` characters rejected with field `description`; 500 `😀` characters accepted. Plus `TaskDescriptionPropertiesTest` (jqwik): blank input → empty; stripped length ≤ 500 code points → value equals stripped input; > 500 → rejected. Verify: `./mvnw verify`.
- [ ] 1.4 Create `task.domain.TaskId`, `task.domain.TaskStatus` and `task.domain.Task` with `Task.create` (D2). Test first: `TaskTest` (unit) with `createdAt = 2026-11-15T10:00:00Z`: new task has status `PENDING`, the given id and `createdAt`; due date `null`, `2026-11-15` and `2026-11-16` accepted; `2026-11-14` rejected with field `dueDate`; `createdAt = 2026-11-15T00:00:00Z` with due date `2026-11-14` rejected (UTC day boundary); blank title, 501-character description and past due date in one call produce three violations; `TaskId.generate()` returns different values on two calls. Plus `TaskPropertiesTest` (jqwik): for any `createdAt` and any day offset, the due date is accepted iff it is not before the UTC date of `createdAt`. Verify: `./mvnw verify`.

## 2. Persistence

- [ ] 2.1 Create the outbound port `task.application.port.out.SaveTaskPort`, the Flyway migration `V1__create_task_table.sql` (D5), and the persistence adapter: `TaskJpaEntity`, `TaskJpaRepository`, `TaskPersistenceMapper`, `TaskPersistenceAdapter`. Test first: `TaskPersistenceAdapterTest` (`@DataJpaTest`, `@Import(TestcontainersConfiguration.class)`, no in-memory database) asserting that saving a task with all fields and one with only a title returns an equal domain task, that the row is read back with the same values (including `created_at` at microsecond precision and `null` description and due date), and that the database rejects a 101-character title, a 501-character description and an unknown status. Verify: `./mvnw verify` (includes `AppApplicationTests` and Hibernate schema validation).

## 3. Application

- [ ] 3.1 Create the inbound port `CreateTaskUseCase` and `CreateTaskCommand`, and `CreateTaskService` (D3). Test first: `CreateTaskServiceTest` (unit, Mockito mock of `SaveTaskPort`, `Clock.fixed(Instant.parse("2026-11-15T10:00:00.123456789Z"), ZoneOffset.UTC)`) asserting the saved task has the trimmed title, status `PENDING`, `createdAt` `2026-11-15T10:00:00.123456Z` (truncated to microseconds) and a non-null id; the service returns what the port returns; a due date `2026-11-14` throws `InvalidInputException` for `dueDate` and the port is never called; due date `2026-11-15` is accepted. Verify: `./mvnw verify` (including the PIT threshold on `application`).

## 4. Web adapter

- [ ] 4.1 Create `TaskController`, `CreateTaskRequest`, `TaskResponse` and the single `@RestControllerAdvice` `shared.adapter.in.web.ApiExceptionHandler` (D1, D4). Test first: `TaskControllerTest` (`@WebMvcTest(TaskController.class)`, `@Import(ApiExceptionHandler.class)`, `@MockitoBean CreateTaskUseCase`, MockMvc) asserting: 201 with the D4 response body for a task with all fields and `null` description and due date for a title-only task; the command passed to the use case; for a missing title and for `""`, 400 `application/problem+json` with `status` 400 and an `errors` entry `{field: "title", message: "must not be blank"}` without calling the use case; a use case throwing `InvalidInputException` maps to 400 with its violations; `dueDate` values `"2026-02-30"` and `"tomorrow"` map to 400 with an `errors` entry for `dueDate`; a body that is not JSON returns 400 `application/problem+json`. Verify: `./mvnw verify`.

## 5. Acceptance

- [ ] 5.1 Implement the Cucumber step definitions for `src/test/resources/features/task-management/task-management.feature` in `com.roigcode.app.acceptance` (for example `TaskManagementSteps`), using `RestTestClient` and the application's `Clock` bean for relative dates and for the creation-time window (D7). Remove the `@pending` tag from the feature file; this is the only change allowed to the feature file. Verify: `./mvnw verify` runs all 22 scenarios of the feature and they pass.

## Workflow follow-up

- Archive the change after the spec gate and the implementation review pass.
