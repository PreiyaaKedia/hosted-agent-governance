---
name: travel-guide
description: Creates colorful PDF travel guides for cities, including itinerary ideas, neighborhoods, food, practical tips, and photo-worthy stops. Use when the user asks for a travel guide, city guide, itinerary, trip plan, or PDF document for a destination.
---

# Travel guide skill

Use this skill when the user wants a city travel guide, itinerary, or downloadable PDF trip-planning document.

## Workflow

1. Identify the city or destination from the user's request.
2. Infer the trip length and interests when provided. If the user does not specify them, use a 3-day guide and a balanced mix of culture, food, neighborhoods, views, and practical tips.
3. Run the PDF generator script `create_travel_guide.py` in the `travel-guide` skill.
   Arguments MUST be passed as a JSON **array of strings** — positional CLI flags,
   not an object. Supported flags:
     - `--city <name>` — destination city (required)
     - `--days <n>` — number of itinerary days, defaults to `3`
     - `--interests <csv>` — comma-separated interests such as `food,art,history,views`
     - `--tone <style>` — guide style such as `family-friendly`, `luxury`, `budget`, or `first-time visitor`
4. After the script returns, share the `share_url` (a time-limited Azure Blob SAS link) with the user and briefly summarize the guide. Mention that the link expires after `share_url_expires_hours` hours.

## Available scripts

- `create_travel_guide.py` - Generates a colorful PDF travel guide, uploads it to Azure Blob Storage, and returns JSON containing a shareable `share_url` (SAS-signed) plus the local `$HOME`-based path.

## Required environment

The script uploads to Azure Blob Storage using the agent's managed identity (`DefaultAzureCredential`). Configure the hosted agent with:

- `TRAVEL_GUIDE_BLOB_ACCOUNT_URL` — full blob endpoint, e.g. `https://mystorage.blob.core.windows.net` (or set `TRAVEL_GUIDE_BLOB_ACCOUNT` to just the account name).
- `TRAVEL_GUIDE_BLOB_CONTAINER` — container name, defaults to `travel-guides`.
- `TRAVEL_GUIDE_SAS_HOURS` — SAS link lifetime in hours, defaults to `24`.

Grant the agent identity the **Storage Blob Data Contributor** role on the account (required so the user-delegation SAS can be issued and the blob written).

## Example script arguments

Pass arguments as a JSON array of strings (positional CLI flags). Do NOT pass an object/dict.

Correct:

```json
["--city", "Lisbon", "--days", "3", "--interests", "food,viewpoints,neighborhoods", "--tone", "first-time visitor"]
```

Incorrect (will fail with `TypeError: Expected a list of CLI arguments but received dict`):

```json
{ "city": "Lisbon", "days": 3 }
```