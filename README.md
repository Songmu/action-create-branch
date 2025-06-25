# action-create-branch

A fast GitHub Action to create a new branch in a repository without checkout. Uses GitHub API directly for maximum performance.

## Features

- ⚡ **Fast execution**: No checkout required - uses GitHub API directly
- ✅ Create a new branch from any reference (branch, tag, or commit SHA)
- ✅ Skip creation if branch already exists (idempotent operation)
- ✅ Automatic token handling with `github.token`
- ✅ Support for cross-repository branch creation
- ✅ Efficient API usage with GraphQL and `gh` CLI
- ✅ Detailed output for downstream workflow steps

## Usage

### Basic Usage

```yaml
- name: Create feature branch
  uses: Songmu/action-create-branch@v1
  with:
    branch: feature/new-feature
```

### Advanced Usage

```yaml
- name: Create branch from specific ref
  id: create-branch
  uses: Songmu/action-create-branch@v1
  with:
    token: ${{ secrets.GITHUB_TOKEN }}
    repository: owner/repo
    branch: feature/new-feature
    ref: develop

- name: Check if branch was created
  if: steps.create-branch.outputs.created == 'true'
  run: echo "New branch was created!"
```

### Cross-Repository Usage

```yaml
- name: Create branch in another repository
  uses: Songmu/action-create-branch@v1
  with:
    token: ${{ secrets.PAT_TOKEN }}  # Needs write access to target repo
    repository: another-owner/another-repo
    branch: feature/cross-repo-branch
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `token` | GitHub token with write access to the repository | No | `${{ github.token }}` |
| `repository` | Repository name with owner (e.g., `owner/repo`) | No | `${{ github.repository }}` |
| `branch` | The name of the branch to create | Yes | - |
| `ref` | The ref (branch/tag/commit) to create the new branch from | No | `${{ github.ref }}` |

## Outputs

| Output | Description |
|--------|-------------|
| `created` | Whether the branch was created (`true`) or already existed (`false`) |

## Permissions

The action requires the following permissions:

```yaml
permissions:
  contents: write  # Required to create branches
```

## Examples

### Create Release Branch

```yaml
name: Create Release Branch
on:
  workflow_dispatch:
    inputs:
      version:
        description: 'Release version'
        required: true

jobs:
  create-release-branch:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - name: Create release branch
        uses: Songmu/action-create-branch@v1
        with:
          branch: release/v${{ github.event.inputs.version }}
          ref: develop
```

### Create Branch from Tag

```yaml
- name: Create hotfix branch from tag
  uses: Songmu/action-create-branch@v1
  with:
    branch: hotfix/urgent-fix
    ref: v1.0.0
```

### Create Branch from Commit SHA

```yaml
- name: Create branch from specific commit
  uses: Songmu/action-create-branch@v1
  with:
    branch: feature/from-commit
    ref: a1b2c3d4e5f6789
```

### Conditional Branch Creation

```yaml
- name: Create branch if needed
  id: create
  uses: Songmu/action-create-branch@v1
  with:
    branch: auto-generated-branch

- name: Push changes to new branch
  if: steps.create.outputs.created == 'true'
  run: |
    git checkout auto-generated-branch
    # Make changes...
    git push origin auto-generated-branch
```

## Error Handling

The action will:
- Exit successfully if the branch already exists (idempotent)
- Fail with detailed error message if branch creation fails
- Provide full API response for debugging

## License

MIT License - see [LICENSE](LICENSE) file for details.
