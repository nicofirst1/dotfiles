#!/bin/bash

dotfiles_dir="."
verbose=true

# Check if the current directory is inside the dotfiles directory
if [[ $PWD != *"dotfiles"* ]]; then
    echo "Current directory is not inside the dotfiles directory."
    exit 1
fi

# Loop through all dotfiles in the directory
for dotfile in $dotfiles_dir/.[!.]*; do
    # Exclude . and ..
    if [[ $dotfile != "$dotfiles_dir/." && $dotfile != "$dotfiles_dir/.." ]]; then
        # Get the filename without the directory path
        filename=$(basename "$dotfile")

        # Print the filename if verbose is true
        if [ "$verbose" = true ]; then
            echo "Processing file: $filename"
        fi

        # Check if the file already exists in the home directory
        if [ ! -f "$(eval echo $HOME)/$filename" ]; then
            # Check if the file is a symbolic link
            if [ -L "$dotfile" ]; then
                if [ "$verbose" = true ]; then
                    echo "Skipping symbolic link: $filename"
                fi
            else
                # Create the symbolic link in the home directory
                ln -s "$dotfile" "$(eval echo $HOME)/$filename"
                if [ "$verbose" = true ]; then
                    echo "Created symbolic link for $filename in $HOME"
                fi
            fi
        else
            # Ask user if they want to override the existing file with a symbolic link
            read -p "File $filename already exists. Do you want to override it with a symbolic link? (y/n): " answer
            if [ "$answer" = "y" ]; then
                # Remove the existing file
                rm "$(eval echo $HOME)/$filename"
                # Create the symbolic link
                ln -s "$dotfile" "$(eval echo $HOME)/$filename"
                if [ "$verbose" = true ]; then
                    echo "Overwrote file $filename with a symbolic link"
                fi
            else
                if [ "$verbose" = true ]; then
                    echo "Skipped creating symbolic link for $filename"
                fi
            fi
        fi
    fi
done
