# The eDraft Location — a design

*Written 2026-09-18 on branch `rename/edraft`, HEAD `fbd7eb9`, under lock
IL-0046. The human asked for eDraft to have "a folder also connected and
sync", listed in Files the way Adobe Scan is, and on Apple's iCloud. This RFC
designs that Location — in Files on iPhone and iPad, in the Finder sidebar on
the Mac — and the locks that build it.*

*Every claim carries its evidence:*

- ***measured*** — read or run in this repository on 2026-09-18.
- ***sourced*** — Apple's documentation or sample code, linked in §14.
- ***inference*** — reasoned from measured or sourced facts, not itself run.
- ***judgement*** — a design call, with its alternative named.
- ***unproven*** — needed and not yet known, with the probe that settles it (§11).

*No example uses real script text or real names. The repository is public.*

---

## 0. Decisions

### Settled — the human's

| # | Decision |
|---|---|
| D1 | eDraft has **its own Location**, listed like Adobe Scan: in Files on iPhone and iPad, in the Finder sidebar on the Mac. |
| D2 | It syncs through **Apple's iCloud**. Nothing hidden and nothing undocumented: public, documented Apple APIs only, and a script is an ordinary file the writer can see, move and share. |
| D3 | **The Location is the one home for scripts.** The eDraft folder inside iCloud Drive, begun in the other session (`NSUbiquitousContainers`, saving into the ubiquity container), does not ship. Its entitlement and icon work stay. |
| D4 | Design first; the build follows the other session's commit. |

### Proposed by this RFC — settled when the human approves it

| # | Proposal | Where |
|---|---|---|
| P1 | A **replicated File Provider extension** in each app, one domain named "eDraft". | §2 |
| P2 | Sync through **CKSyncEngine** against the writer's own iCloud — CloudKit's *private database*, one custom zone. Never the public database. | §2, §7 |
| P3 | **The extension owns sync.** The app never runs a second sync engine; it asks the extension to sync. | §4 |
| P4 | **One record per file or folder**, the file's bytes as a CloudKit asset, a parent pointer that never cascades. | §3 |
| P5 | **Never silent loss.** A conflict keeps both versions; an edit beats a delete; a lost account keeps its unsynced files on the device. | §5, §6 |

### Open — the human's to decide

Listed in §12, each with a recommendation. None blocks the first lock.

---

## 1. Where things stand — measured

- **The project** has three targets — the iOS app, its tests, the Mac app —
  and no extension. Both apps deploy to version 26 (`IPHONEOS_DEPLOYMENT_TARGET`,
  `MACOSX_DEPLOYMENT_TARGET`).
- **iPhone:** the app's `Info.plist` sets `UIFileSharingEnabled` and
  `LSSupportsOpeningDocumentsInPlace`, so Files already shows *On My iPhone ›
  eDraft*; it sets `UISupportsDocumentBrowser`. The iOS target has no
  entitlements file: no iCloud today.
