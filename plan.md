Sticky Notes for macOS — Engineering Specification

Document Control

* Project: Sticky Notes for macOS
* Document Type: Engineering Specification
* Audience: Software engineer / intern implementing v1
* Platform: macOS
* Primary Language: Swift
* UI Stack: AppKit + SwiftUI hybrid
* Editor Stack: NSTextView
* Version: v1.0 spec

⸻

1. Purpose

Build a native macOS sticky notes application where each note appears as a standalone Post-it-like desktop object with:

* custom window appearance
* custom window controls
* rich text editing
* per-note persistence
* note pinning
* note theming
* polished desktop-native behavior

This document is intended to be implementation-ready and detailed enough to hand to an intern.

⸻

2. Product Goals

2.1 Primary Goals

The app must:

1. Let the user create a new note instantly.
2. Represent each note as its own standalone native macOS window.
3. Render each note as a paper-like object rather than a standard Mac document window.
4. Support rich text in the note body.
5. Support custom title bar visuals and custom window controls.
6. Persist notes across app restarts.
7. Persist note frame, theme, and pin state.
8. Support multiple notes open simultaneously.
9. Feel lightweight, fast, and native.

2.2 Non-Goals for v1

Do not implement the following in v1 unless trivial:

* cloud sync
* cross-device sync
* iOS or iPad support
* collaboration
* note attachments
* handwriting or drawing
* OCR
* markdown mode
* tags
* folders
* note sharing workflows beyond simple export
* alarms/reminders
* AI features

⸻

3. Product Principles

3.1 UX Principles

The application should feel:

* immediate
* low friction
* desktop-native
* visually playful but not gimmicky
* less formal than a document editor
* more capable than a plain text widget

3.2 Technical Principles

The implementation should:

* use native macOS primitives where custom behavior matters
* avoid web-based rendering
* separate persistence from UI
* separate note data from note windows
* autosave without user intervention
* remain stable under many simultaneous note windows

⸻

4. Technical Architecture

4.1 Stack Decision

Use a hybrid AppKit + SwiftUI architecture:

* SwiftUI for app entry, settings, utility windows, and general UI where custom windowing is not critical
* AppKit for custom note windows and chrome
* NSTextView for the note body editor
* native persistence for note content and note metadata

4.2 Why This Stack

The two hardest requirements are:

1. fully custom window appearance/controls
2. robust rich text editing

These are best served by:

* AppKit window APIs for custom native desktop behavior
* NSTextView for mature macOS rich text editing

Pure SwiftUI is not the recommended implementation path for this app because it introduces unnecessary friction around the two most important areas.

⸻

5. App Scope

5.1 Supported Platforms

* macOS only
* target current modern macOS versions supported by the chosen Xcode baseline
* Apple Silicon and Intel if practical, though Apple Silicon optimization is sufficient for v1

5.2 Distribution Assumption

The app is assumed to be a local standalone desktop app.

No server dependency is required.

⸻

6. Core User Flows

6.1 Create a Note

1. User triggers New Note.
2. App creates a new note record.
3. App creates a new note window.
4. Window appears at default or cascaded location.
5. Note becomes key window.
6. Caret is ready in note body.

6.2 Edit a Note

1. User clicks inside note body.
2. Editor becomes first responder.
3. User types, formats, pastes, or edits content.
4. Changes are autosaved after debounce.

6.3 Move a Note

1. User drags header area.
2. Window moves.
3. Final frame is persisted after move debounce.

6.4 Resize a Note

1. User drags resize affordance or resizable edge/corner.
2. Window resizes.
3. Final frame is persisted after resize debounce.

6.5 Pin a Note

1. User clicks pin control.
2. Window moves to pinned behavior.
3. Pin state is persisted.

6.6 Close a Note

1. User clicks close control or uses close command.
2. Window closes.
3. Note data remains persisted.
4. Note can be reopened later.

6.7 Restore Notes on Relaunch

1. App launches.
2. Persisted notes are loaded.
3. Note windows are recreated.
4. Frames, themes, and pin states are restored.

⸻

7. Functional Requirements

7.1 Required Features

7.1.1 Notes

* create note
* open note
* close note
* persist note
* restore note
* duplicate note

7.1.2 Rich Text

