# Quick PRD Generator

Generate a prd.json directly from a feature description. Use this when you want to skip the markdown intermediate step.

## Usage

Paste this prompt into Claude (chat or Claude Code), replacing the description:

---

I need to create a prd.json for an autonomous coding agent. The feature I want to build:

**[DESCRIBE YOUR FEATURE HERE]**

Technical context:
- Stack: [Rails/Django/Next.js/etc]
- Key directories: [app/, src/, etc]
- Patterns to follow: [any existing conventions]

Please:
1. Ask me 3-5 clarifying questions first
2. After I answer, generate prd.json with 4-8 small, focused user stories
3. Each story should be completable in one AI context window (~15-30 min of work)
4. Output ONLY valid JSON, no markdown code blocks

The JSON format:
```json
{
  "projectName": "Feature Name",
  "branchName": "feature/kebab-case-name", 
  "description": "What this feature does",
  "userStories": [
    {
      "id": "US-001",
      "title": "Short description",
      "priority": 1,
      "passes": false,
      "acceptanceCriteria": ["Criterion 1", "Criterion 2"],
      "technicalNotes": "Implementation hints"
    }
  ]
}
```

---

## Example Session

**You**: I need to create a prd.json for an autonomous coding agent. The feature I want to build:

Add a "save for later" feature to my Rails e-commerce app where users can save products they're interested in.

Technical context:
- Stack: Rails 7, Hotwire, PostgreSQL
- Key directories: app/models, app/controllers, app/views
- Patterns to follow: RESTful controllers, Stimulus for JS

**Claude**: Before I generate the PRD, let me ask a few clarifying questions:

1. Should "saved items" be tied to user accounts only, or should anonymous users be able to save items (via session/cookies)?
2. Where should the "save" button appear - product listing pages, product detail pages, or both?
3. Do you need a dedicated "My Saved Items" page, or just add them to the existing user dashboard?
4. Should there be a limit on how many items a user can save?
5. Do you want any notification features (e.g., "item on sale" or "low stock" for saved items)?

**You**: 
1. Logged in users only
2. Both listing and detail pages
3. Dedicated page at /saved-items
4. No limit
5. Not for now, but design for future extensibility

**Claude**: 
```json
{
  "projectName": "Save for Later",
  "branchName": "feature/save-for-later",
  "description": "Allow logged-in users to save products for later viewing",
  "userStories": [
    {
      "id": "US-001",
      "title": "Create saved_items table and model",
      "priority": 1,
      "passes": false,
      "acceptanceCriteria": [
        "Migration creates saved_items table with user_id and product_id",
        "SavedItem model exists with belongs_to associations",
        "User has_many :saved_items association",
        "Product has_many :saved_items association",
        "Unique constraint on [user_id, product_id]"
      ],
      "technicalNotes": "Follow existing migration patterns. Add index on user_id for query performance."
    },
    {
      "id": "US-002",
      "title": "Create SavedItems controller with create/destroy",
      "priority": 2,
      "passes": false,
      "acceptanceCriteria": [
        "POST /saved_items creates a saved item",
        "DELETE /saved_items/:id removes a saved item",
        "Both actions require authentication",
        "Returns appropriate status codes",
        "Handles duplicate saves gracefully"
      ],
      "technicalNotes": "Use before_action :authenticate_user!. Return 422 if already saved."
    }
  ]
}
```

(truncated for example - real output would have 4-8 stories)
