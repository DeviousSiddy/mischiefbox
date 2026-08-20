# odoo-ref

Search Odoo 19.0/SaaS source code for models, fields, views, and patterns.

## What it does

Scans the Odoo source trees (community, enterprise, saas) and returns matching files with line numbers, so you can quickly find how features are implemented.

## Inputs

| Input | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `query` | string | yes | — | Search text (plain text, case-insensitive) |
| `source` | enum | no | `all` | `community`, `enterprise`, `saas`, or `all` |
| `module` | string | no | — | Filter to specific module (e.g. `sale`, `account`) |
| `limit` | int | no | 30 | Max files to return matches from |

## Usage examples

```bash
# Find the sale.order model definition
odoo-ref --query "_name = 'sale.order'" --module sale

# Find all fields named 'state' in the account module
odoo-ref --query "state = fields." --module account

# Search enterprise for pos.config
odoo-ref --query "pos.config" --source enterprise

# Find all uses of action_confirm in sale module
odoo-ref --query "action_confirm" --module sale

# Search everything for ir.actions.server
odoo-ref --query "ir.actions.server" --limit 20
```

## Output

Returns JSON with file paths and matching lines:

```json
{
  "count": 2,
  "results": [
    {
      "file": "community/odoo/addons/sale/models/sale_order.py",
      "matches": [
        {"line": 35, "content": "_name = 'sale.order'"},
        {"line": 36, "content": "_inherit = ['mail.thread', 'mail.activity.mixin']"}
      ]
    }
  ]
}
```

## Source trees

The tool expects Odoo source mounted at `/odoo`:

```
/odoo/
├── community/    ← Odoo community (19.0 branch)
├── enterprise/   ← Enterprise modules (commit 885edbc2)
└── saas/         ← SaaS-specific code (saas-19.4)
```

Windows path: `C:\Odoo\`