* plain text typing
* bold
* italic
* underline
* font size changes
* text color
* paragraph alignment
* bulleted lists
* paste rich text
* undo/redo

7.1.3 Window Behavior

* custom window appearance
* custom controls
* move
* resize
* focus
* pin/unpin
* shadow
* per-note theme

7.1.4 Utility Surface

* All Notes window or equivalent list view
* reopen note from list
* search notes by title
* basic note management

⸻

8. UI Architecture

8.1 Main Components

The app consists of:

1. App shell
2. Note store
3. Window manager
4. Individual note windows
5. Note editor
6. All Notes utility window
7. Settings window
8. Menu/commands layer
9. Theme/rendering layer
10. Diagnostics layer

8.2 Ownership Model

Recommended ownership graph:

* AppCoordinator
    * NoteStore
    * WindowManager
    * PersistenceService
    * ThemeRegistry
* WindowManager
    * many NoteWindowController
* NoteWindowController
    * one note ID
    * one note content view
    * one editor coordinator
* AllNotesViewModel
    * subscribes to NoteStore

⸻

9. Data Model

9.1 Note Entity

Each note must contain the following persisted fields:

struct NoteRecord: Codable, Identifiable {
    let id: UUID
    var title: String
    var attributedBodyData: Data
    var themeID: String
    var isPinned: Bool
    var frame: PersistedRect
    var createdAt: Date
    var updatedAt: Date
    var isClosed: Bool
    var isArchived: Bool
}

9.2 Field Semantics

id

* immutable
* unique across all notes

title

* explicit header title
* may be empty
* empty title is allowed

attributedBodyData

* serialized rich text payload
* must preserve formatting for supported attributes

themeID

* references a theme registry entry
* invalid IDs must fall back to default theme

isPinned

* whether note is always-on-top relative to standard windows

frame

* persisted note window size and location

createdAt

* timestamp note was created

updatedAt

* timestamp of last meaningful persisted change

isClosed

* whether note window is currently closed but note still exists

isArchived

* optional hidden/deleted state
* for v1, can remain false unless archive functionality is implemented

9.3 PersistedRect Type

struct PersistedRect: Codable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

⸻

10. Theme Model

10.1 Theme Entity

struct NoteTheme: Equatable {
    let id: String
    let displayName: String
    let bodyBackgroundColor: NSColor
    let headerBackgroundColor: NSColor
    let titleTextColor: NSColor
    let bodyTextColor: NSColor
    let placeholderTextColor: NSColor
    let controlTintColor: NSColor
    let foldedCornerColor: NSColor
}

10.2 Required Built-In Themes

Implement these v1 themes:

* yellow
* pink
* blue
* green
* white

10.3 Theme Rules

* themes must preserve readable contrast
* theme choice is per-note
* theme persists across relaunch
* theme affects both header and body appearance
* theme must remain visually usable in light and dark system appearance

⸻

11. Windowing Model

11.1 Per-Note Window

Each note is its own AppKit window.

Recommended implementation:

* one NSWindow
* one NSWindowController
* one root content view for note UI

11.2 Window Behavior Requirements

Each note window must:

* be independently movable
* be independently resizable
* support custom visuals
* support shadow
* support focus
* support custom controls
* support pinning
* persist its frame

11.3 Window Style

The note must not visually resemble a standard document window.

The system title bar should be hidden or visually replaced such that the user perceives the note itself as the whole window.

11.4 Default Window Dimensions

* default width: 320
* default height: 320
* minimum width: 180
* minimum height: 140
* maximum size: practical, not hard capped unless implementation requires it

11.5 Window Positioning

For new notes:

* cascade from last created note if one exists
* otherwise center-ish or use a default origin within visible screen area

For restored notes:

* use persisted frame unless offscreen
* if offscreen, clamp to a visible screen

⸻

12. Window Visual Structure

12.1 Layout Anatomy

The note window content structure is:

NoteWindowRootView
├── PaperBackgroundView
├── HeaderBandView
│   ├── TitleField
│   └── ControlClusterView
├── EditorContainerView
│   └── ScrollView
│       └── NSTextView
└── ResizeAffordanceView

12.2 Visual Regions

Region A: Outer Paper Body

* rounded rectangle
* paper-like background color
* soft shadow

