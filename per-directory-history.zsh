#!/usr/bin/env zsh
#
# This is a implementation of per directory history for zsh, with support for per-git-repo history.
# When in a git repo, history is stored locally in the git repo instead of in the default location.
# Original implementation by Jim Hester, modified to support git repos.
#
# It also implements a per-directory-history-toggle-history function to change from using the
# directory/repo history to using the global history. In both cases the history is
# always saved to both the global history and the local history, so the
# toggle state will not effect the saved histories.
#
#-------------------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------------------
#
# HISTORY_BASE a global variable that defines the base directory in which the
# directory histories are stored (for non-git directories)
#
# GIT_HISTORY_NAME the name of the history file to create in git repositories
# (defaults to .git_zsh_history)
#
################################################################################

#-------------------------------------------------------------------------------
# configuration, the base under which the directory histories are stored
#-------------------------------------------------------------------------------

[[ -z $HISTORY_BASE ]] && HISTORY_BASE="$HOME/.directory_history"
[[ -z $GIT_HISTORY_NAME ]] && GIT_HISTORY_NAME=".zsh_history"
[[ -z $HISTORY_START_WITH_GLOBAL ]] && HISTORY_START_WITH_GLOBAL=false
[[ -z $PER_DIRECTORY_HISTORY_TOGGLE ]] && PER_DIRECTORY_HISTORY_TOGGLE='^G'

#-------------------------------------------------------------------------------
# Function to determine if current directory is in a git repo
# and get the repository root if so
#-------------------------------------------------------------------------------

function _is_in_git_repo() {
  git rev-parse --is-inside-work-tree &>/dev/null
  return $?
}

function _is_in_git_repo_at_path() {
  local path="$1"
  git -C "$path" rev-parse --is-inside-work-tree &>/dev/null
  return $?
}

function _get_git_repo_root() {
  git rev-parse --show-toplevel
}

function _get_git_repo_root_at_path() {
  local path="$1"
  git -C "$path" rev-parse --show-toplevel 2>/dev/null
}

#-------------------------------------------------------------------------------
# Function to set the appropriate history file path
#-------------------------------------------------------------------------------

function _set_per_directory_history_path() {
  if _is_in_git_repo; then
    # Get git repo root
    local repo_root=$(_get_git_repo_root)
    _per_directory_history_directory="${repo_root}/${GIT_HISTORY_NAME}"
  else
    # Use traditional per-directory history
    _per_directory_history_directory="$HISTORY_BASE${PWD:A}/history"
  fi
  
  # Ensure parent directory exists if needed
  if [[ $_per_directory_history_directory == */* ]]; then
    mkdir -p ${_per_directory_history_directory:h}
  fi
}

#-------------------------------------------------------------------------------
# Function to get history path for a specific directory
#-------------------------------------------------------------------------------
function _get_history_file_for_directory() {
  local directory="$1"
  local history_path
  
  if _is_in_git_repo_at_path "$directory"; then
    local gitroot=$(_get_git_repo_root_at_path "$directory")
    history_path="${gitroot}/${GIT_HISTORY_NAME}"
  else
    history_path="$HISTORY_BASE${directory:A}/history"
  fi
  
  echo "$history_path"
}

#-------------------------------------------------------------------------------
# toggle global/directory history used for searching - ctrl-G by default
#-------------------------------------------------------------------------------

function per-directory-history-toggle-history() {
  if [[ $_per_directory_history_is_global == true ]]; then
    _per-directory-history-set-directory-history
    _per_directory_history_is_global=false
    zle -I
    if _is_in_git_repo; then
      echo "using git repo history"
    else
      echo "using local directory history"
    fi
  else
    _per-directory-history-set-global-history
    _per_directory_history_is_global=true
    zle -I
    echo "using global history"
  fi
}

autoload per-directory-history-toggle-history
zle -N per-directory-history-toggle-history
bindkey $PER_DIRECTORY_HISTORY_TOGGLE per-directory-history-toggle-history
bindkey -M vicmd $PER_DIRECTORY_HISTORY_TOGGLE per-directory-history-toggle-history

#-------------------------------------------------------------------------------
# implementation details
#-------------------------------------------------------------------------------

function _per-directory-history-change-directory() {
  if [[ $_per_directory_history_is_global == false ]]; then
    # Save to the global history
    fc -AI $HISTFILE
    
    # Determine previous history file based on OLD directory
    local prev_history_path=$(_get_history_file_for_directory "$OLDPWD")
    
    # Make sure the directory exists
    if [[ $prev_history_path == */* ]]; then
      mkdir -p ${prev_history_path:h}
    fi
    
    # Save history to previous directory's history file
    fc -AI "$prev_history_path"
    
    # Set the new history file path based on current directory
    _set_per_directory_history_path
    
    # Discard previous directory's history
    local original_histsize=$HISTSIZE
    HISTSIZE=0
    HISTSIZE=$original_histsize

    # Read history in new file
    if [[ -e $_per_directory_history_directory ]]; then
      fc -R $_per_directory_history_directory
    fi
  else
    # Even when using global history, update the directory path
    _set_per_directory_history_path
  fi
}

function _per-directory-history-addhistory() {
  # Respect hist_ignore_space
  if [[ -o hist_ignore_space ]] && [[ "$1" == \ * ]]; then
      true
  else
      print -Sr -- "${1%%$'\n'}"
      # Instantly write history if set options require it.
      if [[ -o share_history ]] || \
         [[ -o inc_append_history ]] || \
         [[ -o inc_append_history_time ]]; then
          fc -AI $HISTFILE
          fc -AI $_per_directory_history_directory
      fi
      fc -p $_per_directory_history_directory
  fi
}

function _per-directory-history-precmd() {
  if [[ $_per_directory_history_initialized == false ]]; then
    _per_directory_history_initialized=true
    
    # Initial setup of history file path
    _set_per_directory_history_path

    if [[ $HISTORY_START_WITH_GLOBAL == true ]]; then
      _per-directory-history-set-global-history
      _per_directory_history_is_global=true
    else
      _per-directory-history-set-directory-history
      _per_directory_history_is_global=false
    fi
  fi
}

function _per-directory-history-set-directory-history() {
  fc -AI $HISTFILE
  local original_histsize=$HISTSIZE
  HISTSIZE=0
  HISTSIZE=$original_histsize
  if [[ -e "$_per_directory_history_directory" ]]; then
    fc -R "$_per_directory_history_directory"
  fi
}

function _per-directory-history-set-global-history() {
  fc -AI $_per_directory_history_directory
  local original_histsize=$HISTSIZE
  HISTSIZE=0
  HISTSIZE=$original_histsize
  if [[ -e "$HISTFILE" ]]; then
    fc -R "$HISTFILE"
  fi
}

# Initialize
_set_per_directory_history_path

# Add functions to the exec list for chpwd and zshaddhistory
autoload -U add-zsh-hook
add-zsh-hook chpwd _per-directory-history-change-directory
add-zsh-hook zshaddhistory _per-directory-history-addhistory
add-zsh-hook precmd _per-directory-history-precmd

# Set initialized flag to false
_per_directory_history_initialized=false
