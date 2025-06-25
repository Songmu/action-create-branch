#!/bin/bash
set -euo pipefail

if [ -z "${GITHUB_TOKEN:-}" ]; then
    echo "Error: GITHUB_TOKEN is required"
    exit 1
fi

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
    DEFAULT_BRANCH=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        "https://api.github.com/repos/$REPOSITORY" | \
        grep '"default_branch":' | cut -d'"' -f4)
    
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
    BASE_SHA=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        "https://api.github.com/repos/$REPOSITORY/git/$BASE_REF" | \
        grep '"sha":' | cut -d'"' -f4)
else
    # First, try to get it as a branch
    BASE_SHA=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        "https://api.github.com/repos/$REPOSITORY/git/refs/heads/$BASE_REF" | \
        grep '"sha":' | cut -d'"' -f4)

    # If not found as a branch, try as a tag
    if [ -z "$BASE_SHA" ]; then
        BASE_SHA=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
            "https://api.github.com/repos/$REPOSITORY/git/refs/tags/$BASE_REF" | \
            grep '"sha":' | cut -d'"' -f4)
    fi

    # If still not found, try as a commit SHA
    if [ -z "$BASE_SHA" ]; then
        COMMIT_RESPONSE=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
            "https://api.github.com/repos/$REPOSITORY/git/commits/$BASE_REF")
        BASE_SHA=$(echo "$COMMIT_RESPONSE" | grep '"sha":' | head -n1 | cut -d'"' -f4)
    fi
fi

if [ -z "$BASE_SHA" ]; then
    echo "Error: Could not get SHA for ref '$BASE_REF'"
    exit 1
fi

echo "Base ref SHA: $BASE_SHA"

# Create the new branch
RESPONSE=$(curl -s -X POST -H "Authorization: token $GITHUB_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"ref\": \"refs/heads/$BRANCH_NAME\", \"sha\": \"$BASE_SHA\"}" \
    "https://api.github.com/repos/$REPOSITORY/git/refs")

# Check if branch was created successfully
if echo "$RESPONSE" | grep -q '"ref":'; then
    echo "Successfully created branch '$BRANCH_NAME'"
else
    echo "Error creating branch. Response: $RESPONSE"
    exit 1
fi