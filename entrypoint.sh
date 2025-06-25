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
        jq -r '.default_branch // empty')
    
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
        jq -r '.object.sha // empty')
else
    # Use GraphQL to check all possibilities in a single request
    GRAPHQL_RESPONSE=$(curl -s -H "Authorization: bearer $GITHUB_TOKEN" \
        -X POST https://api.github.com/graphql \
        -d @- <<EOF
{
  "query": "query {
    repository(owner: \"$OWNER\", name: \"$REPO\") {
      branch: ref(qualifiedName: \"refs/heads/$BASE_REF\") {
        target {
          oid
        }
      }
      tag: ref(qualifiedName: \"refs/tags/$BASE_REF\") {
        target {
          oid
        }
      }
      commit: object(oid: \"$BASE_REF\") {
        ... on Commit {
          oid
        }
      }
    }
  }"
}
EOF
)
    
    # Extract SHA from GraphQL response using jq
    # Try branch first, then tag, then commit
    BASE_SHA=$(echo "$GRAPHQL_RESPONSE" | jq -r '
        .data.repository.branch.target.oid //
        .data.repository.tag.target.oid //
        .data.repository.commit.oid //
        empty
    ')
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
if echo "$RESPONSE" | jq -e '.ref' > /dev/null 2>&1; then
    echo "Successfully created branch '$BRANCH_NAME'"
else
    # Extract error message if available
    ERROR_MESSAGE=$(echo "$RESPONSE" | jq -r '.message // "Unknown error"')
    echo "Error creating branch: $ERROR_MESSAGE"
    echo "Full response: $RESPONSE"
    exit 1
fi
