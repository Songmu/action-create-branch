#!/bin/bash
set -euo pipefail

# Set GH_TOKEN for gh command
export GH_TOKEN="$INPUT_TOKEN"

# Extract owner and repo from INPUT_REPOSITORY
if [[ ! "$INPUT_REPOSITORY" =~ ^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$ ]]; then
    echo "Error: INPUT_REPOSITORY must be in the format 'owner/repo'"
    exit 1
fi

OWNER=$(echo "$INPUT_REPOSITORY" | cut -d'/' -f1)
REPO=$(echo "$INPUT_REPOSITORY" | cut -d'/' -f2)

# Check if branch already exists
echo "Checking if branch '$INPUT_BRANCH' already exists..."
if gh api "repos/$INPUT_REPOSITORY/git/refs/heads/$INPUT_BRANCH" --silent > /dev/null 2>&1; then
    echo "Branch '$INPUT_BRANCH' already exists"
    # Set output for GitHub Actions
    echo "created=false" >> "${GITHUB_OUTPUT:-/dev/null}"
    exit 0
fi

# Determine the base ref
if [ -n "${INPUT_REF:-}" ]; then
    # Handle different ref formats
    if [[ "$INPUT_REF" =~ ^refs/(heads|tags|pull)/ ]]; then
        # Keep absolute refs as-is
        # refs/heads/* - branches
        # refs/tags/* - tags
        # refs/pull/* - pull request refs (e.g., refs/pull/123/head, refs/pull/123/merge)
        BASE_REF="$INPUT_REF"
        IS_ABS_REF=true
        echo "Using absolute ref: $BASE_REF"
    else
        # Treat as branch/tag name or commit SHA
        BASE_REF="$INPUT_REF"
        IS_ABS_REF=false
    fi
    echo "Creating branch '$INPUT_BRANCH' from ref '$BASE_REF' in repository '$INPUT_REPOSITORY'"
else
    # Get the default branch if no ref is specified
    DEFAULT_BRANCH=$(gh api "repos/$INPUT_REPOSITORY" \
        --jq '.default_branch // empty')

    if [ -z "$DEFAULT_BRANCH" ]; then
        echo "Error: Could not determine default branch for repository '$INPUT_REPOSITORY'"
        exit 1
    fi

    BASE_REF="$DEFAULT_BRANCH"
    IS_ABS_REF=false
    echo "Creating branch '$INPUT_BRANCH' from default branch '$BASE_REF' in repository '$INPUT_REPOSITORY'"
fi

# Get the SHA of the base ref
if [ "$IS_ABS_REF" = true ]; then
    # For absolute refs, get the SHA directly from the full ref path
    BASE_SHA=$(gh api "repos/$INPUT_REPOSITORY/git/$BASE_REF" \
        --jq '.object.sha // empty')
else
    # Check if BASE_REF looks like a SHA (7-40 hex chars)
    if [[ "$BASE_REF" =~ ^[a-f0-9]{7,40}$ ]]; then
        # Use GraphQL with commit object for SHA
        BASE_SHA=$(gh api graphql \
            -f query='query($owner: String!, $repo: String!, $ref: GitObjectID!, $branchRef: String!, $tagRef: String!) {
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
    else
        # Use GraphQL without commit object for branch/tag names
        BASE_SHA=$(gh api graphql \
            -f query='query($owner: String!, $repo: String!, $branchRef: String!, $tagRef: String!) {
                repository(owner: $owner, name: $repo) {
                    branch: ref(qualifiedName: $branchRef) {
                        target { oid }
                    }
                    tag: ref(qualifiedName: $tagRef) {
                        target { oid }
                    }
                }
            }' \
            -f owner="$OWNER" \
            -f repo="$REPO" \
            -f branchRef="refs/heads/$BASE_REF" \
            -f tagRef="refs/tags/$BASE_REF" \
            --jq '.data.repository.branch.target.oid // .data.repository.tag.target.oid // empty')
    fi
fi

if [ -z "$BASE_SHA" ]; then
    echo "Error: Could not get SHA for ref '$BASE_REF'"
    exit 1
fi

echo "Base ref SHA: $BASE_SHA"

# Create the new branch
echo "Creating branch with SHA: $BASE_SHA"
RESPONSE=$(gh api "repos/$INPUT_REPOSITORY/git/refs" \
    --method POST \
    -f ref="refs/heads/$INPUT_BRANCH" \
    -f sha="$BASE_SHA" 2>&1) || CREATE_FAILED=true

if [ -z "${CREATE_FAILED:-}" ]; then
    echo "Successfully created branch '$INPUT_BRANCH'"
    # Set output for GitHub Actions
    echo "created=true" >> "${GITHUB_OUTPUT:-/dev/null}"
else
    echo "Error creating branch '$INPUT_BRANCH'"
    # Extract error message from response if possible
    ERROR_MESSAGE=$(echo "$RESPONSE" | grep -o '"message":"[^"]*"' | cut -d'"' -f4 || echo "Unknown error")
    echo "Error details: $ERROR_MESSAGE"
    echo "Full response: $RESPONSE"
    exit 1
fi
