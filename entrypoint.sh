#!/bin/bash
set -euo pipefail

if [ -z "${GITHUB_TOKEN:-}" ]; then
    echo "Error: GITHUB_TOKEN is required"
    exit 1
fi

# Set GH_TOKEN for gh command
export GH_TOKEN="$GITHUB_TOKEN"

if [ -z "${REPOSITORY:-}" ]; then
    echo "Error: REPOSITORY is required"
    exit 1
fi

if [ -z "${BRANCH_NAME:-}" ]; then
    echo "Error: BRANCH_NAME is required"
    exit 1
fi

# Extract owner and repo from REPOSITORY
if [[ ! "$REPOSITORY" =~ ^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$ ]]; then
    echo "Error: REPOSITORY must be in the format 'owner/repo'"
    exit 1
fi

OWNER=$(echo "$REPOSITORY" | cut -d'/' -f1)
REPO=$(echo "$REPOSITORY" | cut -d'/' -f2)

# Check if branch already exists
echo "Checking if branch '$BRANCH_NAME' already exists..."
if gh api "repos/$REPOSITORY/git/refs/heads/$BRANCH_NAME" --silent > /dev/null 2>&1; then
    echo "Branch '$BRANCH_NAME' already exists"
    # Set output for GitHub Actions
    echo "created=false" >> "${GITHUB_OUTPUT:-/dev/null}"
    exit 0
fi

# Determine the base ref
if [ -n "${REF:-}" ]; then
    # Handle different ref formats
    if [[ "$REF" =~ ^refs/(heads|tags|pull)/ ]]; then
        # Keep absolute refs as-is
        # refs/heads/* - branches
        # refs/tags/* - tags
        # refs/pull/* - pull request refs (e.g., refs/pull/123/head, refs/pull/123/merge)
        BASE_REF="$REF"
        IS_ABS_REF=true
        echo "Using absolute ref: $BASE_REF"
    else
        # Treat as branch/tag name or commit SHA
        BASE_REF="$REF"
        IS_ABS_REF=false
    fi
    echo "Creating branch '$BRANCH_NAME' from ref '$BASE_REF' in repository '$REPOSITORY'"
else
    # Get the default branch if no ref is specified
    DEFAULT_BRANCH=$(gh api "repos/$REPOSITORY" \
        --jq '.default_branch // empty')
    
    if [ -z "$DEFAULT_BRANCH" ]; then
        echo "Error: Could not determine default branch for repository '$REPOSITORY'"
        exit 1
    fi
    
    BASE_REF="$DEFAULT_BRANCH"
    IS_ABS_REF=false
    echo "Creating branch '$BRANCH_NAME' from default branch '$BASE_REF' in repository '$REPOSITORY'"
fi

# Get the SHA of the base ref
if [ "$IS_ABS_REF" = true ]; then
    # For absolute refs, get the SHA directly from the full ref path
    BASE_SHA=$(gh api "repos/$REPOSITORY/git/$BASE_REF" \
        --jq '.object.sha // empty')
else
    # Use GraphQL to check all possibilities in a single request
    BASE_SHA=$(gh api graphql \
        -f query='query($owner: String!, $repo: String!, $ref: String!, $branchRef: String!, $tagRef: String!) {
            repository(owner: $owner, name: $repo) {
                branch: ref(qualifiedName: $branchRef) {
                    target { oid }
                }
                tag: ref(qualifiedName: $tagRef) {
                    target { oid }
                }
                commit: object(oid: $ref) {
                    ... on Commit { oid }
                }
            }
        }' \
        -f owner="$OWNER" \
        -f repo="$REPO" \
        -f ref="$BASE_REF" \
        -f branchRef="refs/heads/$BASE_REF" \
        -f tagRef="refs/tags/$BASE_REF" \
        --jq '.data.repository.branch.target.oid // .data.repository.tag.target.oid // .data.repository.commit.oid // empty')
fi

if [ -z "$BASE_SHA" ]; then
    echo "Error: Could not get SHA for ref '$BASE_REF'"
    exit 1
fi

echo "Base ref SHA: $BASE_SHA"

# Create the new branch
echo "Creating branch with SHA: $BASE_SHA"
if gh api "repos/$REPOSITORY/git/refs" \
    --method POST \
    -f ref="refs/heads/$BRANCH_NAME" \
    -f sha="$BASE_SHA" > /dev/null 2>&1; then
    echo "Successfully created branch '$BRANCH_NAME'"
    # Set output for GitHub Actions
    echo "created=true" >> "${GITHUB_OUTPUT:-/dev/null}"
else
    echo "Error creating branch '$BRANCH_NAME'"
    # Try to get more detailed error information
    ERROR_RESPONSE=$(gh api "repos/$REPOSITORY/git/refs" \
        --method POST \
        -f ref="refs/heads/$BRANCH_NAME" \
        -f sha="$BASE_SHA" 2>&1 || true)
    echo "Error details: $ERROR_RESPONSE"
    exit 1
fi
