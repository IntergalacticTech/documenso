# Claude skills for signature.victorycto.com

## send-for-signature

Lets anyone in VictoryCTO ask Claude to "send this Google Doc to Jane at Acme
for signature". Claude:
- exports the doc as a PDF
- finds the signature, initial, date and fill-in spots
- assigns them to signers in order
- previews the placement
- creates a draft in Documenso

It only sends once the person confirms.

### Install

**Claude.ai (whole org):**
1. Zip the folder:

   ```bash
   cd skills && zip -r send-for-signature.zip send-for-signature
   ```

2. An org owner uploads it as an organisation skill in Claude.ai's admin settings.
3. In the code execution settings, add `signature.victorycto.com` to the allowed
   network domains. The scripts call its API from Claude's sandbox.
4. To pull docs straight from Google Docs, members connect the **Google Drive**
   connector. Without it, they attach a PDF instead.

**Claude Code (per person):** copy the folder into your personal skills folder:

```bash
cp -r skills/send-for-signature ~/.claude/skills/
```

Then put `export DOCUMENSO_API_TOKEN=...` in your shell profile.

### Each person needs

A Documenso API token. Sign in at https://signature.victorycto.com and go to
**Settings → API Tokens** (in the VictoryCTO team). The token acts as that
person, so drafts appear under their name.

### Scripts

| Script | Purpose |
|---|---|
| `scripts/detect_fields.py` | Candidate fields from text labels, underscores and drawn signature lines; renders pages |
| `scripts/preview_fields.py` | Draws a plan's boxes on the pages for visual checking |
| `scripts/create_envelope.py` | Validates a plan, creates the draft envelope, or sends one with `--send` |
