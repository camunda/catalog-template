# Camunda Hub Catalog — example asset repository

This is a template repository for publishing reusable **element templates** to the
[Camunda Hub Catalog](https://docs.camunda.io/docs/components/hub/organization/manage-catalog/manage-catalog/).

A [GitHub Actions workflow](.github/workflows/sync-catalog.yml) submits the
templates in this repository to the Hub Catalog whenever you push to `main`. The
submission represents the **complete desired state** of the Catalog: assets in
this repository are published or updated, and any asset that is no longer present
is unpublished.

Use it as a starting point: clone or use it as a template, replace the example
assets with your own, configure the required secrets, and push.

## Repository layout

Each asset lives in its own directory containing exactly two files:

```
.
├── notify-customer/
│   ├── README.md              # asset metadata (frontmatter) + description (body)
│   └── notify-customer.json   # the element template
├── approve-request/
│   ├── README.md
│   └── approve-request.json
├── scripts/
│   └── sync-catalog.sh        # discovers assets and calls the Catalog API
└── .github/workflows/
    └── sync-catalog.yml        # runs the sync on every push to main
```

- **`README.md`** — YAML frontmatter plus a Markdown description. The frontmatter
  must include a `template:` field that names the `.json` file in the same
  directory. `category` and `tags` are optional and power search and filtering in
  the Catalog. The Markdown body is shown as the asset description.
- **Element template (`.json`)** — the element template descriptor. Its `id` and
  `version` fields are authoritative for the asset's identity and version. The
  asset name, short description, and icon are read from this file, not the
  frontmatter.

The two example assets are placeholders. Replace them with your own templates.

## Setup

### 1. Create client credentials

Create credentials with the **Camunda Hub API** permissions `create` and `update`
(the ingestion endpoint requires both). To delete assets, also grant `delete`.

- **SaaS:** In Camunda Hub, go to **Organization > Administration API > Create API
  Client**, grant access to the **Camunda Hub API**, and copy the client ID and
  secret. See the
  [SaaS authentication guide](https://docs.camunda.io/docs/apis-tools/hub-api-saas/authentication/).
- **Self-Managed:** Add an M2M application in Management Identity, grant it access
  to the **Camunda Hub API**, and copy the client ID and secret. See the
  [Self-Managed authentication guide](https://docs.camunda.io/docs/apis-tools/hub-api-sm/authentication/).

### 2. Add repository secrets

In **Settings > Secrets and variables > Actions**, add:

| Secret                          | Description                      |
| ------------------------------- | -------------------------------- |
| `CAMUNDA_CONSOLE_CLIENT_ID`     | OAuth client ID from step 1.     |
| `CAMUNDA_CONSOLE_CLIENT_SECRET` | OAuth client secret from step 1. |

### 3. Configure the environment URLs

The workflow defaults to **SaaS**. For Self-Managed, edit the `env` block in
[`.github/workflows/sync-catalog.yml`](.github/workflows/sync-catalog.yml):

| Variable                         | SaaS                                         | Self-Managed                                            |
| -------------------------------- | -------------------------------------------- | ------------------------------------------------------- |
| `CAMUNDA_OAUTH_URL`              | `https://login.cloud.camunda.io/oauth/token` | `<your-identity>/protocol/openid-connect/token`         |
| `CAMUNDA_CONSOLE_OAUTH_AUDIENCE` | `api.cloud.camunda.io`                       | _(leave unset — Management Identity adds the `web-modeler-public-api` audience)_ |
| `CAMUNDA_HUB_BASE_URL`           | `https://hub.cloud.camunda.io`               | your Hub API base URL (default `http://localhost:8088`) |

### 4. Push

Commit and push to `main`, or run the **Sync Catalog** workflow manually from the
**Actions** tab. The script prints the number of assets submitted and fails the
job if the Catalog API rejects the submission.

## Run locally

You can run the sync from your machine with the same environment variables:

```bash
export CAMUNDA_CONSOLE_CLIENT_ID="<client-id>"
export CAMUNDA_CONSOLE_CLIENT_SECRET="<client-secret>"
export CAMUNDA_OAUTH_URL="https://login.cloud.camunda.io/oauth/token"
export CAMUNDA_CONSOLE_OAUTH_AUDIENCE="api.cloud.camunda.io"
export CAMUNDA_HUB_BASE_URL="https://hub.cloud.camunda.io"

bash scripts/sync-catalog.sh
```

Requires `bash`, `curl`, and `jq`.

## Versioning

When you change a template's content, increment its `version` field. The Catalog
rejects a changed template whose `version` is not greater than the latest stored
version. If the content is unchanged, the version may stay the same and no new
version is created.
