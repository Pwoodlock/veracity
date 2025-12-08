# Spec Initialization: Auto-Seed Salt State Templates

**Created:** 2025-12-08

## Feature Description

Automatically seed Salt State templates from db/seeds/salt_templates.rb during both initial installation and system upgrades. The seed file already exists and contains idempotent code to create or update Salt State templates (states, pillars, cloud profiles, and orchestrations) in the PostgreSQL database.

**Current State:**
- Seed file exists at: /mnt/d/Projects/veracity/db/seeds/salt_templates.rb
- Rake task exists: `rails salt:seed_templates`
- Templates are stored in PostgreSQL `salt_states` table, NOT on filesystem
- Templates are only written to /srv/salt/ on Salt Master when deployed

**Goal:**
Ensure templates are automatically loaded into the database during:
1. Fresh installation (rails db:setup / db:seed)
2. System upgrades (when deploying new versions)

---

This spec was initialized on 2025-12-08 for automatic template seeding functionality.
