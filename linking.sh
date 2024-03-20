#!/bin/bash

dotfiles_dir="~/dotfiles"
home_dir="~/"

# Loop through all dotfiles in the directory
for dotfile in $dotfiles_dir/.*; do
    # Exclude . and ..
    if [[ $dotfile != "$dotfiles_dir/." && $dotfile != "$dotfiles_dir/.." ]]; then
        # Get the filename without the directory path
        filename=$(basename "$dotfile")
        
        # Create the symbolic link in the home directory
        ln -s "$dotfile" "$home_dir/$filename"
        
        echo "Created symbolic link for $filename"
    fi
done