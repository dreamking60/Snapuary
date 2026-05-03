# Xcode 15.4 Compatibility Notes

## Goal

Keep local development on `Xcode 15.4` while preserving the repo's `XcodeGen` workflow.

## Environment

- macOS host
- Xcode `15.4`
- Swift `5.10`
- XcodeGen `2.45.4`
- iOS Simulator target used for verification: `iPhone 15 / iOS 17.5`

## Problems Encountered

### 1. Generated project could not be opened by Xcode 15.4

Error:

```text
xcodebuild: error: Unable to read project 'Snapuary.xcodeproj'.
Reason: The project ‘Snapuary’ cannot be opened because it is in a future Xcode project file format (77).
```

Cause:

- `xcodegen 2.45.4` generated `objectVersion = 77`
- `Xcode 15.4` cannot read that project format

Fix:

- Added `options.xcodeVersion: "15.4"` to `project.yml`
- Normalized the generated `project.pbxproj` inside `scripts/bootstrap_ios.sh`
- Forced:
  - `objectVersion = 60`
  - `preferredProjectObjectVersion = 60`

Why the fix lives in `bootstrap_ios.sh`:

- The repo treats `.xcodeproj` as generated output
- The compatibility rewrite must happen every time `xcodegen generate` runs

### 2. Test target and app target produced conflicting Swift module outputs

Error:

```text
Multiple commands produce .../Snapuary.swiftmodule/...
```

Cause:

- The app target and test target were both resolving to the same effective module/product output names during test builds

Fix:

- Moved `PRODUCT_NAME` to the app target explicitly
- Set the unit test target `PRODUCT_NAME` to `SnapuaryTests`

### 3. `withCheckedThrowingContinuation` failed type inference

Error:

```text
generic parameter 'T' could not be inferred
```

Cause:

- The continuation inside `deleteAssets(withLocalIdentifiers:)` did not make the `Void` return type explicit enough for the compiler in this toolchain path

Fix:

- Changed the continuation closure to:

```swift
(continuation: CheckedContinuation<Void, Error>)
```

### 4. `PHAsset` had no `addedDate` member

Error:

```text
value of type 'PHAsset' has no member 'addedDate'
```

Cause:

- `PHAsset` does not expose `addedDate` as a direct property in this usage path

Fix:

- Replaced `asset.addedDate` with `asset.creationDate` in the descriptor mapping path

Tradeoff:

- This keeps the project compiling on `Xcode 15.4`
- If true library-added timestamps are needed later, they should be sourced through a PhotoKit collection/member fetch path rather than `PHAsset` directly

### 5. SwiftUI style shorthand was not accepted by Xcode 15.4

Error:

```text
type 'ShapeStyle' has no member 'accent'
```

Cause:

- `.foregroundStyle(.accent)` was too new for the compiler/API combination in use

Fix:

- Replaced shorthand style values with explicit color values:
  - `Color.accentColor`
  - `Color(uiColor: .tertiaryLabel)`

### 6. `Swift Testing` module was unavailable

Error:

```text
no such module 'Testing'
```

Cause:

- `Xcode 15.4` does not ship the `Swift Testing` framework used by the original tests

Fix:

- Converted `Tests/SnapuaryTests/SnapuaryTests.swift` from `Swift Testing` to `XCTest`
- Replaced:
  - `@Test` -> XCTest test methods
  - `#expect(...)` -> `XCTAssert...`
  - `#require(...)` -> `XCTUnwrap(...)`

### 7. Actor isolation in a test double conflicted with a synchronous protocol requirement

Error:

```text
actor-isolated instance method 'authorizationStatus()' cannot be used to satisfy nonisolated protocol requirement
```

Cause:

- `PhotoLibraryServing.authorizationStatus()` is synchronous
- The test double used an `actor`, which isolated that method

Fix:

- Changed `InMemoryPhotoLibraryService` from `actor` to `final class`

## Verification Commands

The following commands succeeded after the fixes:

```bash
./scripts/bootstrap_ios.sh
xcodebuild -list -project Snapuary.xcodeproj
xcodebuild build -project Snapuary.xcodeproj -scheme Snapuary -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5'
xcodebuild test -project Snapuary.xcodeproj -scheme Snapuary -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5'
```

## Practical Development Rules

1. If `xcodegen` is upgraded, re-check the generated `objectVersion`.
2. Keep `.xcodeproj` treated as generated output, not source-of-truth.
3. If a new API compiles only on newer Xcode, prefer the most explicit SwiftUI/UIKit spelling that still works on `15.4`.
4. If tests start using `Swift Testing` again, they will stop working on `Xcode 15.4`.
5. Toolchain compatibility and iPhone OS compatibility are different concerns:
   - `Xcode 15.4` controls developer tooling compatibility
   - `deploymentTarget` controls how old an iPhone/iOS version can install the app
