#!/bin/bash

# Git Worktree Helper Script
# Simplifies working with git worktrees

VERSION="1.0.0"

# Error handling function
error_exit() {
    echo "Error: $1" >&2
    exit 1
}

# Command functions
cmd_clone() {
    local repository="$1"
    local name="$2"

    # Validate parameters
    if [ -z "$repository" ]; then
        error_exit "Repository URL is required. Usage: wtree.sh clone <repository> <name>"
    fi

    if [ -z "$name" ]; then
        error_exit "Directory name is required. Usage: wtree.sh clone <repository> <name>"
    fi

    # Check if directory already exists
    if [ -d "$name" ]; then
        error_exit "Directory '$name' already exists"
    fi

    echo "📁 Creating directory structure for '$name'..."

    # Create main directory
    if ! mkdir "$name"; then
        error_exit "Failed to create directory '$name'"
    fi

    # Clone bare repository
    echo "🔄 Cloning repository into bare repo..."
    if ! git clone "$repository" --bare "$name/.bare-repo" 2>&1; then
        rm -rf "$name"
        error_exit "Git clone failed for repository '$repository'"
    fi

    # Update git config to point worktree to the bare repo
    echo "⚙️  Configuring git worktree settings..."
    if ! (cd "$name" && git --git-dir=.bare-repo config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*" 2>&1); then
        rm -rf "$name"
        error_exit "Failed to configure git remote fetch settings"
    fi

    # Create worktree-config directory
    echo "📝 Creating worktree configuration directory..."
    if ! mkdir -p "$name/worktree-config"; then
        rm -rf "$name"
        error_exit "Failed to create worktree-config directory"
    fi

    # Generate empty init script in worktree-config
    local init_script="$name/worktree-config/worktree-Init.sh"
    if ! cat > "$init_script" << 'EOF'
#!/bin/bash
# Worktree initialization script
#
# This script runs after each new worktree is created.
# Add any setup commands that should run when creating new worktrees.
#
# Examples:
#   - npm install / yarn install
#   - Copy environment files
#   - Create symlinks
#   - Set up git hooks
#   - Initialize databases
#
# The script runs from within the new worktree directory.
# Exit with non-zero to indicate failure (will show warning but won't stop worktree creation)

echo "Running worktree initialization..."

# Add your initialization commands here
# Example:
# if [ -f package.json ]; then
#     echo "Installing dependencies..."
#     npm install
# fi

echo "Initialization complete!"
EOF
    then
        rm -rf "$name"
        error_exit "Failed to create initialization script"
    fi

    # Make init script executable
    if ! chmod +x "$init_script"; then
        rm -rf "$name"
        error_exit "Failed to make initialization script executable"
    fi

    # Create README for worktree-config
    local readme="$name/worktree-config/README.md"
    if ! cat > "$readme" << 'EOF'
# Worktree Configuration Directory

This directory contains files and scripts that are automatically copied to each new worktree.

## Files

- **worktree-Init.sh**: Initialization script that runs after each worktree is created
- Any other files in this directory will be copied to the root of new worktrees

## Usage

### Adding Config Files

Place any files you want copied to new worktrees in this directory:
- `.env.example` - Environment variable templates
- `.vscode/settings.json` - Editor settings
- `config.local.json` - Local configuration files
- Any other files or directories

### Customizing Initialization

Edit `worktree-Init.sh` to add commands that should run when creating worktrees:
```bash
#!/bin/bash
echo "Setting up worktree..."

# Install dependencies
npm install

# Copy environment file
cp .env.example .env

# Create necessary directories
mkdir -p logs tmp
```

### Creating Worktrees

Use the `wtree.sh add` command to create new worktrees:
```bash
# Interactive mode (prompts if remote branch exists)
./wtree.sh add feature-branch

# Use existing remote branch
./wtree.sh add feature-branch --from-remote

# Start fresh from main/master
./wtree.sh add feature-branch --start-fresh
```
EOF
    then
        echo "⚠️  Warning: Failed to create README in worktree-config"
    fi

    echo "✅ Success! Repository cloned to '$name/.bare-repo'"
    echo "💡 Next steps:"
    echo "   1. cd $name"
    echo "   2. Customize worktree-config/worktree-Init.sh for your project"
    echo "   3. Add config files to worktree-config/ to copy to new worktrees"
    echo "   4. Create your first worktree: wtree.sh add <branch-name>"
}

cmd_add() {
    local name=""
    local from_remote=false
    local start_fresh=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --from-remote)
                from_remote=true
                shift
                ;;
            --start-fresh)
                start_fresh=true
                shift
                ;;
            -*)
                error_exit "Unknown option: $1. Usage: wtree.sh add <branch-name> [--from-remote|--start-fresh]"
                ;;
            *)
                if [ -z "$name" ]; then
                    name="$1"
                    shift
                else
                    error_exit "Unexpected argument: $1"
                fi
                ;;
        esac
    done

    # Validate parameters
    if [ -z "$name" ]; then
        error_exit "Branch name is required. Usage: wtree.sh add <branch-name> [--from-remote|--start-fresh]"
    fi

    # Check for conflicting flags
    if [ "$from_remote" = true ] && [ "$start_fresh" = true ]; then
        error_exit "Cannot use both --from-remote and --start-fresh flags"
    fi

    # Check if we're in a wtree repository (has .bare-repo)
    if [ ! -d ".bare-repo" ]; then
        error_exit "Not in a wtree repository. Run this command from the repository root (where .bare-repo exists)"
    fi

    # Fetch latest from remote
    echo "🔄 Fetching latest from remote..."
    if ! git --git-dir=.bare-repo fetch origin 2>&1; then
        error_exit "Failed to fetch from remote"
    fi

    # Detect the default remote branch (main or master)
    local default_branch=""
    if git --git-dir=.bare-repo show-ref --verify --quiet "refs/remotes/origin/main"; then
        default_branch="origin/main"
    elif git --git-dir=.bare-repo show-ref --verify --quiet "refs/remotes/origin/master"; then
        default_branch="origin/master"
    else
        error_exit "Could not find origin/main or origin/master branch"
    fi

    # Check if branch exists on remote
    local remote_branch_exists=false
    if git --git-dir=.bare-repo show-ref --verify --quiet "refs/remotes/origin/$name"; then
        remote_branch_exists=true
    fi

    local base_branch=""

    # Handle --from-remote flag
    if [ "$from_remote" = true ]; then
        if [ "$remote_branch_exists" = true ]; then
            base_branch="origin/$name"
            echo "✓ Using remote branch 'origin/$name'"
        else
            error_exit "Remote branch 'origin/$name' does not exist. Use --start-fresh to create from $default_branch"
        fi
    # Handle --start-fresh flag
    elif [ "$start_fresh" = true ]; then
        base_branch="$default_branch"
        echo "✓ Creating new branch from $default_branch"
    # Interactive mode (no flags)
    elif [ "$remote_branch_exists" = true ]; then
        echo "🌿 Remote branch 'origin/$name' exists."
        read -p "Do you want to base your worktree off the remote branch? (y/n): " -n 1 -r
        echo

        if [[ $REPLY =~ ^[Yy]$ ]]; then
            base_branch="origin/$name"
            echo "✓ Will create worktree from remote branch 'origin/$name'"
        else
            base_branch="$default_branch"
            echo "✓ Will create worktree from $default_branch"
        fi
    else
        base_branch="$default_branch"
        echo "ℹ️  Branch does not exist on remote. Creating new branch from $default_branch."
    fi

    # Create the worktree
    echo "📁 Creating worktree '$name'..."

    # Create worktree from the selected base branch
    if ! git --git-dir=.bare-repo worktree add "$name" -b "$name" "$base_branch" 2>&1; then
        error_exit "Failed to create worktree from $base_branch"
    fi

    # Initialize the worktree with config files and scripts
    echo "⚙️  Initializing worktree..."

    # Copy config files from worktree-config to the new worktree
    if [ -d "worktree-config" ]; then
        # Copy all files except the init script and README
        local copied_files=0

        # Enable dotglob to match hidden files
        shopt -s dotglob nullglob

        for file in worktree-config/*; do
            local basename_file="$(basename "$file")"

            # Skip if it's the init script or README
            if [ "$basename_file" = "worktree-Init.sh" ] || [ "$basename_file" = "README.md" ]; then
                continue
            fi

            # Skip if no files exist (glob didn't match anything)
            if [ ! -e "$file" ]; then
                continue
            fi

            # Check if file already exists in worktree
            if [ -e "$name/$basename_file" ]; then
                echo "  ⚠️  Skipped $basename_file (already exists in worktree)"
                continue
            fi

            # Copy file or directory
            if cp -r "$file" "$name/"; then
                copied_files=$((copied_files + 1))
                echo "  ✓ Copied $basename_file"
            else
                echo "  ⚠️  Warning: Failed to copy $basename_file"
            fi
        done

        # Disable dotglob
        shopt -u dotglob nullglob

        if [ $copied_files -eq 0 ]; then
            echo "  ℹ️  No config files to copy"
        fi
    fi

    # Run initialization script if it exists
    if [ -x "worktree-config/worktree-Init.sh" ]; then
        echo "  🔧 Running initialization script..."
        if (cd "$name" && ../worktree-config/worktree-Init.sh); then
            echo "  ✓ Initialization script completed successfully"
        else
            echo "  ⚠️  Warning: Initialization script failed (exit code: $?)"
        fi
    else
        if [ -f "worktree-config/worktree-Init.sh" ]; then
            echo "  ⚠️  Warning: worktree-Init.sh exists but is not executable"
        fi
    fi

    echo "✅ Success! Worktree created at '$name'"
    echo "💡 Use 'cd $name' to switch to the new worktree"

}

cmd_remove() {
    local name=""
    local force=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force|-f)
                force=true
                shift
                ;;
            -*)
                error_exit "Unknown option: $1. Usage: wtree.sh remove <worktree-name> [--force]"
                ;;
            *)
                if [ -z "$name" ]; then
                    name="$1"
                    shift
                else
                    error_exit "Unexpected argument: $1"
                fi
                ;;
        esac
    done

    # Validate parameters
    if [ -z "$name" ]; then
        error_exit "Worktree name is required. Usage: wtree.sh remove <worktree-name> [--force]"
    fi

    # Check if we're in a wtree repository (has .bare-repo)
    if [ ! -d ".bare-repo" ]; then
        error_exit "Not in a wtree repository. Run this command from the repository root (where .bare-repo exists)"
    fi

    # Check if worktree exists
    if [ ! -d "$name" ]; then
        error_exit "Worktree '$name' does not exist"
    fi

    # Verify it's actually a worktree
    if ! git --git-dir=.bare-repo worktree list | grep -q "/$name "; then
        error_exit "'$name' exists but is not a git worktree"
    fi

    # Get the branch name for this worktree
    local branch_name=""
    branch_name=$(git --git-dir=.bare-repo worktree list --porcelain | grep -A 2 "/$name$" | grep "^branch" | sed 's/branch refs\/heads\///')

    if [ -z "$branch_name" ]; then
        echo "⚠️  Warning: Could not determine branch name for worktree '$name'"
        echo "   This might be a detached HEAD worktree"
    else
        echo "🔍 Checking merge status of branch '$branch_name'..."

        # Fetch latest from remote
        echo "🔄 Fetching latest from remote..."
        if ! git --git-dir=.bare-repo fetch origin 2>&1; then
            echo "⚠️  Warning: Failed to fetch from remote. Merge status check may be inaccurate."
        fi

        # Detect the default remote branch (main or master)
        local default_branch=""
        if git --git-dir=.bare-repo show-ref --verify --quiet "refs/remotes/origin/main"; then
            default_branch="origin/main"
        elif git --git-dir=.bare-repo show-ref --verify --quiet "refs/remotes/origin/master"; then
            default_branch="origin/master"
        else
            echo "⚠️  Warning: Could not find origin/main or origin/master branch"
        fi

        if [ -n "$default_branch" ]; then
            # Check if the branch is merged into the default remote branch
            local is_merged=false

            # Get the commit hash of the branch
            local branch_commit=""
            branch_commit=$(git --git-dir=.bare-repo rev-parse "refs/heads/$branch_name" 2>/dev/null)

            if [ -n "$branch_commit" ]; then
                # Check if this commit is an ancestor of the default branch (i.e., it's been merged)
                if git --git-dir=.bare-repo merge-base --is-ancestor "refs/heads/$branch_name" "$default_branch" 2>/dev/null; then
                    is_merged=true
                fi
            fi

            if [ "$is_merged" = true ]; then
                echo "✓ Branch '$branch_name' has been merged into $default_branch"
            else
                echo "⚠️  Branch '$branch_name' has NOT been merged into $default_branch"

                if [ "$force" = false ]; then
                    echo ""
                    echo "The branch may contain unmerged changes. Options:"
                    echo "  1. Merge or push your changes first"
                    echo "  2. Use --force flag to remove anyway: wtree.sh remove $name --force"
                    echo ""
                    read -p "Do you want to remove this worktree anyway? (y/n): " -n 1 -r
                    echo

                    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                        echo "❌ Removal cancelled"
                        exit 0
                    fi
                fi
            fi
        fi
    fi

    # Remove the worktree
    echo "🗑️  Removing worktree '$name'..."
    if ! git --git-dir=.bare-repo worktree remove "$name" 2>&1; then
        echo "⚠️  Failed to remove worktree with git command. Trying with --force..."
        if ! git --git-dir=.bare-repo worktree remove "$name" --force 2>&1; then
            error_exit "Failed to remove worktree '$name'"
        fi
    fi

    echo "✅ Worktree '$name' removed successfully"

    # Delete the associated branch
    if [ -n "$branch_name" ]; then
        echo "🌿 Deleting branch '$branch_name'..."
        if git --git-dir=.bare-repo branch -d "$branch_name" 2>&1; then
            echo "✅ Branch '$branch_name' deleted"
        else
            echo "⚠️  Could not delete branch with -d (branch may not be fully merged)"
            read -p "Force delete the branch? This will lose any unmerged changes. (y/n): " -n 1 -r
            echo

            if [[ $REPLY =~ ^[Yy]$ ]]; then
                if git --git-dir=.bare-repo branch -D "$branch_name" 2>&1; then
                    echo "✅ Branch '$branch_name' force deleted"
                else
                    echo "⚠️  Warning: Failed to delete branch '$branch_name'"
                fi
            else
                echo "ℹ️  Branch '$branch_name' was not deleted"
            fi
        fi
    fi
}

cmd_help() {
    # TODO: Implement help functionality
    echo "Help command not yet implemented"
}

cmd_generate_autocomplete() {
    # TODO: Implement generate-autocomplete functionality
    echo "Generate-autocomplete command not yet implemented"
}

# Main command dispatcher
main() {
    if [ $# -eq 0 ]; then
        cmd_help
        exit 1
    fi

    local command="$1"
    shift

    case "$command" in
        clone)
            cmd_clone "$@"
            ;;
        add)
            cmd_add "$@"
            ;;
        remove)
            cmd_remove "$@"
            ;;
        help|--help|-h)
            cmd_help "$@"
            ;;
        generate-autocomplete)
            cmd_generate_autocomplete "$@"
            ;;
        *)
            echo "Error: Unknown command '$command'"
            echo "Run 'wtree.sh help' for usage information"
            exit 1
            ;;
    esac
}

main "$@"
