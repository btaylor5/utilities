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
# Add any setup commands that should run when creating new worktrees

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

    echo "✅ Success! Repository cloned to '$name/.bare-repo'"
    echo "💡 Use 'git worktree add' from within '$name' to create worktrees"
    echo "📂 Configuration stored in '$name/worktree-config/'"
}

cmd_add() {
    local name="$1"

    # Validate parameter
    if [ -z "$name" ]; then
        error_exit "Branch name is required. Usage: wtree.sh add <branch-name>"
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

    if [ "$remote_branch_exists" = true ]; then
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

    # Run initialization script if it exists
    if [ -x "worktree-config/worktree-Init.sh" ]; then
        echo "⚙️  Running initialization script..."
        if ! (cd "$name" && ../worktree-config/worktree-Init.sh); then
            echo "⚠️  Warning: Initialization script failed"
        fi
    fi

    echo "✅ Success! Worktree created at '$name'"
    echo "💡 Use 'cd $name' to switch to the new worktree"
}

cmd_remove() {
    # TODO: Implement remove functionality
    echo "Remove command not yet implemented"
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
