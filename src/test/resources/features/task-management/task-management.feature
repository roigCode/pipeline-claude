@pending
Feature: Task management
  As a user of the to-do application
  I want to create a task
  So that I can keep track of the things I need to do

  # Requirement: Create a task

  Scenario: Create a task with all fields
    When a client creates a task with title "Buy milk", description "Two litres of semi-skimmed" and a due date 1 day after the current UTC date
    Then the response status is 201
    And the response body has title "Buy milk"
    And the response body has description "Two litres of semi-skimmed"
    And the response body has a due date 1 day after the current UTC date

  Scenario: Create a task with only a title
    When a client creates a task with title "Buy milk"
    Then the response status is 201
    And the response body has title "Buy milk"
    And the response body has no description
    And the response body has no due date

  # Requirement: Created task has an identifier, pending status and creation time

  Scenario: New task is pending and records its creation time
    When a client creates a task with title "Buy milk"
    Then the response status is 201
    And the response body has a non-empty id
    And the response body has status "PENDING"
    And the response body has a creation time in UTC between the request being sent and the response being received

  Scenario: Each new task receives a different identifier
    When a client creates a task with title "Buy milk"
    And a client creates another task with title "Buy milk"
    Then both responses have status 201
    And the two responses have different ids

  # Requirement: Rejected input is reported as a problem detail

  Scenario: Error response identifies the rejected field
    When a client creates a task without a title
    Then the response status is 400
    And the response content type is "application/problem+json"
    And the response body has status 400
    And the response body has an error for field "title" with a non-empty message

  # Requirement: Title is required

  Scenario: Missing title is rejected
    When a client creates a task without a title
    Then the response status is 400
    And the response body has an error for field "title"

  Scenario: Empty title is rejected
    When a client creates a task with title ""
    Then the response status is 400
    And the response body has an error for field "title"

  Scenario: Whitespace-only title is rejected
    When a client creates a task with a title of 3 spaces
    Then the response status is 400
    And the response body has an error for field "title"

  # Requirement: Title is trimmed and limited to 100 characters

  Scenario: Leading and trailing whitespace is removed from the title
    When a client creates a task with title "  Buy milk  "
    Then the response status is 201
    And the response body has title "Buy milk"

  Scenario: Title of 1 character is accepted
    When a client creates a task with title "A"
    Then the response status is 201
    And the response body has title "A"

  Scenario: Title of 100 characters is accepted
    When a client creates a task with a title of 100 "a" characters
    Then the response status is 201
    And the response body has a title of 100 "a" characters

  Scenario: Title of 101 characters is rejected
    When a client creates a task with a title of 101 "a" characters
    Then the response status is 400
    And the response body has an error for field "title"

  Scenario: Title of 100 characters surrounded by spaces is accepted
    When a client creates a task with a title of 100 "a" characters preceded by 2 spaces and followed by 2 spaces
    Then the response status is 201
    And the response body has a title of 100 "a" characters

  Scenario: Title of 100 emoji characters is accepted
    When a client creates a task with a title of 100 "😀" characters
    Then the response status is 201
    And the response body has a title of 100 "😀" characters

  # Requirement: Description is optional, trimmed and limited to 500 characters

  Scenario: Leading and trailing whitespace is removed from the description
    When a client creates a task with title "Buy milk" and description "  Two litres  "
    Then the response status is 201
    And the response body has description "Two litres"

  Scenario: Whitespace-only description is stored as no description
    When a client creates a task with title "Buy milk" and a description of 3 spaces
    Then the response status is 201
    And the response body has no description

  Scenario: Description of 500 characters is accepted
    When a client creates a task with title "Buy milk" and a description of 500 "d" characters
    Then the response status is 201
    And the response body has a description of 500 "d" characters

  Scenario: Description of 501 characters is rejected
    When a client creates a task with title "Buy milk" and a description of 501 "d" characters
    Then the response status is 400
    And the response body has an error for field "description"

  # Requirement: Due date is optional and cannot be in the past

  Scenario: Due date equal to the current date is accepted
    When a client creates a task with title "Buy milk" and a due date 0 days after the current UTC date
    Then the response status is 201
    And the response body has a due date 0 days after the current UTC date

  Scenario: Due date in the past is rejected
    When a client creates a task with title "Buy milk" and a due date 1 day before the current UTC date
    Then the response status is 400
    And the response body has an error for field "dueDate"

  Scenario: Due date that is not a valid calendar date is rejected
    When a client creates a task with title "Buy milk" and due date "2026-02-30"
    Then the response status is 400
    And the response body has an error for field "dueDate"

  Scenario: Due date that is not in YYYY-MM-DD format is rejected
    When a client creates a task with title "Buy milk" and due date "tomorrow"
    Then the response status is 400
    And the response body has an error for field "dueDate"