- **Mac:** the entitlements (`apple/macOS/eDraft.entitlements`, uncommitted,
  the other session's) carry iCloud Documents for `iCloud.xyz.edraft` — the
  key corrected in IL-0045 — and the App Sandbox. The uncommitted
  `EDraftMacApp.swift` and `ScreenplayDocument.swift` resolve the ubiquity
  container and save there; `Info.plist` declares it as the "eDraft" folder in
  iCloud Drive. D3 retires that path (§8.3).
- **Documents** are single files: a `.draft` is one ZIP (RFC-DRAFT-FORMAT §4),
  an `.fdx` one XML file, a PDF one file. A script syncs as one item.

---

## 2. The shape

```
 iPhone / iPad                                Mac
 ┌──────────────────────────┐                 ┌──────────────────────────┐
 │ eDraft app               │                 │ eDraft app               │
 │  opens & saves files in  │                 │  opens & saves files in  │
 │  the Location            │                 │  the Location            │
 └────────────┬─────────────┘                 └────────────┬─────────────┘
              │ signalEnumerator                           │
 ┌────────────▼─────────────┐                 ┌────────────▼─────────────┐
 │ File Provider extension  │                 │ File Provider extension  │
 │  NSFileProviderReplicated│                 │  NSFileProviderReplicated│
 │  Extension + CKSyncEngine│                 │  Extension + CKSyncEngine│
 └────────────┬─────────────┘                 └────────────┬─────────────┘
              │         the writer's own iCloud            │
              └──────────►  CloudKit, iCloud.xyz.edraft  ◄─┘
                           private database, zone "eDraft"
```

| Piece | What | Evidence |
|---|---|---|
| **Domain** | One `NSFileProviderDomain`, identifier `edraft`, display name "eDraft", added by each app with `NSFileProviderManager.add(_:)` at first launch. It is what Files lists under Locations and the Finder lists in its sidebar. | *sourced:* "The system will expose that domain in the Finder sidebar and create a root directory for the domain in the file system" (WWDC21); Apple's sample adds a domain and finds it "in the list of locations" in Files. |
| **Extension** | One File Provider extension per app, implementing `NSFileProviderReplicatedExtension`: the system keeps the files on disk and calls the extension to create, modify, delete, fetch and enumerate. | *sourced:* available from iOS 16 and macOS 11; both apps deploy to 26. |
| **Sync** | `CKSyncEngine` in the extension (§4), against the **private database** of the container `iCloud.xyz.edraft`, one custom record zone `eDraft`. | *sourced:* iOS 17 and macOS 14; "Don't use CKSyncEngine to sync your app's public database." |
| **Shared state** | An App Group, `group.xyz.edraft`, shared by each app and its extension: the item index (§3.3), the engine's saved state, the sync log. | *sourced:* Apple's sample shares one App Group identifier across its macOS and iOS apps and extensions. |
| **Entitlements** | App and extension: CloudKit for `iCloud.xyz.edraft`; the App Group; push (`aps-environment`), which CKSyncEngine requires. iCloud Documents and the ubiquity key go (§8.3). | *sourced:* "CKSyncEngine requires the CloudKit and Remote notifications entitlements." |

**What "private" means here.** CloudKit names each person's own storage for
an app its *private database*: only that iCloud account can read it. It is a
public, documented API. The *public database* is readable by every user of
the app; a script must never be written there, and Apple says not to sync it
with CKSyncEngine. This design touches the private database only (D2, §7).

---

## 3. The data model

### 3.1 One record per item

Record type `Item`, in zone `eDraft`. The record name is the item's
identifier: a random UUID string, fixed for the item's life, and the
`NSFileProviderItemIdentifier` the system sees.

| Field | Type | For |
|---|---|---|
| `name` | String, encrypted | The file or folder name, as the writer sees it. |
| `parent` | String | The parent folder's record name, or `root`. |
| `kind` | String | `file` or `folder`. |
| `content` | CKAsset | Files only: the bytes. |
| `contentHash` | String | SHA-256 of the bytes, lowercase hex. |
| `size` | Int64 | Bytes. |
| `created`, `modified` | Date | As Files and the Finder show them. |
| `trashed` | Int64 (0/1) | In the Location's trash (§12 O2). |
| `origin` | String | The device class that last wrote it (`iPhone`, `iPad`, `Mac`) — never a device's or person's name (RFC-NOTES-SYSTEM D6). |

- *Sourced:* a record's data is limited to 1 MB and assets do not count.
  *Measured:* a `.draft` is tens of kilobytes and an FDX up to about 800 KB
  (RFC-DRAFT-FORMAT §1.2); a PDF is a few megabytes.
- `name` uses `encryptedValues`, so a file's name is end-to-end encrypted
  when the writer has Advanced Data Protection on. Whether a CKAsset's bytes
  are end-to-end encrypted under Advanced Data Protection is **unproven** —
  U5, settled from Apple's security documentation before L2.

### 3.2 No cascading deletes

`parent` is a plain string, not a `CKRecord.Reference` with a delete action.
A deleted folder never deletes a child the server holds; children are
deleted one by one, and each deletion can lose to an edit (§5). *Judgement:*
a cascading reference is shorter code and the one way a deleted folder could
silently take a newer script with it.

### 3.3 The item index

The App Group holds an index — one row per item: identifier, parent, name,
kind, content hash, the record's server change tag, and the local state
(`synced`, `pending upload`, `pending delete`, `conflict`). It answers the
system's `item(for:)` and enumerations without the network, and it is what
the engine's batches are built from.

### 3.4 Versions

Each item's `NSFileProviderItemVersion` is:

- `contentVersion`: the content hash;
- `metadataVersion`: a hash of `name`, `parent` and `trashed`.

The system passes a `baseVersion` to `modifyItem` and `deleteItem`; a base
that no longer matches the index is a conflict (§5), never an overwrite.

### 3.5 What Files does, and what it becomes

| In Files or the Finder | The extension is called | CloudKit |
|---|---|---|
| New file, paste, drop, save | `createItem(basedOn:fields:contents:…)` | save a new record with its asset |
| Edit and save | `modifyItem(…changedFields: .contents…)` | save the record with the new asset and hash |
| Rename, move | `modifyItem(…changedFields: .filename / .parentItemIdentifier…)` | save `name` / `parent` |
| New folder | `createItem` with a folder template | save a folder record |
| Move to trash | `modifyItem` to the trash container | `trashed = 1` (§12 O2) |
| Delete forever | `deleteItem(identifier:baseVersion:…)` | delete the record |
| Open a file not yet on this device | `fetchContents(for:version:…)` | download the asset |

---

## 4. Sync

### 4.1 The extension owns it

A writer can drop a file into the Location from Files while eDraft is not
running; only the extension is there to upload it. So **the sync engine lives
in the extension**, and the app never runs a second one against the same
saved state (P3). The app asks for a sync with
`NSFileProviderManager.signalEnumerator(for: .workingSet)`, which wakes the
extension (*sourced*).

### 4.2 Sending

A local change is written to the index as `pending`, and the matching
`CKSyncEngine.PendingRecordZoneChange` (save or delete) is added to the
engine's state. The engine sends batches when conditions allow;
`nextRecordZoneChangeBatch` builds them from the index. A successful send
marks the item `synced` and stores the server's change tag. The completion
handler the system passed with the change is called only when the change is
safely in the index — so the system never believes a change is saved that
could still be lost.

### 4.3 Receiving

Fetched changes (`fetchedRecordZoneChanges`) update the index, and the
extension calls `signalEnumerator(for: .workingSet)`. The system then calls
`enumerateChanges(for:from:)` on the working-set enumerator, which reports
what changed since its sync anchor — the engine's saved state serialised
with the index generation. An anchor too old to answer returns
`syncAnchorExpired`, and the system re-enumerates from the start
(*sourced*).

### 4.4 Files not yet on this device

A replicated domain lists every item but keeps bytes only for files that
have been opened ("materialised"). Opening one calls `fetchContents`, which
downloads the asset. `materializedItemsDidChange` tells the extension which
files are kept, so it downloads new versions only of those (*sourced*).
*Judgement:* scripts are small, and the Mac may keep all of them; the phone
keeps what the writer opens.

### 4.5 What wakes the engine — unproven

CloudKit's change notifications are delivered to the **app** (*inference*:
the app registers for them). CKSyncEngine "periodically pushes and pulls
database and record zone changes on the app's behalf", and "the engine's sync
schedule is indeterminate" (*sourced*). Whether an engine hosted in the
**extension** is woken promptly when another device changes a file, with
eDraft not running, is **unproven** (U1). The design's answer, in order of
preference, is settled by probe P1:

