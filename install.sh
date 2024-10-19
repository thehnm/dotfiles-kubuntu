#!/usr/bin/env bash

UBUNTU_DEPENDENCIES=(
    rofi
    fzf
    zsh
    git
    curl
    wget
    pass
    pass-extension-otp
    yakuake
    unzip
    nextcloud-desktop
    ssh
    eza
)

SNAP_DEPENDENCIES=(
    brave
    spotify
)

DOTFILES_REPOSITORIES=(
    "git@github.com:thehnm/dotfiles.git|https://github.com/thehnm/dotfiles|persistent"
    "git@github.com:thehnm/dotfiles-kubuntu.git|https://github.com/thehnm/dotfiles-kubuntu|delete"
)
GIT_REPOSITORIES=(
    "git@github.com:thehnm/nvim.git|https://github.com/thehnm/nvim|$HOME/.config/nvim"
    "git@github.com:thehnm/tmux.git|https://github.com/thehnm/tmux|$HOME/.config/tmux"
)
XORG_KEYBOARD_CONFIG_FILE=/etc/X11/xorg.conf.d/00-keyboard.conf

FONTS_URL=https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/CascadiaMono.zip
FONTS_DIR=$HOME/.local/share/fonts

ask_yes_no() {
    local prompt="$1"
    local default="$2"
    local response

    if [ "$default" == "y" ]; then
        prompt="$prompt [Y/n]"
    elif [ "$default" == "n" ]; then
        prompt="$prompt [y/N]"
    else
        echo "Invalid default value: $default"
        return 1
    fi

    while true; do
        read -rp "$prompt: " response
        if [ -z "$response" ]; then
            response="$default"
        fi

        case "$response" in
            [yY]) return 0 ;;
            [nN]) return 1 ;;
            *) echo "Please answer with 'y' or 'n'." ;;
        esac
    done
}

install_bare_git_repository() {
    LOCAL_REPO_PATH="$HOME"/."$2"
    BACKUP_DIR_PATH="$HOME"/."$2".backup

    if [ -d "$BACKUP_DIR_PATH" ]; then
        mv "$BACKUP_DIR_PATH" "$BACKUP_DIR_PATH"."$(date +'%y%m%d%H%M%S')"
    fi

    echo "Cloning $2 ..."
    if git clone --bare "$1" "$LOCAL_REPO_PATH"; then
        git_alias() {
            git --git-dir="$LOCAL_REPO_PATH" --work-tree="$HOME" "$@"
        }
        if ! git_alias checkout; then
            echo "Moving existing dotfiles to $BACKUP_DIR_PATH"
            mkdir -p "$BACKUP_DIR_PATH"
            git_alias checkout 2>&1 | grep -E "\s+\." | awk \{'print $1'\} | xargs -I{} mv {} "$BACKUP_DIR_PATH"
            git_alias checkout --force
        fi
        git_alias config status.showUntrackedFiles no

        if [[ $3 == "delete" ]]; then
            rm -rf "$LOCAL_REPO_PATH"
        fi

        return 0
    fi
    return 1
}

install_lazygit() {
    LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
    curl -Lo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz"
    tar xf lazygit.tar.gz lazygit
    rm lazygit.tar.gz lazygit
    install lazygit "$HOME"/.local/bin
}

install_neovim() {
    curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux64.tar.gz
    sudo rm -rf /opt/nvim
    sudo tar -C /opt -xzf nvim-linux64.tar.gz
}

install_fonts() {
    mkdir -p "$FONTS_DIR"
    wget $FONTS_URL
    local fonts_zip_file
    fonts_zip_file=$(basename $FONTS_URL)
    unzip "$fonts_zip_file" -d "$FONTS_DIR"
    rm "$fonts_zip_file"
    fc-cache -rf &> /dev/null
}

if ! command -v curl &> /dev/null; then
    echo "# curl is not installed. Installing curl..."
    sudo apt-get update
    sudo apt-get install -y curl
fi

echo "Installing dependencies: ${UBUNTU_DEPENDENCIES[*]}"
sudo apt-get install -y "${UBUNTU_DEPENDENCIES[@]}"

echo "Installing snap dependencies: ${SNAP_DEPENDENCIES[*]}"
sudo snap install "${SNAP_DEPENDENCIES[@]}"

echo "Install Antibody ZSH Plugin manager"
mkdir -p "$HOME"/.local/bin
curl -sfL git.io/antibody | sh -s - -b "$HOME"/.local/bin/

echo "Install neovim"
install_neovim

echo "Install lazygit"
install_lazygit

echo "Install new fonts"
install_fonts

for dotfile_repo in "${DOTFILES_REPOSITORIES[@]}"; do
    IFS='|' read -r ssh_url http_url delete_repo <<< "$dotfile_repo"
    repo_name=$(basename "$ssh_url" .git)

    if ! install_bare_git_repository "$ssh_url" "$repo_name" "$delete_repo"; then
        if ! install_bare_git_repository "$http_url" "$repo_name" "$delete_repo"; then
            echo "ERROR: Failed to clone $http_url. Exiting"
            return 1
        fi
    fi
done

for git_repo in "${GIT_REPOSITORIES[@]}"; do
    IFS='|' read -r ssh_url http_url target_location <<< "$git_repo"
    repo_name=$(basename "$ssh_url" .git)
    if [ -d "$target_location" ]; then
        mv "$target_location" "$target_location".backup."$(date +'%y%m%d%H%M%S')"
    fi

    echo "Cloning $repo_name ..."
    if ! git clone "$ssh_url" "$target_location"; then
        if ! git clone "$http_url" "$target_location"; then
            echo "ERROR: Failed to clone $http_url. Exiting"
            return 1
        fi
    fi
done

if [ ! -f $XORG_KEYBOARD_CONFIG_FILE ]; then
    NEW_FILE_CONTENT=$(cat <<EOF
Section "InputClass"
        Identifier "system-keyboard"
        MatchIsKeyboard "on"
        Option "XkbLayout" "de"
        Option "XkbVariant" "nodeadkeys"
        Option "XkbOptions" "ctrl:nocaps"
EndSection
EOF
    )
    echo "$NEW_FILE_CONTENT" > sudo tee "$XORG_KEYBOARD_CONFIG_FILE"
else
    OPTION_LINE='Option "XkbOptions" "ctrl:nocaps"'
    TEMP_FILE=$(mktemp)
    in_input_class_section=false
    option_added=false

    while IFS= read -r line; do
        if [[ $line =~ ^Section\ \"InputClass\" ]]; then
            in_input_class_section=true
        fi
        if [[ $line =~ ^EndSection ]]; then
            if $in_input_class_section && ! $option_added; then
                echo "        $OPTION_LINE" >> "$TEMP_FILE"
                option_added=true
            fi
            in_input_class_section=false
        fi
        echo "$line" >> "$TEMP_FILE"
    done < "$XORG_KEYBOARD_CONFIG_FILE"
    mv "$TEMP_FILE" "$XORG_KEYBOARD_CONFIG_FILE"
fi

echo "Creating directory for ZSH"
mkdir -p "$HOME"/.local/share/zsh
touch "$HOME"/.local/share/zsh/history

if ask_yes_no "Do you want to reboot the system now?" "n"; then
    sudo reboot
fi
