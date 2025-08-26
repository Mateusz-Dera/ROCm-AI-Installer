#!/bin/bash

# Create JSON output for GPU information
echo "{"

gpu_count=0
first_entry=true

if command -v lspci &> /dev/null; then
    # Get graphics cards info for ordering
    lspci | grep -i vga | sort | while read -r line; do
        # Extract bus ID for GPU identification
        bus_id=$(echo "$line" | cut -d' ' -f1)
        
        # Check for NVIDIA GPU
        if command -v nvidia-smi &> /dev/null && echo "$line" | grep -qi nvidia; then
            nvidia-smi --query-gpu=name,memory.total,memory.used,memory.free --format=csv,noheader,nounits -i "$bus_id" 2>/dev/null | while IFS=',' read -r name total used free; do
                if [ "$first_entry" = false ]; then
                    echo ","
                fi
                echo "  \"GPU $gpu_count\": \"$name ${used}MB/${total}MB\""
                first_entry=false
                gpu_count=$((gpu_count + 1))
            done
        # Check for AMD GPU
        elif command -v rocm-smi &> /dev/null && echo "$line" | grep -qi amd; then
            # Get AMD GPU info (matching by bus ID is complex, so we'll use index)
            amd_name=$(rocm-smi --showproductname --csv 2>/dev/null | tail -n +2 | head -n 1 | cut -d',' -f2)
            amd_vram=$(rocm-smi --showmeminfo vram --csv 2>/dev/null | tail -n +2 | head -n 1 | cut -d',' -f2,3,4)
            if [ -n "$amd_name" ] && [ -n "$amd_vram" ]; then
                echo "$amd_name,$amd_vram" | while IFS=',' read -r name total used free; do
                    if [ "$first_entry" = false ]; then
                        echo ","
                    fi
                    echo "  \"GPU $gpu_count\": \"$name ${used}MB/${total} MB\""
                    first_entry=false
                    gpu_count=$((gpu_count + 1))
                done
            fi
        # Intel GPU (use lspci name, no VRAM info)
        elif echo "$line" | grep -qi intel; then
            gpu_name=$(echo "$line" | sed 's/^[0-9a-f:.]* VGA compatible controller: //')
            if [ "$first_entry" = false ]; then
                echo ","
            fi
            echo "  \"GPU $gpu_count\": \"$gpu_name (integrated)\""
            first_entry=false
            gpu_count=$((gpu_count + 1))
        fi
    done
fi

echo ""
echo "}"