1. The app, when it runs or is woken by CloudKit's notification, calls
   `signalEnumerator`; the extension fetches before it answers.
2. Opening the Location in Files enumerates the working set; the extension
   fetches first. The writer sees the latest the moment they look.
3. If neither is prompt enough, CloudKit's notification is routed to the
   extension through PushKit's `fileProvider` push type (*sourced* that the
   type exists; *unproven* that CloudKit can target it).

---

## 5. Conflicts — never silent loss

| Case | Rule |
|---|---|
| **Two devices edit one file** | The version that reached iCloud first keeps the name. The other is saved beside it as **"The Kettle (conflicted copy, iPhone, 2026-09-18 23.04).draft"** (§12 O3). Both sync everywhere. |
| **A rename meets a rename** | The first to reach iCloud wins the name; the other's contents are unaffected. |
| **An edit meets a delete** | The edit wins: the file stays, with the edit. If its folder was deleted, the file comes back at the top of the Location. |
| **A folder is deleted while a file in it changes elsewhere** | Children are deleted one by one (§3.2); the changed file survives by the rule above. |
| **Two devices create the same name in one folder** | Both files exist; the second is shown as "The Kettle 2.draft", the way the Finder names a collision. |

Mechanism: CloudKit rejects a save whose change tag is stale with
`serverRecordChanged` and returns the server's record; the engine compares
content hashes and applies the table. A conflict is written to the sync log
(§6) — the writer is shown what happened, not left to find a second file.