Region B: Header Band

* visually distinct strip at top
* acts as primary drag region
* contains title and controls

Region C: Body Editor

* rich text area
* fills most of note
* scrolls vertically when content overflows

Region D: Resize Affordance

* bottom-right corner cue
* visually subtle but discoverable

⸻

13. Header Specification

13.1 Header Dimensions

* height: 34 pt
* horizontal padding: 12 pt
* vertical visual centering of contents required

13.2 Header Responsibilities

The header must:

* visually anchor the note
* contain title
* contain controls
* act as draggable region where not covered by active subcontrols

13.3 Drag Behavior Rules

Dragging is allowed from:

* empty header space
* decorative header surface

Dragging is not allowed from:

* title edit field when editing interaction starts
* control buttons
* note body
* resize affordance

⸻

14. Title Field Specification

14.1 Purpose

The title field is an explicit single-line title distinct from the body.

14.2 Behavior

The title field must:

* support editing
* allow empty value
* show placeholder when empty
* truncate long content when not editing
* support keyboard commit on Return
* not overlap controls

14.3 Placeholder

Placeholder text:

* Untitled

Placeholder style:

* subdued
* readable
* clearly not persisted literal text unless user types it

14.4 Edit Rules

* single-line only
* no multiline
* Return commits edit
* Escape cancels current in-progress edit if practical
* losing focus commits current content

⸻

15. Custom Control Specification

15.1 Required Controls

Each note header must include:

* Close
* Pin / Unpin
* Theme / Color picker

Optional for v1.1:

* More actions
* Collapse
* Duplicate

15.2 Control Placement

Recommended placement:

* top-right cluster
* right padding: 12 pt
* spacing between controls: 8 pt

15.3 Control Visual Design

Close Control

* icon: small x or close glyph
* hover state: increased contrast
* pressed state: darker or inset effect

Pin Control

* icon: pin glyph
* selected state must be clearly visible
* hover and pressed states required

Theme Control

* icon: swatch or palette
* click opens popover palette

15.4 Control Hit Targets

Each control must have:

* minimum visually clickable area appropriate for desktop use
* no accidental overlap with drag region
* deterministic click behavior

15.5 Accessibility

Each control must expose:

* accessibility role: button
* label
* value/state if toggle
* keyboard focus support

⸻

16. Rich Text Editor Specification

16.1 Editor Choice

Use NSTextView hosted inside a scroll view.

16.2 Why NSTextView

The note body requires mature macOS-native text editing behavior including:

* attributed text
* undo/redo
* selection
* paste handling
* keyboard behavior
* spellcheck
* native editing semantics

16.3 Editor Container

The note body region must contain:

* NSScrollView
* document view as NSTextView

16.4 Editor Padding

Recommended content inset relative to body region:

* top: 10 pt
* left: 12 pt
* right: 12 pt
* bottom: 12 pt

16.5 Default Typing Attributes

Default body typing attributes:

* font: system font, 15 pt
* weight: regular
* text color: theme body text color
* paragraph spacing: light default
* alignment: left
* underline: none
* background: transparent unless text highlight feature is later added

16.6 Required Editing Features

The editor must support:

* typing plain text
* selection
* deletion
* cut/copy/paste
* undo/redo
* bold
* italic
* underline
* font size increase/decrease
* text color
* alignment
* bullets
* select all

16.7 Optional Features

May be deferred:

* links
* smart data detection
* checklist semantics
* background text highlights
* rich paste sanitization controls beyond default handling

16.8 Scrolling

When content exceeds visible area:

* vertical scrolling must occur
* typing must remain smooth
* selection must remain stable

Horizontal scrolling should be avoided by wrapping text naturally.

⸻

17. Formatting Command Specification

17.1 Access Paths

Formatting must be accessible via:

* menu commands
* keyboard shortcuts
* context menu

Optional:

* popover formatting UI

17.2 Required Commands

* Bold
* Italic
* Underline
* Increase Font Size
* Decrease Font Size
* Align Left
* Align Center
* Align Right
* Toggle Bullets
* Text Color

17.3 Formatting Scope Rules

When text selection exists:

* command applies to selected range

When no selection exists:

* command updates typing attributes for subsequent input

17.4 Persistence

