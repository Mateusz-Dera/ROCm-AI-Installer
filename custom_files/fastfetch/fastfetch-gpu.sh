#!/bin/bash

# Default values
target_index=-1
show_count=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --index|-i)
            target_index="$2"
            shift 2
            ;;
        --number|-n)
            show_count=true
            shift
            ;;
        *)
            printf "Unknown option: %s\n" "$1"
            printf "Usage: %s [--index|-i <number>] [--number|-n]\n" "$0"
            exit 1
            ;;
    esac
done

gpu_count=1

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

                # Check if we should display this GPU based on target_index
                if [[ "$show_count" == false ]] && ([[ "$target_index" == -1 ]] || [[ "$target_index" == "$gpu_count" ]]); then
                    echo "${name} ${total} MiB"
                fi
                gpu_count=$((gpu_count + 1))
            done < <(nvidia-smi --query-gpu=name,memory.total,memory.used,memory.free --format=csv,noheader,nounits -i "$bus_id" 2>/dev/null)
        # Check for AMD GPU
        elif command -v rocm-smi &> /dev/null && echo "$line" | grep -qi amd; then
            # Calculate AMD GPU index based on current gpu_count (0-indexed for rocm-smi)
            amd_gpu_index=$((gpu_count - 1))
            # Get AMD GPU info for specific GPU index
            amd_name=$(rocm-smi --showproductname --csv 2>/dev/null | tail -n +2 | sed -n "$((amd_gpu_index + 1))p" | cut -d',' -f2)
            amd_vram=$(rocm-smi --showmeminfo vram --csv 2>/dev/null | tail -n +2 | sed -n "$((amd_gpu_index + 1))p" | cut -d',' -f2,3,4)
            if [ -n "$amd_name" ] && [ -n "$amd_vram" ]; then
                while IFS=',' read -r name total used free; do
                    # Trim whitespace from values
                    name=$(echo "$name" | xargs)
                    used=$(echo "$used" | xargs)
                    total=$(echo "$total" | xargs)
                    
                    # Convert bytes to MiB (1 MiB = 1048576 bytes)
                    if [[ "$used" =~ ^[0-9]+$ ]] && [[ "$total" =~ ^[0-9]+$ ]]; then
                        used_mib=$((used / 1048576))
                        total_mib=$((total / 1048576))
                        # Check if we should display this GPU based on target_index
                        if [[ "$show_count" == false ]] && ([[ "$target_index" == -1 ]] || [[ "$target_index" == "$gpu_count" ]]); then
                            echo "${name} ${total_mib} MiB"
                        fi
                    else
                        # Check if we should display this GPU based on target_index
                        if [[ "$show_count" == false ]] && ([[ "$target_index" == -1 ]] || [[ "$target_index" == "$gpu_count" ]]); then
                            echo "${name}"
                        fi
                    fi
                    
                    gpu_count=$((gpu_count + 1))
                done < <(echo "$amd_name,$amd_vram")
            fi
        # All other GPUs (use lspci name, no VRAM info)
        else
            gpu_name=$(echo "$line" | sed 's/^[0-9a-f:.]* VGA compatible controller: //')
            # Clean up name by cutting off everything after [ or (
            gpu_name=$(echo "$gpu_name" | sed 's/\[[^]]*\].*$//' | sed 's/(.*$//' | xargs)
            
            # Check if we should display this GPU based on target_index
            if [[ "$show_count" == false ]] && ([[ "$target_index" == -1 ]] || [[ "$target_index" == "$gpu_count" ]]); then
                echo "${gpu_name}"
            fi
            
            gpu_count=$((gpu_count + 1))
        fi
    done < <(lspci | grep -i vga | sort)
fi

# If show_count is true, display the count instead
if [[ "$show_count" == true ]]; then
    echo $((gpu_count - 1))
fi

