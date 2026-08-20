# UI and UX Architecture

Qwen Prime keeps user-interface policy in a small set of shared models and
renderers. Views consume those sources of truth instead of redefining colors,
shortcuts, availability rules, formatting, or destructive-action behavior.

## Sources of truth

- `DesignTokens` and `MarkdownTheme` own theme roles, metrics, motion, and
  control sizing. Their contracts live in `ThemeColorUsageGateTests` and
  `VisualSystemAndFormattingTests`.
- `AppPreferences` and `AppPreferencesPersistence` own durable user settings
  and migration. `AppPreferencesAndCommandsTests` covers compatibility.
- `AppCommands` owns titles, shortcuts, help, and availability for app menus,
  prompt input, and the Shortcuts tab.
- `AppConfirmation`, `AppOperationErrorPresentation`, and
  `AppPresentationScope` own scene-specific alerts. Their behavior is covered
  by `ConfirmationPresentationScopeTests`.
- `AppState` and `RuntimeLifecycleAction` own runtime lifecycle and model
  profiles for Engine settings and Quick Settings.
- `PresentationFormatting` and `TokenEstimation` own counts, durations,
  throughput, and estimates for chat, tools, prompts, and MCP settings.
- `ToolName` and `WorkspacePathSanitizer` own tool identity and path-safe
  presentation for workspace brokers, MCP tools, and tool cards.

## Theme ownership

Renderer-facing colors come from the active `MarkdownTheme` or semantic roles
in `DesignTokens`. The theme owns the window and control surfaces as well as
the normal text, selection, and syntax colors. `DesignTokens` owns shared
status colors and adaptive behavior for Increased Contrast, Reduce
Transparency, and Reduce Motion.

Native macOS controls inherit the active theme tint from their renderer.
Settings navigation and contextual action popovers are rendered explicitly so
selection never falls back to the system accent color. The theme-usage gate
rejects raw palette colors, `Color.accentColor`, untinted native controls, and
native menu renderers in product views.

## View composition

`SettingsView` is only the settings-window shell. Each destination lives in a
focused tab file, and common form layout is provided by `SettingsComponents`,
`SettingsSectionLabel`, and `StandardFormControl`.

Chat disclosures share `DisclosureCardHeader`; copy interactions share
`CopyFeedbackButton`; contextual choices share `ThemedPopoverActionRow` and
`BottomAttachedPopoverContent`. These components own hit targets, focus and
hover states, icon rails, popover clearance, and accessibility labels.

Sidebar conversation cards use a full-card button target with a separate
actions control. Scope filters, search, New, conversation cards, and footer
actions sit on one explicit content rail rather than inheriting unrelated
native list gutters.

## State and interaction policy

`AppState` owns cross-scene application state. Its typed preferences are the
only durable UI settings. `AppCommands` supplies command titles, shortcuts,
help, and enabled state to the macOS menu, prompt input, and Shortcuts tab.
Escape requests one stop-generation command, Return sends once, and
Shift-Return inserts a newline.

Destructive actions are requested through scoped confirmations. Eligibility
is checked before presentation and again before mutation. Main-window and
settings-window confirmations and operation errors cannot block or dismiss
one another accidentally.

Conversation drafts are keyed by conversation identifier and retained only
while that conversation exists. Streaming auto-scroll follows the user only
while the view is pinned to the bottom and the preference is enabled; otherwise
Jump to Latest remains available.

## Streaming and Markdown

`QwenClient` buffers server-sent event bytes through complete lines before
decoding JSON. This keeps split UTF-8 scalars intact. `StreamingTokenEstimator`
maintains bounded grapheme-boundary state, so telemetry remains chunk invariant
without retaining or rescanning the full response.

Current streaming Markdown is rendered as one coherent document. Completed
documents use the bounded `MarkdownDocumentCache`. Repeated list content uses
stable positional identity, headings expose VoiceOver traits, and table rows
preserve empty cells while providing complete accessibility summaries.

## Localization and accessibility

`Resources/Localizable.xcstrings` owns typed count-unit plural variations.
Visible counts and approximate counts flow through `PresentationFormatting`
instead of hand-built singular and plural strings.

Interactive rows expose meaningful labels, values, help, and selected or
expanded state. File panels are asynchronous, keyboard commands have one
execution path, minimum control sizes are shared, and motion or transparency
adapts to macOS accessibility settings.

## Persistence and compatibility

Preference decoding preserves known values when new fields are absent, repairs
corrupt payloads without logging values, and migrates legacy keys. Runtime
profiles are persisted transactionally: a failed write does not partially
change in-memory state. Endpoint normalization trims whitespace and trailing
slashes while preserving path case and handling IPv6 loopback addresses.

No runtime payload, model weights, machine-specific model paths, credentials,
or user preferences are part of this UI architecture.

## Validation

Run the complete contribution gates from the repository root:

```bash
swift test
swift build
./package_app.sh
git diff --check
```

The focused theme gate can be run while changing a renderer:

```bash
swift test --filter ThemeColorUsageGateTests
```
