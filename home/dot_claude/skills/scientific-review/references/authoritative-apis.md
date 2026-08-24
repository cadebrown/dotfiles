# Authoritative API routes

Use these primary services instead of scraping web interfaces. Record the full
request and response metadata in the project evidence record.

| Service | Read route | Constraint |
| --- | --- | --- |
| Crossref | `https://api.crossref.org/v1/works/{doi}` | Include `mailto` in a polite client; metadata is not full text. |
| OpenAlex | `https://api.openalex.org/works` | A key is free for scaled use; record cost/rate-limit metadata. |
| DataCite | `https://api.datacite.org/dois/{doi}` | REST v2; use a repository credential only for an authorized deposit. |
| OpenReview | `https://api2.openreview.net` | API v2 is current; note visibility and invitation permissions. |
| Zotero local | `http://localhost:23119/api/` | Local only; read requests are local and write requests need user-granted authorization. |

Official documentation: [Crossref REST](https://www.crossref.org/documentation/retrieve-metadata/rest-api/),
[OpenAlex API](https://help.openalex.org/api/authentication/),
[DataCite REST](https://support.datacite.org/docs/api),
[OpenReview API v2](https://docs.openreview.net/reference/api-v2), and
[Zotero local API](https://www.zotero.org/support/dev/client_coding/direct_integration/local_api).