Supported formatting must survive:

* autosave
* app termination
* app relaunch
* note reopen

⸻

18. Selection and Responder Behavior

18.1 Focus Rules

When user clicks inside note body:

* note window becomes key
* editor becomes first responder

When user clicks title:

* note window becomes key
* title becomes first responder

When user clicks a control:

* note window becomes key
* action fires
* editor focus may be lost depending on control interaction

18.2 Keyboard Routing

Keyboard commands must route to the active note/editor where relevant.

Undo/redo must be scoped to the current active note/editor.

⸻

19. Window Interaction Details

19.1 Dragging

The note must move when dragging from the designated drag region.

The note must not move when:

* selecting text
* editing title
* clicking controls
* resizing

19.2 Resizing

At minimum:

* bottom-right resize affordance must work

Optional:

* edge/corner resizing at all sides

19.3 Resize Affordance

Recommended visual:

* subtle folded paper corner
* or diagonal grip lines
* must not look like a standard OS chrome control

19.4 Minimum Size Rules

If user resizes below minimum size:

* clamp width and height
* preserve layout integrity
* prevent header overlap and unusable editor region

⸻

20. Pinning Model

20.1 Pin Semantics

Pinned means:

* note remains above normal windows

Unpinned means:

* note participates in normal z-order behavior

20.2 Pin Persistence

Pin state must persist per note.

20.3 Pin UX Rules

When pin is enabled:

* pin control visibly changes state immediately
* window behavior changes immediately

When pin is disabled:

* note returns to normal stacking behavior

⸻

21. Persistence Architecture

21.1 Required Persisted Data

Persist per note:

* note ID
* title
* body rich text data
* theme ID
* pin state
* frame
* timestamps
* closed/open state if used

21.2 Suggested Persistence Options

Any of the following is acceptable:

Option A: File-Based Persistence

* metadata in JSON
* rich text blobs as data files

Option B: SwiftData / Core Data

* one entity for note
* binary rich text data field
* metadata fields

Recommended for intern

Use whichever approach is simpler and least error-prone for the implementer, provided:

* note content is durable
* multi-note restore is reliable
* implementation remains debuggable

21.3 Save Triggers

Persist on:

* text edit after debounce
* title change on commit
* theme change immediately
* pin toggle immediately
* frame change after debounce
* app lifecycle flush on quit/background where relevant

21.4 Debounce Values

Recommended:

* text edits: 500 ms
* frame changes: 300 ms
* title commit: immediate
* theme change: immediate
* pin toggle: immediate

21.5 Flush on Exit

On app termination:

* all pending debounced saves must be flushed synchronously if safe

⸻

22. Restore Rules

22.1 App Launch

On app launch:

1. load all persisted notes
2. validate note records
3. repair/fallback invalid theme IDs
4. decode body data
5. recreate note windows
6. restore frames
7. restore pin states

22.2 Corruption Handling

If one note’s content is corrupted:

* app must not crash
* remaining notes must still load
* corrupted note should degrade gracefully if possible

Graceful fallback options:

* empty body with logged error
* plain text recovery if feasible
* note marked recoverable in diagnostics

22.3 Offscreen Frame Recovery

If a saved frame is offscreen:

* move it onto a visible display
* preserve approximate size if valid

⸻

23. Close, Delete, Archive Semantics

23.1 Close Behavior

In v1, closing a note window must not delete the note.

Close means:

* hide/remove the window
* retain note data
* mark note as closed if necessary

23.2 Delete / Archive

Delete/archive can be deferred.

If implemented:

* must be explicit
* must not be triggered by ordinary close
* should ideally support a recovery path

⸻

24. All Notes Utility Window

24.1 Purpose

A user must be able to find and reopen notes after closing their windows.

24.2 Recommended Implementation

Build an All Notes utility window in SwiftUI.

24.3 Required Capabilities

* list all notes
* search notes by title
* reopen closed notes
* create new note
* show excerpt/preview
* show theme chip or indicator
* show pinned state indicator

24.4 Recommended Columns / Fields

Each row should display:

* title
* excerpt preview
* updated timestamp
* theme indicator
* pinned indicator

24.5 Search Behavior

Search should match:

* title
* optionally plain text body excerpt if easy

⸻

