#!/usr/bin/env bash

{ # this ensures the entire script is downloaded #

nvm_has() {
  type "$1" > /dev/null 2>&1
}

nvm_install_dir() {
  echo "${NVM_DIR:-"/home/ec2-user/.nvm"}"
}
#HOme=/home/ec2-user
nvm_latest_version() {
  echo "v0.32.0"
}

#
# Outputs the location to NVM depending on:
# * The availability of $NVM_SOURCE
# * The method used ("script" or "git" in the script, defaults to "git")
# NVM_SOURCE always takes precedence unless the method is "script-nvm-exec"
#
nvm_source() {
  local NVM_METHOD
  NVM_METHOD="$1"
  local NVM_SOURCE_URL
  NVM_SOURCE_URL="$NVM_SOURCE"
  if [ "_$NVM_METHOD" = "_script-nvm-exec" ]; then
    NVM_SOURCE_URL="https://raw.githubusercontent.com/creationix/nvm/$(nvm_latest_version)/nvm-exec"
  elif [ -z "$NVM_SOURCE_URL" ]; then
    if [ "_$NVM_METHOD" = "_script" ]; then
      NVM_SOURCE_URL="https://raw.githubusercontent.com/creationix/nvm/$(nvm_latest_version)/nvm.sh"
    elif [ "_$NVM_METHOD" = "_git" ] || [ -z "$NVM_METHOD" ]; then
      NVM_SOURCE_URL="https://github.com/creationix/nvm.git"
    else
      echo >&2 "Unexpected value \"$NVM_METHOD\" for \$NVM_METHOD"
      return 1
    fi
  fi
  echo "$NVM_SOURCE_URL"
}

#
# Node.js version to install
#
nvm_node_version() {
  echo "$NODE_VERSION"
}

nvm_download() {
  if nvm_has "curl"; then
    curl -q "$@"
  elif nvm_has "wget"; then
    # Emulate curl with wget
    ARGS=$(echo "$*" | command sed -e 's/--progress-bar /--progress=bar /' \
                           -e 's/-L //' \
                           -e 's/-I /--server-response /' \
                           -e 's/-s /-q /' \
                           -e 's/-o /-O /' \
                           -e 's/-C - /-c /')
    # shellcheck disable=SC2086
    eval wget $ARGS
  fi
}

install_nvm_from_git() {
  local INSTALL_DIR
  INSTALL_DIR="$(nvm_install_dir)"

  if [ -d "$INSTALL_DIR/.git" ]; then
    echo "=> nvm is already installed in $INSTALL_DIR, trying to update using git"
    command printf "\r=> "
    command git --git-dir="$INSTALL_DIR"/.git --work-tree="$INSTALL_DIR" fetch 2> /dev/null || {
      echo >&2 "Failed to update nvm, run 'git fetch' in $INSTALL_DIR yourself."
      exit 1
    }
  else
    # Cloning to $INSTALL_DIR
    echo "=> Downloading nvm from git to '$INSTALL_DIR'"
    command printf "\r=> "
    mkdir -p "${INSTALL_DIR}"
    if [ "$(ls -A "${INSTALL_DIR}")" ]; then
      command git init "${INSTALL_DIR}" || {
        echo >&2 'Failed to initialize nvm repo. Please report this!'
        exit 2
      }
      command git --git-dir="${INSTALL_DIR}/.git" remote add origin "$(nvm_source)" 2> /dev/null \
        || command git --git-dir="${INSTALL_DIR}/.git" remote set-url origin "$(nvm_source)" || {
        echo >&2 'Failed to add remote "origin" (or set the URL). Please report this!'
        exit 2
      }
      command git --git-dir="${INSTALL_DIR}/.git" fetch origin --tags || {
        echo >&2 'Failed to fetch origin with tags. Please report this!'
        exit 2
      }
    else
      command git clone "$(nvm_source)" "${INSTALL_DIR}" || {
        echo >&2 'Failed to clone nvm repo. Please report this!'
        exit 2
      }
    fi
  fi
  command git --git-dir="$INSTALL_DIR"/.git --work-tree="$INSTALL_DIR" checkout -f --quiet "$(nvm_latest_version)"
  if [ ! -z "$(command git --git-dir="$INSTALL_DIR"/.git --work-tree="$INSTALL_DIR" show-ref refs/heads/master)" ]; then
    if command git --git-dir="$INSTALL_DIR"/.git --work-tree="$INSTALL_DIR" branch --quiet 2>/dev/null; then
      command git --git-dir="$INSTALL_DIR"/.git --work-tree="$INSTALL_DIR" branch --quiet -D master >/dev/null 2>&1
    else
      echo >&2 "Your version of git is out of date. Please update it!"
      command git --git-dir="$INSTALL_DIR"/.git --work-tree="$INSTALL_DIR" branch -D master >/dev/null 2>&1
    fi
  fi
  return
}

#
# Automatically install Node.js
#
nvm_install_node() {
  local NODE_VERSION
  NODE_VERSION="$(nvm_node_version)"

  if [ -z "$NODE_VERSION" ]; then
    return 0
  fi

  echo "=> Installing Node.js version $NODE_VERSION"
  nvm install "$NODE_VERSION"
  local CURRENT_NVM_NODE

  CURRENT_NVM_NODE="$(nvm_version current)"
  if [ "$(nvm_version "$NODE_VERSION")" == "$CURRENT_NVM_NODE" ]; then
    echo "=> Node.js version $NODE_VERSION has been successfully installed"
  else
    echo >&2 "Failed to install Node.js $NODE_VERSION"
  fi
}

install_nvm_as_script() {
  local INSTALL_DIR
  INSTALL_DIR="$(nvm_install_dir)"
  local NVM_SOURCE_LOCAL
  NVM_SOURCE_LOCAL=$(nvm_source script)
  local NVM_EXEC_SOURCE
  NVM_EXEC_SOURCE=$(nvm_source script-nvm-exec)

  # Downloading to $INSTALL_DIR
  mkdir -p "$INSTALL_DIR"
  if [ -f "$INSTALL_DIR/nvm.sh" ]; then
    echo "=> nvm is already installed in $INSTALL_DIR, trying to update the script"
  else
    echo "=> Downloading nvm as script to '$INSTALL_DIR'"
  fi
  nvm_download -s "$NVM_SOURCE_LOCAL" -o "$INSTALL_DIR/nvm.sh" || {
    echo >&2 "Failed to download '$NVM_SOURCE_LOCAL'"
    return 1
  }
  nvm_download -s "$NVM_EXEC_SOURCE" -o "$INSTALL_DIR/nvm-exec" || {
    echo >&2 "Failed to download '$NVM_EXEC_SOURCE'"
    return 2
  }
  chmod a+x "$INSTALL_DIR/nvm-exec" || {
    echo >&2 "Failed to mark '$INSTALL_DIR/nvm-exec' as executable"
    return 3
  }
}

#
# Detect profile file if not specified as environment variable
# (eg: PROFILE=~/.myprofile)
# The echo'ed path is guaranteed to be an existing file
# Otherwise, an empty string is returned
#
nvm_detect_profile() {
  if [ -n "${PROFILE}" ] && [ -f "${PROFILE}" ]; then
    echo "${PROFILE}"
    return
  fi

  local DETECTED_PROFILE
  DETECTED_PROFILE=''
  local SHELLTYPE
  SHELLTYPE="$(basename "/$SHELL")"

  if [ "$SHELLTYPE" = "bash" ]; then
    if [ -f "$/home/ec2-user/.bashrc" ]; then
      DETECTED_PROFILE="$/home/ec2-user/.bashrc"
    elif [ -f "$/home/ec2-user/.bash_profile" ]; then
      DETECTED_PROFILE="$/home/ec2-user/.bash_profile"
    fi
  elif [ "$SHELLTYPE" = "zsh" ]; then
    DETECTED_PROFILE="$/home/ec2-user/.zshrc"
  fi

  if [ -z "$DETECTED_PROFILE" ]; then
    if [ -f "$/home/ec2-user/.profile" ]; then
      DETECTED_PROFILE="$/home/ec2-user/.profile"
    elif [ -f "$/home/ec2-user/.bashrc" ]; then
      DETECTED_PROFILE="$/home/ec2-user/.bashrc"
    elif [ -f "$/home/ec2-user/.bash_profile" ]; then
      DETECTED_PROFILE="$/home/ec2-user/.bash_profile"
    elif [ -f "$/home/ec2-user/.zshrc" ]; then
      DETECTED_PROFILE="$/home/ec2-user/.zshrc"
    fi
  fi

  if [ ! -z "$DETECTED_PROFILE" ]; then
    echo "$DETECTED_PROFILE"
  fi
}

#
# Check whether the user has any globally-installed npm modules in their system
# Node, and warn them if so.
#
nvm_check_global_modules() {
  command -v npm >/dev/null 2>&1 || return 0

  local NPM_VERSION
  NPM_VERSION="$(npm --version)"
  NPM_VERSION="${NPM_VERSION:--1}"
  [ "${NPM_VERSION%%[!-0-9]*}" -gt 0 ] || return 0

  local NPM_GLOBAL_MODULES
  NPM_GLOBAL_MODULES="$(
    npm list -g --depth=0 |
    command sed '/ npm@/d' |
    command sed '/ (empty)$/d'
  )"

  local MODULE_COUNT
  MODULE_COUNT="$(
    command printf %s\\n "$NPM_GLOBAL_MODULES" |
    command sed -ne '1!p' |                     # Remove the first line
    wc -l | tr -d ' '                           # Count entries
  )"

  if [ "${MODULE_COUNT}" != '0' ]; then
    cat <<-'END_MESSAGE'
	=> You currently have modules installed globally with `npm`. These will no
	=> longer be linked to the active version of Node when you install a new node
	=> with `nvm`; and they may (depending on how you construct your `$PATH`)
	=> override the binaries of modules installed with `nvm`:

	END_MESSAGE
    command printf %s\\n "$NPM_GLOBAL_MODULES"
    cat <<-'END_MESSAGE'

	=> If you wish to uninstall them at a later point (or re-install them under your
	=> `nvm` Nodes), you can remove them from the system Node as follows:

	     $ nvm use system
	     $ npm uninstall -g a_module

	END_MESSAGE
  fi
}

