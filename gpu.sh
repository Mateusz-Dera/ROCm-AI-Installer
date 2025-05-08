#!/bin/bash

# Function to count AMD GPUs
count_amd_gpus() {
    lspci | grep -i "VGA" | grep -i "AMD" | wc -l
}

# Function to count NVIDIA GPUs
count_nvidia_gpus() {
    if command -v nvidia-smi &> /dev/null; then
        nvidia-smi --query-gpu=count --format=csv,noheader
    else
        echo 0
    fi
}

# Check for required tools
has_rocm_smi=false
has_nvidia_smi=false

if command -v rocm-smi &> /dev/null; then
    has_rocm_smi=true
fi

if command -v nvidia-smi &> /dev/null; then
    has_nvidia_smi=true
fi

# Count GPUs
amd_count=$(count_amd_gpus)
nvidia_count=$(count_nvidia_gpus)

# echo "Found $amd_count AMD GPU(s) and $nvidia_count NVIDIA GPU(s)"

# Check if any GPUs are found
if [ "$amd_count" -le 0 ] && [ "$nvidia_count" -le 0 ]; then
    exit 0
fi

# Process AMD GPUs if found
if [ "$amd_count" -gt 0 ]; then
    if $has_rocm_smi; then
        # echo "=== AMD GPU Memory Usage ==="
        # Loop through each AMD GPU index
        for ((gpu=0; gpu<amd_count; gpu++)); do
            used_mem_bytes=$(rocm-smi --showmeminfo vram -d $gpu | grep 'Used Memory' | awk '{print $NF}')
            total_mem_bytes=$(rocm-smi --showmeminfo vram -d $gpu | grep 'Total Memory' | awk '{print $NF}')
            used_mem_mb=$(echo "$used_mem_bytes / 1048576" | bc)
            total_mem_mb=$(echo "$total_mem_bytes / 1048576" | bc)
            echo "AMD GPU $gpu VRAM: $used_mem_mb/$total_mem_mb MB"
        done
    else
        echo "rocm-smi not found. Skipping AMD GPU memory info."
    fi
fi

# Process NVIDIA GPUs if found
if [ "$nvidia_count" -gt 0 ]; then
    if $has_nvidia_smi; then
        # echo "=== NVIDIA GPU Memory Usage ==="
        # Get memory usage for all NVIDIA GPUs
        nvidia-smi --query-gpu=index,memory.used,memory.total --format=csv,noheader,nounits | while read -r line; do
            index=$(echo "$line" | awk -F ', ' '{print $1}')
            used=$(echo "$line" | awk -F ', ' '{print $2}')
            total=$(echo "$line" | awk -F ', ' '{print $3}')
            echo "NVIDIA GPU $index VRAM: $used/$total MB"
        done
    else
        echo "nvidia-smi not found. Skipping NVIDIA GPU memory info."
    fi
fi