25. Menu and Command Spec

25.1 App Menu

Include:

* About
* Settings
* Quit

25.2 File Menu

Include:

* New Note
* Close Note
* Duplicate Note
* Open All Notes
* Export Plain Text
* Export RTF

25.3 Edit Menu

Include:

* Undo
* Redo
* Cut
* Copy
* Paste
* Paste and Match Style
* Select All

25.4 Format Menu

Include:

* Bold
* Italic
* Underline
* Increase Font Size
* Decrease Font Size
* Align Left
* Align Center
* Align Right
* Toggle Bullets
* Text Color

25.5 Note Menu

Include:

* Pin / Unpin
* Change Theme
* Bring to Front

25.6 Shortcuts

Required:

* Cmd-N New Note
* Cmd-W Close Note
* Cmd-B Bold
* Cmd-I Italic
* Cmd-U Underline
* Cmd-, Settings

Optional:

* Cmd-Shift-A Open All Notes
* other shortcuts for formatting if chosen

⸻

26. Accessibility Specification

26.1 General Requirements

The app must support:

* VoiceOver
* keyboard-only navigation
* accessible labels for custom controls
* readable contrast

26.2 Focus Order

Recommended focus order within a note:

1. title
2. pin
3. theme
4. close
5. editor

Alternative order is acceptable if it remains consistent and logical.

26.3 Control Labels

Examples:

* Close note
* Pin note
* Unpin note
* Change note color
* Note title
* Note body

26.4 Editor Accessibility

The note body must behave as a standard accessible text editing surface.

26.5 Contrast

Every built-in theme must maintain readable contrast between:

* header and title text
* body background and body text
* controls and header background

⸻

27. Performance Requirements

27.1 Scale Targets

The app should comfortably handle:

* 100 persisted notes
* 30 open note windows
* note bodies up to roughly 100 KB of attributed content per note without major degradation

27.2 Responsiveness Targets

* New note creation should feel immediate
* Typing latency should be imperceptible under normal use
* Window drag and resize should remain smooth
* Restore should not freeze excessively for moderate note counts

27.3 Performance Constraints

Do not:

* save all notes on every keystroke
* re-render all windows when one note changes
* serialize the full store on each small mutation if avoidable
* couple editor updates to unnecessary SwiftUI re-render loops

⸻

28. Logging and Diagnostics

28.1 Logging Requirements

Implement logging for:

* note creation
* note persistence
* restore failures
* body decode failures
* frame restore adjustments
* save failures

28.2 Debug Features

Recommended debug-only tools:

* list persisted notes
* force flush saves
* show note IDs
* show frame bounds overlay
* dump attributed body decode result status

⸻

29. Error Handling

29.1 Save Failure

If save fails:

* do not crash
* keep note open in memory
* log the error
* retry on future save events if possible

29.2 Restore Failure

If restore fails for a note:

* continue restoring other notes
* log the failure
* degrade gracefully

29.3 Window Creation Failure

If a note record exists but its window cannot be created:

* keep note in the store
* allow recovery via All Notes if possible
* do not lose note data

⸻

30. Suggested Class Structure

30.1 Core Types

final class AppCoordinator: ObservableObject {
    let noteStore: NoteStore
    let windowManager: WindowManager
    let persistenceService: PersistenceService
}
final class NoteStore: ObservableObject {
    @Published private(set) var notes: [UUID: NoteRecord] = [:]
    func createNote() -> NoteRecord
    func updateTitle(noteID: UUID, title: String)
    func updateBody(noteID: UUID, attributedData: Data)
    func updateTheme(noteID: UUID, themeID: String)
    func updatePinned(noteID: UUID, isPinned: Bool)
    func updateFrame(noteID: UUID, frame: PersistedRect)
    func markClosed(noteID: UUID, isClosed: Bool)
    func duplicateNote(noteID: UUID) -> NoteRecord
}
final class WindowManager {
    private var windows: [UUID: NoteWindowController] = [:]
    func openWindow(for noteID: UUID)
    func closeWindow(for noteID: UUID)
    func reopenClosedWindow(for noteID: UUID)
    func restoreAllWindows()
}
final class NoteWindowController: NSWindowController, NSWindowDelegate {
    let noteID: UUID
}

