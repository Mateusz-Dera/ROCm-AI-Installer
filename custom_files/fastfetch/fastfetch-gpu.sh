#!/bin/bash

# Default values
bold_enabled=false
polish=false
color_name="white"
separator_color_name="white"
separator=": "

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --bold)
            bold_enabled=true
            shift
            ;;
        --polish)
            polish=true
            shift
            ;;
        --key-color)
            color_name="$2"
            shift 2
            ;;
        --separator)
            separator="$2"
            shift 2
            ;;
        --separator-color)
            separator_color_name="$2"
            shift 2
            ;;
        *)
            printf "Unknown option: %s\n" "$1"
            printf "Usage: %s [--bold] [--polish] [--key-color <color_name>] [--separator <separator>] [--separator-color <color_name>]\n" "$0"
            printf "Available colors: black, red, green, yellow, blue, magenta, cyan, white,\n"
            exit 1
            ;;
    esac
done

gpu_count=1
first_gpu=true

# Function to map color names to ANSI codes (16 standard colors)
get_color_code() {
    local color_name="$1"
    case "$color_name" in
        black)         echo "30" ;;
        red)           echo "31" ;;
        green)         echo "32" ;;
        yellow)        echo "33" ;;
        blue)          echo "34" ;;
        magenta)       echo "35" ;;
        cyan)          echo "36" ;;
        white)         echo "37" ;;
        *)
            printf "Error: Unknown color '%s'\n" "$color_name"
            printf "Available colors: black, red, green, yellow, blue, magenta, cyan, white\n"
            exit 1
            ;;
    esac
}

# Map color names to ANSI codes
color_code=$(get_color_code "$color_name")
separator_color_code=$(get_color_code "$separator_color_name")

# Set color codes based on bold option
if [[ "$bold_enabled" == true ]]; then
    color_start="\e[1;${color_code}m"
    separator_color_start="\e[1;${separator_color_code}m"
else
    color_start="\e[${color_code}m"
    separator_color_start="\e[${separator_color_code}m"
fi
color_end="\e[0m"

# Set GPU label based on polish flag
if [[ "$polish" == true ]]; then
    gpu_label="KARTA"
else
    gpu_label="GPU"
fi

if command -v lspci &> /dev/null; then
    # Get graphics cards info for ordering
    while read -r line; do
        # Extract bus ID for GPU identification
        bus_id=$(echo "$line" | cut -d' ' -f1)
        
        # Check for NVIDIA GPU
        if command -v nvidia-smi &> /dev/null && echo "$line" | grep -qi nvidia; then
            while IFS=',' read -r name total used free; do
                # Trim whitespace from values
                name=$(echo "$name" | xargs)
                used=$(echo "$used" | xargs)
                total=$(echo "$total" | xargs)

                echo -e "${color_start}${gpu_label} ${gpu_count}${color_end}${separator_color_start}${separator}${color_end}${name} ${used} MiB / ${total} MiB"
                first_gpu=false
                gpu_count=$((gpu_count + 1))
            done < <(nvidia-smi --query-gpu=name,memory.total,memory.used,memory.free --format=csv,noheader,nounits -i "$bus_id" 2>/dev/null)
        # Check for AMD GPU
        elif command -v rocm-smi &> /dev/null && echo "$line" | grep -qi amd; then
            # Get AMD GPU info (matching by bus ID is complex, so we'll use index)
            amd_name=$(rocm-smi --showproductname --csv 2>/dev/null | tail -n +2 | head -n 1 | cut -d',' -f2)
            amd_vram=$(rocm-smi --showmeminfo vram --csv 2>/dev/null | tail -n +2 | head -n 1 | cut -d',' -f2,3,4)
            if [ -n "$amd_name" ] && [ -n "$amd_vram" ]; then
                while IFS=',' read -r name total used free; do
                    # Trim whitespace from values
                    name=$(echo "$name" | xargs)
                    used=$(echo "$used" | xargs)
                    total=$(echo "$total" | xargs)

                    echo -e "${color_start}${gpu_label} ${gpu_count}${color_end}${separator_color_start}${separator}${color_end}${name} ${used} MiB / ${total} MiB"
                    first_gpu=false
                    gpu_count=$((gpu_count + 1))
                done < <(echo "$amd_name,$amd_vram")
            fi
        # All other GPUs (use lspci name, no VRAM info)
        else
            gpu_name=$(echo "$line" | sed 's/^[0-9a-f:.]* VGA compatible controller: //')
            # Clean up name by cutting off everything after [ or (
            gpu_name=$(echo "$gpu_name" | sed 's/\[[^]]*\].*$//' | sed 's/(.*$//' | xargs)
            
            echo -e "${color_start}${gpu_label} ${gpu_count}${color_end}${separator_color_start}${separator}${color_end}${gpu_name}"
            
            first_gpu=false
            gpu_count=$((gpu_count + 1))
        fi
    done < <(lspci | grep -i vga | sort)
fi

