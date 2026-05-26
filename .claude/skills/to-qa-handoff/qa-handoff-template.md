# QA handoff — {Feature name}

## Prerequisites
- Test environment URL: {url}
- Test user credentials: {creds or pointer}
- Feature flags to enable: {flags, or "none"}
- Other setup: {fixtures, seed data, etc.}

## Pages

### `/route — Page label`

**On this page you should see:**
- R{n}: {behavior}
- R{n}: {behavior}

**On this page you can:**
- {interaction}
- {interaction}

**Expected outcomes:**
- {interaction → result}

### `/other-route — Other Page`
...

## End-to-end scenarios

### Scenario: {short title}
1. Navigate to `/route` — see X.
2. Click Y — should land on `/next-route`.
3. ...

## Out of scope / known limitations
- {wontfix slice} — {reason from manifest}
- {validation gap surfaced during testing}