30.2 Editor Types

final class NoteTextView: NSTextView {
}
final class NoteEditorCoordinator: NSObject {
}

30.3 Persistence Types

protocol PersistenceService {
    func loadNotes() throws -> [NoteRecord]
    func save(note: NoteRecord) throws
    func saveAll(notes: [NoteRecord]) throws
    func delete(noteID: UUID) throws
}

⸻

31. View Layout Specification

31.1 Root Note View Layout

Root Bounds

The note content fills the full custom window.

Header

* fixed height
* top aligned
* full width

Editor

* fills remaining height
* padded
* scrollable

Resize Affordance

* anchored bottom-right
* visually integrated into note design

31.2 Constraint Rules

* header pinned top/leading/trailing
* editor pinned below header
* editor pinned to bottom/leading/trailing
* controls pinned to right edge inside header
* title pinned left and constrained to avoid control overlap

⸻

32. State Management

32.1 Persisted State

Persist:

* note content
* note title
* theme
* pinned state
* frame
* closed/open state if used
* timestamps

32.2 Ephemeral State

Do not persist:

* current selection range
* hover states
* currently open popovers
* live undo stack
* temporary drag state

⸻

33. Event Flow Definitions

33.1 Typing Flow

1. user types
2. NSTextView updates text storage
3. coordinator receives change notification
4. note store updates note body data
5. note marked dirty
6. save debounce scheduled
7. persistence flush occurs after idle

33.2 Title Edit Flow

1. user edits title
2. title commit fires
3. note store updates title
4. save occurs immediately

33.3 Frame Update Flow

1. user moves/resizes window
2. frame changes continuously
3. debounce timer resets
4. final frame persisted after interaction settles

33.4 Theme Change Flow

1. user opens theme picker
2. user selects theme
3. note updates immediately
4. view refreshes
5. note saves immediately

33.5 Pin Flow

1. user clicks pin control
2. window behavior toggles
3. note store updates pinned state
4. state persists immediately

⸻

34. Testing Strategy

This section defines test cases that should be used during implementation and debugging.

⸻

35. Test Cases — Launch and Restore

AL-001

Precondition: 10 notes exist with distinct frames
Action: Launch app
Expected: All 10 notes reopen in their saved positions and sizes

AL-002

Precondition: 3 notes pinned, 2 notes unpinned
Action: Launch app
Expected: Pin state is preserved for all notes

AL-003

Precondition: One note has corrupted body data
Action: Launch app
Expected: App does not crash; remaining notes load

AL-004

Precondition: Pending unsaved edits within debounce window
Action: Quit app normally
Expected: Pending edits are flushed before termination

AL-005

Precondition: A saved frame is offscreen
Action: Launch app
Expected: Note is repositioned onto a visible screen

⸻

36. Test Cases — New Note Creation

NN-001

Action: Press Cmd-N
Expected: New note appears and becomes key window

NN-002

Action: Create 5 notes in sequence
Expected: Notes appear cascaded or offset, not perfectly overlapping

NN-003

Action: Create a new note
Expected: Default theme is applied and body is empty

NN-004

Action: Create a new note
Expected: Caret is ready in note body immediately

NN-005

Action: Create a note when many notes are already open
Expected: New note still opens correctly and receives focus

⸻

37. Test Cases — Window Dragging

WD-001

Action: Drag from empty header region
Expected: Note moves smoothly

WD-002

Action: Drag inside editor text region
Expected: Window does not move; text interaction occurs instead

WD-003

Action: Click-drag starting on a control
Expected: Control interaction occurs; window does not drag accidentally

WD-004

Action: Drag from title field when entering edit interaction
Expected: Title interaction wins; no unexpected drag

WD-005

Action: Drag note rapidly across screen
Expected: No lag, flicker, or control misplacement

⸻

38. Test Cases — Window Resizing

WR-001

Action: Drag resize affordance
Expected: Window resizes continuously

WR-002

Action: Resize below minimum size
Expected: Window clamps to minimum width and height

WR-003

Action: Resize note very narrow
Expected: Title truncates; controls remain visible

WR-004

Action: Resize note very short
Expected: Header remains usable and editor still renders safely

WR-005

Action: Resize note, then relaunch app
Expected: Updated size is restored

