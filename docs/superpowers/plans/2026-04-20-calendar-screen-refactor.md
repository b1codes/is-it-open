# CalendarScreen Refactoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Decompose the excessively large `CalendarScreen.dart` file (ClickUp Task 86b9gckq5) into smaller, reusable widget components housed in `lib/components/calendar/`, maintaining 1:1 visual and behavioral parity.

**Architecture:** Domain-Focused Breakdown (Approach A). The main screen logic will be extracted into focused sub-components (`CalendarSidebar`, `CalendarViewStack`, `CalendarHeader`, `CalendarEventTile`). State management (Bloc) wiring will remain in the main screen or be passed down appropriately via `BlocBuilder`s or providers without changing the underlying business logic.

**Tech Stack:** Flutter, Dart, flutter_bloc, calendar_view

---

## File Structure

We are breaking down `.worktrees/calendar-screen-refactor/frontend/lib/screens/calendar/calendar_screen.dart`.

**New Files (in `frontend/lib/components/calendar/`):**
- `calendar_sidebar.dart`: Houses the `_buildPlacesSidebar`, `_buildDeviceCalendarsSidebar`, `_buildRemoteSubscriptionSidebar`, and related dialogs.
- `calendar_header.dart`: Houses the `_buildCalendarOptions` and `_buildHeaderText` logic for toggling views and displaying dates.
- `calendar_view_stack.dart`: Houses the `_buildCalendar` logic (Month/Week/Day views).
- `calendar_event_tile.dart`: Houses `_buildEventTile`, `_buildFullDayEventWidget`, and the `_StackEventArranger`.

**Modified Files:**
- `frontend/lib/screens/calendar/calendar_screen.dart`: Will be stripped of the extracted logic and refactored to compose the new components.

---

## Task 1: Setup and Scaffold Component Files

- [ ] **Step 1: Create the target directory**
Run: `mkdir -p .worktrees/calendar-screen-refactor/frontend/lib/components/calendar`

- [ ] **Step 2: Create empty component files**
Run:
```bash
touch .worktrees/calendar-screen-refactor/frontend/lib/components/calendar/calendar_sidebar.dart
touch .worktrees/calendar-screen-refactor/frontend/lib/components/calendar/calendar_header.dart
touch .worktrees/calendar-screen-refactor/frontend/lib/components/calendar/calendar_view_stack.dart
touch .worktrees/calendar-screen-refactor/frontend/lib/components/calendar/calendar_event_tile.dart
```

- [ ] **Step 3: Commit scaffolding**
Run:
```bash
cd .worktrees/calendar-screen-refactor && git add frontend/lib/components/calendar/ && git commit -m "chore: scaffold calendar component files"
```

## Task 2: Extract CalendarEventTile Component

**Files:**
- Create/Modify: `frontend/lib/components/calendar/calendar_event_tile.dart`
- Modify: `frontend/lib/screens/calendar/calendar_screen.dart`

- [ ] **Step 1: Extract Event Tile Widgets and Arranger**
Move `_buildEventTile`, `_buildFullDayEventWidget`, and `class _StackEventArranger` from `calendar_screen.dart` into `calendar_event_tile.dart`.
Refactor the `_build*` methods into `StatelessWidget` classes: `CalendarEventTileWidget` and `FullDayEventWidget`.
Make `_StackEventArranger` public: `StackEventArranger`.

*Note: Ensure all necessary imports (Flutter material, calendar_view, models, etc.) are added to the new file.*

- [ ] **Step 2: Update CalendarScreen to use new widgets**
Import `package:is_it_open_frontend/components/calendar/calendar_event_tile.dart` in `calendar_screen.dart`.
Replace references to the old private methods/classes with the newly extracted public classes.

- [ ] **Step 3: Run tests to ensure no breakage**
Run: `cd .worktrees/calendar-screen-refactor/frontend && flutter test`
Expected: PASS

- [ ] **Step 4: Commit**
Run: `cd .worktrees/calendar-screen-refactor && git add frontend/lib/components/calendar/calendar_event_tile.dart frontend/lib/screens/calendar/calendar_screen.dart && git commit -m "refactor: extract CalendarEventTile component"`

## Task 3: Extract CalendarHeader Component

**Files:**
- Create/Modify: `frontend/lib/components/calendar/calendar_header.dart`
- Modify: `frontend/lib/screens/calendar/calendar_screen.dart`

