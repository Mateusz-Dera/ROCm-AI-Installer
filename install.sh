#!/bin/bash
sudo apt-get update
sudo apt-get upgrade -y
sudo apt-get install -y git whiptail

# Default installation path
default_installation_path="$HOME/AI"
# Global variable for installation path
installation_path="$default_installation_path"

# Function to display the main menu
show_menu() {
    whiptail --title "Menu Example" --menu "Choose an option:" 15 100 4 \
    0 "Set Installation Path ($installation_path)" \
    1 "text-generation-webui" \
    2 "text-generation-webui" \
    3 "SillyTavern" \
    2>&1 > /dev/tty
}

# Function to display the SillyTavern submenu
show_sillytavern_submenu() {
    whiptail --title "SillyTavern Submenu" --menu "Choose an option for SillyTavern:" 15 150 2 \
    1 "SillyTavern" \
    2 "SillyTavern + Extras + chromadb + XTTS-v2" \
    2>&1 > /dev/tty
}

# Function to set the installation path
set_installation_path() {
    # Prompt for installation path, using the default if the user leaves it blank
    new_installation_path=$(whiptail --inputbox "Enter the installation path (default: $default_installation_path):" 10 150 "$installation_path" 3>&1 1>&2 2>&3)

    # If the user leaves it blank, use the default
    new_installation_path=${new_installation_path:-$default_installation_path}

    # Remove trailing "/" if it exists
    new_installation_path=$(echo "$new_installation_path" | sed 's#/$##')

    # Update the installation path variable
    installation_path="$new_installation_path"
}

# Main loop
while true; do
    choice=$(show_menu)

    case $choice in
        0)
            # Set Installation Path
            set_installation_path
            ;;
        1)
            # Action for Option 1
            whiptail --msgbox "You selected text-generation-webui" 10 120
            ;;
        2)
            # Action for Option 2
            whiptail --msgbox "You selected text-generation-webui" 10 120
            ;;
        3)
            # Submenu for SillyTavern
            submenu_choice=$(show_sillytavern_submenu)
            
            case $submenu_choice in
                1)
                    # Action for SillyTavern
                    whiptail --msgbox "You selected SillyTavern" 10 120
                    ;;
                2)
                    # Action for SillyTavern + Extras + chromadb + XTTS-v2
                    whiptail --msgbox "You selected SillyTavern + Extras + chromadb + XTTS-v2" 10 120
                    ;;
                *)
                    # Cancel
                    ;;
            esac
            ;;
        *)
            # Cancel or Exit
            whiptail --yesno "Do you really want to exit?" 10 30
            if [ $? -eq 0 ]; then
                exit 0
            fi
            ;;
    esac
done