⸻

39. Test Cases — Pinning

PN-001

Action: Pin a note
Expected: Note floats above normal windows

PN-002

Action: Unpin a note
Expected: Note returns to normal stacking behavior

PN-003

Action: Pin a note and relaunch
Expected: Note remains pinned after restore

PN-004

Action: Pin multiple notes
Expected: All pinned notes remain interactable and stack predictably

⸻

40. Test Cases — Custom Controls

CC-001

Action: Hover close control
Expected: Hover state appears

CC-002

Action: Click close control
Expected: Only that note window closes

CC-003

Action: Click pin control
Expected: Pin state toggles visually and behaviorally

CC-004

Action: Click theme control
Expected: Theme picker opens correctly anchored

CC-005

Action: Keyboard navigate to controls
Expected: All controls are reachable and actionable

CC-006

Action: Use VoiceOver on controls
Expected: Labels and states are announced correctly

⸻

41. Test Cases — Title Field

TF-001

Action: Click title field
Expected: Title enters edit mode

TF-002

Action: Enter title text and press Return
Expected: Title commits and persists

TF-003

Action: Leave title empty and blur field
Expected: Placeholder appears

TF-004

Action: Enter very long title
Expected: Title truncates without overlapping controls

TF-005

Action: Edit title, quit, relaunch
Expected: Title persists

⸻

42. Test Cases — Editor Basic Typing

ED-001

Action: Type plain text
Expected: Characters appear with default typing attributes

ED-002

Action: Use arrow keys
Expected: Caret moves correctly

ED-003

Action: Select text with mouse
Expected: Selection highlight appears and behaves correctly

ED-004

Action: Undo typing
Expected: Last change is reverted

ED-005

Action: Redo typing
Expected: Reverted change is reapplied

ED-006

Action: Switch between two notes and type in both
Expected: Each note maintains independent text state

⸻

43. Test Cases — Rich Text Formatting

RF-001

Action: Select text and press Cmd-B
Expected: Selected text becomes bold

RF-002

Action: Select text and press Cmd-I
Expected: Selected text becomes italic

RF-003

Action: Select text and press Cmd-U
Expected: Selected text becomes underlined

RF-004

Action: Increase font size for selection
Expected: Only selected text changes size

RF-005

Action: Apply center alignment to paragraph
Expected: Paragraph aligns center and persists

RF-006

Action: Apply bullets
Expected: List styling appears and persists if supported

RF-007

Action: Mix multiple formatting styles in one note
Expected: Formatting round-trips through save/restore

⸻

44. Test Cases — Paste Behavior

PB-001

Action: Paste plain text
Expected: Plain text inserts correctly

PB-002

Action: Paste formatted text from another rich text source
Expected: Supported formatting is preserved

PB-003

Action: Paste very large text payload
Expected: App remains responsive

PB-004

Action: Paste malformed attributed content
Expected: App does not crash

PB-005

Action: Use Paste and Match Style
Expected: Incoming formatting is stripped

⸻

45. Test Cases — Persistence

PS-001

Action: Type in note, wait for debounce
Expected: Note body is persisted

PS-002

Action: Change theme
Expected: Theme persists after relaunch

PS-003

Action: Move note
Expected: Frame persists after relaunch

PS-004

Action: Resize note
Expected: Size persists after relaunch

PS-005

Action: Edit title and body, relaunch
Expected: Both title and body persist

PS-006

Action: Save failure occurs
Expected: App logs failure and retains in-memory state

⸻

46. Test Cases — All Notes Utility Window

AN-001

Action: Open All Notes window
Expected: All existing notes are listed

AN-002

Action: Close a note, then open it from All Notes
Expected: Note window reopens correctly

AN-003

Action: Search by title
Expected: Matching notes are filtered

AN-004

Action: Search by excerpt if implemented
Expected: Matching notes are filtered

AN-005

Action: Create note from All Notes
Expected: New note opens and list updates

⸻

47. Test Cases — Accessibility

AX-001

Action: Navigate note controls with VoiceOver
Expected: All controls are announced meaningfully

AX-002

Action: Navigate note entirely with keyboard
Expected: Title, controls, and body are reachable

AX-003

Action: Read note body via accessibility tools
Expected: Body behaves like standard text content