nvm_do_install() {
  if [ -z "${METHOD}" ]; then
    # Autodetect install method
    if nvm_has git; then
      install_nvm_from_git
    elif nvm_has nvm_download; then
      install_nvm_as_script
    else
      echo >&2 'You need git, curl, or wget to install nvm'
      exit 1
    fi
  elif [ "${METHOD}" = 'git' ]; then
    if ! nvm_has git; then
      echo >&2 "You need git to install nvm"
      exit 1
    fi
    install_nvm_from_git
  elif [ "${METHOD}" = 'script' ]; then
    if ! nvm_has nvm_download; then
      echo >&2 "You need curl or wget to install nvm"
      exit 1
    fi
    install_nvm_as_script
  fi

  echo

  local NVM_PROFILE
  NVM_PROFILE="$(nvm_detect_profile)"
  local INSTALL_DIR
  INSTALL_DIR="$(nvm_install_dir)"

  SOURCE_STR="\nexport NVM_DIR=\"$INSTALL_DIR\"\n[ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"  # This loads nvm\n"

  if [ -z "${NVM_PROFILE-}" ] ; then
    echo "=> Profile not found. Tried ${NVM_PROFILE} (as defined in \$PROFILE), ~/.bashrc, ~/.bash_profile, ~/.zshrc, and ~/.profile."
    echo "=> Create one of them and run this script again"
    echo "=> Create it (touch ${NVM_PROFILE}) and run this script again"
    echo "   OR"
    echo "=> Append the following lines to the correct file yourself:"
    command printf "${SOURCE_STR}"
  else
    if ! command grep -qc '/nvm.sh' "$NVM_PROFILE"; then
      echo "=> Appending source string to $NVM_PROFILE"
      command printf "$SOURCE_STR" >> "$NVM_PROFILE"
    else
      echo "=> Source string already in ${NVM_PROFILE}"
    fi
  fi

  # Source nvm
  # shellcheck source=/dev/null
  . "${INSTALL_DIR}/nvm.sh"

  nvm_check_global_modules

  nvm_install_node

  nvm_reset

  echo "=> Close and reopen your terminal to start using nvm or run the following to use it now:"
  command printf "$SOURCE_STR"
}

#
# Unsets the various functions defined
# during the execution of the install script
#
nvm_reset() {
  unset -f nvm_reset nvm_has nvm_latest_version \
    nvm_source nvm_download install_nvm_as_script install_nvm_from_git \
    nvm_detect_profile nvm_check_global_modules nvm_do_install \
    nvm_install_dir nvm_node_version nvm_install_node
}

[ "_$NVM_ENV" = "_testing" ] || nvm_do_install

} # this ensures the entire script is downloaded #
