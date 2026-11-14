# 0001 - Create a task

## Context

As a user of the to-do application, I want to create a task so that I can keep track of
the things I need to do.

## Requirements

- A task has a title, an optional description and an optional due date.
- The title is required. Leading and trailing spaces are removed, and after that it must
  have between 1 and 100 characters.
- The description is optional and has a maximum of 500 characters.
- The due date is optional and cannot be in the past.
- A new task starts as pending and records when it was created.
- The response returns the created task, including its identifier.

## Acceptance criteria

- Creating a task with valid data returns it with status pending and its creation time.
- A missing or blank title is rejected with a clear error.
- A title longer than 100 characters after removing spaces is rejected.
- A description longer than 500 characters is rejected.
- A due date in the past is rejected.

## Out of scope

Listing, viewing, editing, deleting or completing tasks. Priorities, tags, categories,
users and authentication.
