# Stable + Experimental workflow

Two apps live on the iPhone at all times — **Teycan Stable** (last release) and
**Teycan Translate** (dev). Each has its own bundle ID, its own data,
its own home-screen icon. You can always fall back to Stable if Dev breaks.

## Branch layout

| Branch | Purpose | Touched by |
|---|---|---|
| `main` | Frozen stable trunk. Always points at the latest release tag. | Only release merges. |
| `experimental` | All ongoing dev work. New features, bug-hunts, prototypes. | Day-to-day commits. |
| `v1.0`, `v1.1`, … | Tags marking each promotion of `experimental → main`. | Created at release time. |

The `ios-stable/` worktree is checked out at the current stable tag (right now
`v1.0`) and builds the Stable iPhone app. The `ios/` worktree tracks
`experimental` and builds the Dev iPhone app.

## Bundle IDs (free Personal Team, 2 of 3 slots used)

| Build | Bundle ID | Display name |
|---|---|---|
| Dev    | `solutions.techchain.teycan.translate` | "Teycan Translate" |
| Stable | `solutions.techchain.teycan.stable`    | "Teycan Stable" |

Bundle IDs are pinned in each worktree's `TeycanTranslate/project.yml` →
`PRODUCT_BUNDLE_IDENTIFIER`. Never change these — iOS treats them as separate
apps with separate UserDefaults, separate JWTs, etc.

## Daily workflow

```
# work happens here
cd /Users/serbinov/Desktop/projects/ai-translator/ios
git status                # should always say "On branch experimental"
# … edit … commit … push …

# deploy to phone (Dev app updates, Stable untouched)
cd TeycanTranslate
xcodebuild -project TeycanTranslate.xcodeproj -scheme TeycanTranslate \
  -configuration Debug \
  -destination 'platform=iOS,id=B0BFC1D3-0151-5AEC-A8CC-6CD92B7BEAFA' \
  -derivedDataPath ./build -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=JBZQPPB4YV build
xcrun devicectl device install app --device B0BFC1D3-0151-5AEC-A8CC-6CD92B7BEAFA \
  ./build/Build/Products/Debug-iphoneos/TeycanTranslate.app
xcrun devicectl device process launch --device B0BFC1D3-0151-5AEC-A8CC-6CD92B7BEAFA \
  --terminate-existing solutions.techchain.teycan.translate
```

Free Personal Team builds **expire after 7 days**. Just re-run the deploy to
refresh — same command, fresh signing.

## Promoting experimental → stable (release flow)

When `experimental` reaches a state you'd call stable:

```
cd /Users/serbinov/Desktop/projects/ai-translator/ios

# 1. Merge experimental into main, tag the release
git checkout main
git merge experimental --no-ff -m "Release vX.Y: <one-line summary>"
git tag -a vX.Y -m "<release notes>"
git push origin main vX.Y

# 2. Move the stable worktree to the new tag
cd ../ios-stable
git checkout vX.Y

# 3. The new tag has the dev bundle ID, so apply the stable-bundle override
#    (this is the one place each release needs a manual touch)
cd TeycanTranslate
# project.yml at this commit has PRODUCT_BUNDLE_IDENTIFIER: solutions.techchain.teycan.translate
# — change those two lines to solutions.techchain.teycan.stable, and
# CFBundleDisplayName to "Teycan Stable". Don't commit (the worktree is detached HEAD).
xcodegen generate

# 4. Build + install Stable
xcodebuild -project TeycanTranslate.xcodeproj -scheme TeycanTranslate \
  -configuration Debug \
  -destination 'platform=iOS,id=B0BFC1D3-0151-5AEC-A8CC-6CD92B7BEAFA' \
  -derivedDataPath ./build -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=JBZQPPB4YV build
xcrun devicectl device install app --device B0BFC1D3-0151-5AEC-A8CC-6CD92B7BEAFA \
  ./build/Build/Products/Debug-iphoneos/TeycanTranslate.app
xcrun devicectl device process launch --device B0BFC1D3-0151-5AEC-A8CC-6CD92B7BEAFA \
  --terminate-existing solutions.techchain.teycan.stable
```

After promotion: `experimental` keeps moving forward from where it was. No
rebase needed — `main` is a fast-forward parent of `experimental` after the
merge.

## When something on experimental is dangerously broken

Switch to **Teycan Stable** on the phone. The Dev app's state doesn't bleed
into Stable (different bundle IDs = different sandboxes), so even if dev
crashes on launch, Stable is unaffected.

## Don't do these things

- Don't commit to `main` directly. Use the merge-from-experimental flow above.
- Don't change Stable's bundle ID across releases. If you do, the new build
  installs as a *third* app instead of updating the existing Stable icon, and
  you'll hit the free-tier 3-app-ID limit fast.
- Don't try to share UserDefaults / Keychain between Dev and Stable — they're
  different bundle IDs, iOS treats them as fully separate apps. That's the
  whole point.