- [ ] **Step 1: Extract Header Logic**
Move `_buildCalendarOptions`, `_formatHeaderDate`, and `_buildHeaderText` from `calendar_screen.dart` into `calendar_header.dart`.
Refactor `_buildCalendarOptions` into a `StatelessWidget` named `CalendarHeaderWidget`. It will need to accept `CalendarViewType currentView` and callbacks for changing the view (e.g., `final ValueChanged<CalendarViewType> onViewChanged;`).

- [ ] **Step 2: Update CalendarScreen**
Import `package:is_it_open_frontend/components/calendar/calendar_header.dart` in `calendar_screen.dart`.
Replace the `_buildCalendarOptions(...)` call with `CalendarHeaderWidget(currentView: ..., onViewChanged: ...)`.

- [ ] **Step 3: Run tests**
Run: `cd .worktrees/calendar-screen-refactor/frontend && flutter test`
Expected: PASS

- [ ] **Step 4: Commit**
Run: `cd .worktrees/calendar-screen-refactor && git add frontend/lib/components/calendar/calendar_header.dart frontend/lib/screens/calendar/calendar_screen.dart && git commit -m "refactor: extract CalendarHeader component"`

## Task 4: Extract CalendarViewStack Component

**Files:**
- Create/Modify: `frontend/lib/components/calendar/calendar_view_stack.dart`
- Modify: `frontend/lib/screens/calendar/calendar_screen.dart`

- [ ] **Step 1: Extract Calendar View Logic**
Move the `_buildCalendar` method from `calendar_screen.dart` into `calendar_view_stack.dart`.
Refactor it into a `StatelessWidget` named `CalendarViewStackWidget`.
It will need to accept `CalendarViewType currentView`, styling colors, and rely on `StackEventArranger`, `CalendarEventTileWidget`, and `FullDayEventWidget` (import them).

- [ ] **Step 2: Update CalendarScreen**
Import `package:is_it_open_frontend/components/calendar/calendar_view_stack.dart` in `calendar_screen.dart`.
Replace the `_buildCalendar(...)` call with `CalendarViewStackWidget(...)`.

- [ ] **Step 3: Run tests**
Run: `cd .worktrees/calendar-screen-refactor/frontend && flutter test`
Expected: PASS

- [ ] **Step 4: Commit**
Run: `cd .worktrees/calendar-screen-refactor && git add frontend/lib/components/calendar/calendar_view_stack.dart frontend/lib/screens/calendar/calendar_screen.dart && git commit -m "refactor: extract CalendarViewStack component"`

## Task 5: Extract CalendarSidebar Component

**Files:**
- Create/Modify: `frontend/lib/components/calendar/calendar_sidebar.dart`
- Modify: `frontend/lib/screens/calendar/calendar_screen.dart`

- [ ] **Step 1: Extract Sidebar Sections**
Move `_buildPlacesSidebar`, `_buildDeviceCalendarsSidebar`, `_buildRemoteSubscriptionSidebar`, `_displayName`, and `_showSubscriptionDialog` from `calendar_screen.dart` into `calendar_sidebar.dart`.
Create a main `StatelessWidget` called `CalendarSidebarWidget` that composes these sections within a `ListView` (or similar, matching the original structure).
Pass the `CalendarDataState dataState` down to this widget.

- [ ] **Step 2: Update CalendarScreen**
Import `package:is_it_open_frontend/components/calendar/calendar_sidebar.dart` in `calendar_screen.dart`.
Replace the sidebar assembly logic with `CalendarSidebarWidget(dataState: state)`.

- [ ] **Step 3: Run tests**
Run: `cd .worktrees/calendar-screen-refactor/frontend && flutter test`
Expected: PASS

- [ ] **Step 4: Commit**
Run: `cd .worktrees/calendar-screen-refactor && git add frontend/lib/components/calendar/calendar_sidebar.dart frontend/lib/screens/calendar/calendar_screen.dart && git commit -m "refactor: extract CalendarSidebar component"`

## Task 6: Final Verification & Cleanup

- [ ] **Step 1: Run Dart Format and Fixes**
Run:
```bash
cd .worktrees/calendar-screen-refactor/frontend
dart format .
dart fix --apply
```

- [ ] **Step 2: Run Full Test Suite**
Run: `flutter test`
Expected: PASS

- [ ] **Step 3: Commit Final Formatting**
Run: `cd .worktrees/calendar-screen-refactor && git add frontend/ && git commit -m "chore: format and fix after refactor"`
