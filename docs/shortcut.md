# macOS Shortcut: Send a Screenshot to `/ingest`

A Shortcuts.app shortcut that takes a screenshot and uploads it to the
bank-app-parser `POST /ingest` endpoint — one image, one request, no Share
Sheet.

## Endpoint recap

| Property | Value |
|----------|-------|
| Method | `POST` |
| URL | `http://localhost:3000/ingest` (use your host/port) |
| Auth header | `Authorization: Bearer <INGEST_TOKEN>` |
| Body | `multipart/form-data`, single file field named `image` |
| Success | `202 Accepted`, JSON `{ "batch_id": …, "status": … }` |

Screenshots sent within the 15-minute debounce window land in the same pending
batch, so you can run the shortcut several times in a row.

---

## Step-by-step

### 1. Create the shortcut

1. Open **Shortcuts.app**.
2. Click **+** (top toolbar) to create a new shortcut.
3. Name it (double-click the title), e.g. **Send Screenshot to Bank Parser**.

### 2. Take the screenshot

1. Add a **Take Screenshot** action.
   - This is the macOS screen-capture action; its output is the captured image.

> Want to pick a screen region instead of the full screen? Some macOS versions
> expose an **Interactive** toggle on this action. If yours doesn't, leave it as
> full-screen.

### 3. Store the token

1. Add a **Text** action.
2. Paste your `INGEST_TOKEN` value into it.
3. Rename its output variable to `Token` (right-click the magic variable →
   rename), or just reference its magic variable later.

> Prefer not to embed the token in plain text? Use an **Ask Each Time** Text
> action, or read it from a Keychain/Data Jar item.

### 4. Upload the screenshot

1. Add a **Get Contents of URL** action.
2. **URL**: `http://localhost:3000/ingest`
   (replace with your machine's address if uploading from another device;
   `localhost` only works on the same Mac).
3. Expand **Show More**.
4. **Method**: `POST`.
5. **Headers** → add one:
   - Key: `Authorization`
   - Value: `Bearer ` followed by the `Token` magic variable (type `Bearer `
     then insert the variable, so the result is `Bearer <token>`).
6. **Request Body**: `Form`.
7. Add a body field:
   - Tap **Add new field** → **File**.
   - Key: `image`
   - Value: the **Screenshot** magic variable from step 2.

### 5. (Optional) Confirm the upload

After the request:

1. Add **Get Dictionary from Input** (parses the JSON response).
2. Add **Get Dictionary Value**, key `batch_id`.
3. Add **Show Notification** with text like `Uploaded — batch #` + the
   `batch_id` value.

### 6. Save

Close the editor.

---

## Running it

Trigger the shortcut however you like:

- From the **Shortcuts** menu bar item or the Shortcuts app.
- Pin it to the **Dock** or **Menu Bar** (Shortcut Details → *Pin in Menu Bar*).
- Assign a **keyboard shortcut**: Shortcut Details (ⓘ) → **Add Keyboard
  Shortcut**.

Each run captures the screen and uploads it as one image.

---

## Troubleshooting

| Symptom | Cause / Fix |
|---------|-------------|
| `401 unauthorized` | Token mismatch. Confirm the `Authorization` value is `Bearer <token>` and matches the server's `INGEST_TOKEN`. |
| `422 no image` | Body field key isn't `image`, or it's not a **File** field. Re-check step 4.7. |
| `422 batch image limit reached` | Current batch already has 15 images. Wait for it to process, then retry. |
| Request hangs / fails | Server not running, or `localhost` used from another device. Use the Mac's LAN IP and ensure `./serve-dev` is up. |