AX-004

Action: Evaluate all themes for readability
Expected: Contrast is acceptable

AX-005

Action: Toggle pin control via keyboard
Expected: State change is accessible and announced

⸻

48. Test Cases — Multi-Window Stability

MW-001

Action: Open 20 notes and edit one
Expected: Only that note updates

MW-002

Action: Close one of many open notes
Expected: Others remain stable

MW-003

Action: Undo in one note
Expected: Only that note’s content changes

MW-004

Action: Drag one note over another
Expected: Focus and z-order remain sane

MW-005

Action: Rapidly switch between note windows
Expected: No focus corruption or dropped edits

⸻

49. Debugging Checklist

49.1 If Window Will Not Drag

Check:

* drag region hit-testing
* overlapping invisible views
* editor frame extending into header
* incorrect responder handling
* missing move-window behavior wiring

49.2 If Editor Steals Header Clicks

Check:

* Auto Layout constraints
* z-order of editor vs header
* editor container clipping
* content insets/frame math

49.3 If Controls Are Unclickable

Check:

* transparent overlay intercepting clicks
* drag region covering controls
* control frames
* AppKit hit-testing behavior

49.4 If Formatting Does Not Persist

Check:

* attributed string serialization
* decode/encode class whitelist if applicable
* store update firing on edit
* save debounce not dropping pending state

49.5 If Pinning Does Nothing

Check:

* window level update logic
* toggle state persistence
* window type/flags
* reapplication on restore

49.6 If Typing Lags

Check:

* saving on each keystroke
* excessive bridge updates between AppKit and SwiftUI
* huge attributed string rewrites
* expensive store notifications

49.7 If Note Position Does Not Restore

Check:

* frame save timing
* coordinate conversion
* clamping logic
* restore order before/after showing window

⸻

50. Implementation Phases

Phase 1 — Core Note Window

Build:

* note model
* note store
* persistence
* single note window
* move/resize
* create/close/reopen
* restore frames

Exit criteria:

* multiple notes can be created
* notes persist and restore
* frame restoration works reliably

Phase 2 — Rich Text Editing

Build:

* NSTextView
* body persistence
* undo/redo
* formatting commands
* paste support

Exit criteria:

* rich text formatting works
* formatting persists
* typing is stable

Phase 3 — Custom Chrome and Controls

Build:

* header band
* title field
* custom close/pin/theme controls
* pinning
* polish visual states

Exit criteria:

* no standard chrome feel
* controls are stable and accessible
* note feels like a desktop object

Phase 4 — Utility Windows and Polish

Build:

* All Notes window
* search
* settings
* accessibility
* diagnostics
* final performance cleanup

Exit criteria:

* recoverability is good
* app is debuggable
* core accessibility is acceptable

⸻

51. Intern Guidance

51.1 Build Order

Recommended order:

1. data model
2. persistence service
3. note store
4. one simple AppKit note window
5. open/close/reopen
6. frame persistence
7. multiple note windows
8. custom header
9. custom controls
10. NSTextView integration
11. formatting commands
12. All Notes utility window
13. accessibility and polish

51.2 Rules

* do not couple persistence directly into views
* do not save on every keystroke
* do not use a web view
* do not attempt pure SwiftUI for the custom note/editor path
* keep each subsystem testable in isolation
* add a test note or repro note for every bug fixed

⸻

52. Final Build Recommendation

The application should be implemented as a native macOS AppKit/SwiftUI hybrid, with:

* AppKit handling note windows and custom chrome
* NSTextView handling note body editing
* SwiftUI handling utility surfaces and app shell
* local autosaved persistence
* an All Notes utility window for note recovery and management

This is the recommended implementation path for a stable v1 that matches the desired product behavior.

⸻

53. Definition of Done

The v1 implementation is complete when:

1. User can create, edit, move, resize, pin, close, and reopen notes.
2. Each note appears as a custom Post-it-like native window.
3. Rich text formatting works and persists.
4. Notes restore correctly on relaunch.
5. Closing a note does not delete it.
6. All Notes window allows reopening and searching notes.
7. Core keyboard shortcuts work.
8. Accessibility labels exist for custom controls.
9. App survives corrupted note data without crashing.
10. Multi-window usage is stable.