#!/bin/bash
# Sync local .env to GitHub Secret for production deployment
# Usage: ./scripts/sync-env.sh
#
# How it works:
# 1. Reads your local .env file
# 2. Applies production overrides from .env.production.overrides
# 3. Pushes the result as GitHub Secret PROD_ENV_FILE
# 4. On deploy, the workflow writes this secret to /opt/ai-translator/.env

set -e

ENV_FILE=".env"
OVERRIDES_FILE=".env.production.overrides"

# Check prerequisites
if [ ! -f "$ENV_FILE" ]; then
  echo "Error: $ENV_FILE not found"
  exit 1
fi

if ! command -v gh &> /dev/null; then
  echo "Error: GitHub CLI (gh) is not installed. Install: brew install gh"
  exit 1
fi

# Check gh auth
if ! gh auth status &> /dev/null 2>&1; then
  echo "Error: Not authenticated with GitHub CLI. Run: gh auth login"
  exit 1
fi

# Check overrides file exists
if [ ! -f "$OVERRIDES_FILE" ]; then
  echo "Error: $OVERRIDES_FILE not found."
  echo ""
  echo "Create it with your production-specific values:"
  echo "  cp env.production.overrides.example $OVERRIDES_FILE"
  echo "  # Edit with your prod bot token"
  echo ""
  exit 1
fi

echo "Building production .env..."

# Start with local .env
PROD_ENV=$(cat "$ENV_FILE")

# Apply overrides: for each KEY=VALUE in overrides, replace or append in prod env
while IFS= read -r line || [ -n "$line" ]; do
  # Skip empty lines and comments
  [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

  # Extract key
  KEY=$(echo "$line" | cut -d'=' -f1)

  if echo "$PROD_ENV" | grep -q "^${KEY}="; then
    # Replace existing key
    PROD_ENV=$(echo "$PROD_ENV" | sed "s|^${KEY}=.*|${line}|")
  else
    # Append new key
    PROD_ENV="${PROD_ENV}"$'\n'"${line}"
  fi
done < "$OVERRIDES_FILE"

# Show what will be pushed (keys only, no values)
echo ""
echo "Production .env keys:"
echo "$PROD_ENV" | grep -v '^#' | grep -v '^$' | cut -d'=' -f1 | sed 's/^/  /'
echo ""

# Count overrides applied
OVERRIDE_COUNT=$(grep -v '^#' "$OVERRIDES_FILE" | grep -v '^$' | wc -l | tr -d ' ')
echo "Overrides applied: $OVERRIDE_COUNT (from $OVERRIDES_FILE)"
echo ""

# Push to GitHub Secret
read -p "Push to GitHub Secret PROD_ENV_FILE? [y/N] " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo "$PROD_ENV" | gh secret set PROD_ENV_FILE
  echo ""
  echo "Done! PROD_ENV_FILE secret updated."
  echo "Next deploy (push to main) will use these env vars."
else
  echo "Cancelled."
fi