---

## 6. States — what the writer sees

| State | Detected by | The Location | eDraft shows |
|---|---|---|---|
| **Not signed in to iCloud** | `CKSyncEngine` account change (sign-out), CloudKit `notAuthenticated` | Mac: disconnected with a reason (`NSFileProviderManager.disconnect(reason:…)`, macOS only). iPhone and iPad: the extension answers with `NSFileProviderError.notAuthenticated`, and "the system presents an alert to the user" (*sourced*). Files already on the device stay readable. | "Sign in to iCloud to sync eDraft." |
| **Signed in to a different account** | account change (switch accounts) | the previous account's files leave the Location | Any file with unsent changes is moved first to *On My iPhone / Documents › eDraft › From your previous iCloud account* — never discarded (§12 O5). |
| **iCloud full** | CloudKit `quotaExceeded`, reported as `insufficientQuota` | the file stays on the device, marked not uploaded | "iCloud is full. This script is saved on this device and will sync when there is room." |
| **Offline** | CloudKit network errors, `serverUnreachable` | changes queue; Files shows them waiting | nothing, until a change has waited a day; then a quiet note |
| **iCloud switched off for eDraft** (in the device's iCloud settings) | **unproven** (U2) | as not signed in, if it reports so | as not signed in |
| **The Location turned off in Files** (iOS) | `NSFileProviderDomain.userEnabled` is false | not listed | the one-time hint (§8.1) |
| **The zone was deleted** (the writer erased eDraft's iCloud data in Settings) | CloudKit `userDeletedZone` | local files re-uploaded to a new zone only after the writer confirms | "Your eDraft iCloud data was erased. Upload the scripts on this device again?" |

Every failure leaves the words on the device and says where they are (the
fourth keep of IL-0046). The sync log in the App Group records each state
change, conflict and error, and eDraft shows it on request.

---

## 7. Privacy

- **The private database only.** Every record lives in the writer's own
  iCloud; the public and shared databases are never used by this design.
- **No eDraft server and no account.** CloudKit uses the iCloud account
  already signed in on the device. eDraft adds no sign-in, stores no
  credentials and asks for none (RFC-NOTES-SYSTEM D6).
- **No names from the system.** The conflict copy names the device class
  (`iPhone`), never the device's or the person's name.
- **Names encrypted.** `name` is an encrypted field (§3.1); asset encryption
  under Advanced Data Protection is U5.
- **The web app does not reach the Location.** Reaching CloudKit from a
  browser needs an Apple sign-in, which eDraft does not have. The web app
  keeps exporting and importing files.

---

## 8. The apps

### 8.1 iPhone and iPad

- **First launch** adds the domain. Apple ships a new domain turned off: the
  writer turns it on once in Files ("find the domain in the list of locations,
  and then tap to enable it" — *sourced*). Until they do, eDraft's library
  shows a one-time card: *"Turn on eDraft in Files to keep your scripts in
  iCloud"*, with the steps. It never shows again once `userEnabled` is true.
- **New scripts** are created in the Location's root, found with
  `getUserVisibleURL(for: .rootContainer)`. The system document browser lists
  the Location among its locations. Whether the browser can be opened *at*
  the Location is **unproven** (U4).
- **On My iPhone › eDraft stays** for writers who keep a file off iCloud.

### 8.2 Mac

- The domain appears in the Finder sidebar with the eDraft icon (*sourced*).
- The save panel opens at the Location's root; Open Recent and the launch
  window work unchanged — a file in the Location is an ordinary URL to the app.

### 8.3 What replaces the iCloud Drive folder (D3)

| The other session's piece | Becomes |
|---|---|
| `NSUbiquitousContainers` in the Mac's `Info.plist` | removed |
| Saves into the ubiquity container (`EDraftMacApp.swift`, `ScreenplayDocument.swift`) | saves into the Location (§8.2) |
| iCloud Documents entitlements, `ubiquity-container-identifiers` (fixed in IL-0045) | replaced by CloudKit for the same container `iCloud.xyz.edraft` |
| The App Sandbox, user-selected files, print | kept |

The app is unreleased, so nothing is in any writer's iCloud Drive folder to
move. `IOS-PLAN.md` §7 ("`DocumentGroup` + iCloud Drive") is superseded by
this RFC for storage; it is not edited here.

---

## 9. Scale

*Inference:* a writer keeps tens to hundreds of scripts, each under a
megabyte, plus PDFs of a few megabytes. CloudKit's private database counts
against the writer's own iCloud storage. The largest file this design must
carry well is a PDF with images, tens of megabytes — probe P3 measures an
extension's memory and time limits with one.

---

## 10. Testing

- **Unit tests of the sync logic**, against a fake CloudKit behind the same
  interface the engine's delegate sees: every row of §5's table and §6's
  table, send and fetch batching, anchors expiring, a crash between the index
  write and the completion handler. No test needs a network.
- **`NSFileProviderDomain.testingModes`** (iOS 16, macOS 11.3), to drive the
  system's calls deterministically in tests (*sourced*: "A mode that gives the
  File Provider extension more control over the system's behavior during
  testing").
- **The two-device matrix**, run by the human with a Mac and an iPhone on one
  iCloud account, eDraft closed and open:

| # | Do | Expect |
|---|---|---|
| T1 | Save a script on the Mac | it appears in Files on the iPhone |
| T2 | Edit it on both, offline, then reconnect | the original name and one conflicted copy, on both |
| T3 | Delete on the iPhone while the Mac edits offline | the edit survives |
| T4 | Drop a PDF into the Location from Files with eDraft closed | it reaches the Mac |
| T5 | Sign out of iCloud on the iPhone with an unsent change | the change is in *From your previous iCloud account* |
| T6 | Fill iCloud (a test account) and save | the "iCloud is full" message; the file on the device |

---

## 11. Unknowns — each with its probe

| # | Unknown | Probe |
|---|---|---|
| U1 | What wakes the extension's engine promptly when another device changes a file and eDraft is closed (§4.5) | **P1**, the first lock: a minimal extension on both devices syncing one file; change it on the Mac and time its arrival on the iPhone with eDraft closed, open, and after opening Files. |
| U2 | How switching iCloud off for eDraft alone is reported | **P2**, in L1: turn it off in Settings and read the account status the engine reports. |
| U3 | An extension's memory and time limits with a large file on iOS | **P3**, in L4: upload and download a 50 MB PDF through the Location. |
| U4 | Whether the iOS document browser can open at the Location | **P4**, in L3. If it cannot, eDraft's own library lists the Location first. |
| U5 | Whether CKAsset bytes are end-to-end encrypted under Advanced Data Protection | Apple's platform security documentation, read before L2; the answer is written into §7. |
| U6 | The App Group identifier and signing on the Mac for app and extension | **P1**, by building and signing both extensions. |

---

## 12. Open decisions — the human's

| # | Decision | Recommendation |
|---|---|---|
| O1 | Folders in the Location | **Yes.** Files and the Finder let writers make folders; a Location without them surprises. |
| O2 | A trash that syncs (`supportsSyncingTrash`, iOS 18, macOS 13) | **Yes.** A script deleted on the phone waits in Recently Deleted on the Mac too, and can come back. |
| O3 | The conflicted copy's name | **"Name (conflicted copy, iPhone, 2026-09-18 23.04).ext"** — the device class and the time, no personal name. |
| O4 | What the Location holds | **Any file.** It is a folder; eDraft opens what it can (`.draft`, `.fdx`, `.fountain`, PDF). |
| O5 | Unsynced files from a previous iCloud account | **Keep them on the device** in *From your previous iCloud account*, never upload them to the new account unasked. |
| O6 | The web app | **No Location access**; it keeps import and export (§7). |

---

## 13. The build — one lock each

### L1 — the probe

- **Builds:** a File Provider extension target for each app; the App Group;
  CloudKit and push entitlements; the domain added at launch; CKSyncEngine
  syncing one file both ways. Nothing else.
- **Proofs:** the Location appears in Files and the Finder; one file makes the
  round trip; **P1, P2 and U6 settled and written into §4.5 and §6 of this
  RFC.** Human check on two devices.

### L2 — the sync core

- **Builds:** §3's model and index, §4's send and receive, §5's conflicts,
  §6's states and the sync log.
- **Proofs:** §10's unit tests, each row of §5 and §6; a crash-safety test
  between the index write and the completion handler.

### L3 — the apps

- **Builds:** §8 — new scripts in the Location, the iOS enable card, the Mac
  save panel, the iCloud Drive folder retired (§8.3), P4.
- **Proofs:** T1 and T4 by the human; a new script lands in the Location on
  both platforms; `NSUbiquitousContainers` and the ubiquity key are gone.

### L4 — hardening

- **Builds:** P3's findings; quota, offline and account-switch paths polished;
  the sync log shown in the app.
- **Proofs:** the whole §10 matrix, T1–T6, run by the human on two devices
  before the Location is called done.

---

## 14. Sources

- Apple, *Synchronizing files using file provider extensions* (sample; App
  Group across targets; "A new domain is in a disabled state by default"):
  <https://developer.apple.com/documentation/fileprovider/synchronizing-files-using-file-provider-extensions>
- Apple, `NSFileProviderReplicatedExtension` (iOS 16, macOS 11):
  <https://developer.apple.com/documentation/fileprovider/nsfileproviderreplicatedextension>
- Apple, `NSFileProviderDomain` (`userEnabled`, `supportsSyncingTrash`,
  `testingModes`, `isDisconnected`):
  <https://developer.apple.com/documentation/fileprovider/nsfileproviderdomain>
- Apple, `NSFileProviderManager` (`add`, `signalEnumerator`,
  `getUserVisibleURL`; `disconnect` and `reconnect` are macOS only):
  <https://developer.apple.com/documentation/fileprovider/nsfileprovidermanager>
- Apple, `NSFileProviderError` (`notAuthenticated`, `serverUnreachable`,
  `insufficientQuota`, `syncAnchorExpired`, `cannotSynchronize`):
  <https://developer.apple.com/documentation/fileprovider/nsfileprovidererror>
- Apple, WWDC21 *Sync files to the cloud with FileProvider on macOS* (the
  Finder sidebar and the domain's root directory):
  <https://developer.apple.com/videos/play/wwdc2021/10182/>
- Apple, `CKSyncEngine` (iOS 17, macOS 14; entitlements; "Don't use
  CKSyncEngine to sync your app's public database"):
  <https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5>
- Apple, WWDC23 *Sync to iCloud with CKSyncEngine*:
  <https://developer.apple.com/videos/play/wwdc2023/10188/>
- Apple, sample `sample-cloudkit-sync-engine`:
  <https://github.com/apple/sample-cloudkit-sync-engine>
- Apple, CloudKit Web Services data size limits (1 MB record data; assets
  separate):
  <https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitWebServicesReference/PropertyMetrics.html>
- Apple, PushKit `PKPushType.fileProvider`:
  <https://developer.apple.com/documentation/pushkit/pkpushtype/fileprovider>
- In this repository: [RFC-DRAFT-FORMAT.md](RFC-DRAFT-FORMAT.md),
  [RFC-NOTES-SYSTEM.md](RFC-NOTES-SYSTEM.md), [IOS-PLAN.md](IOS-PLAN.md).
