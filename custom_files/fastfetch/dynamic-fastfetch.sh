#!/bin/bash

# Dynamic fastfetch configuration generator
CONFIG_DIR="$HOME/.config/fastfetch"
TEMP_CONFIG="$CONFIG_DIR/config_temp.jsonc"
FINAL_CONFIG="$CONFIG_DIR/config.jsonc"

# Check if template config exists
if [ ! -f "$TEMP_CONFIG" ]; then
    echo "Error: Template config not found at $TEMP_CONFIG"
    exit 1
fi

# Get number of GPUs
GPU_COUNT=$(fastfetch-gpu -n)

# Read template config
TEMPLATE_CONTENT=$(cat "$TEMP_CONFIG")


# Generate GPU modules with proper JSON syntax
generate_gpu_modules() {
    local count=$1
    local modules=""
    
    for ((i=1; i<=count; i++)); do
        local gpu_info=$(fastfetch-gpu -i $i)
        if [ -n "$gpu_info" ]; then
            if [ -n "$modules" ]; then
                modules="$modules,"
            fi
            modules="$modules
    {
      \"type\": \"command\",
      \"key\": \"GPU $i\",
      \"text\": \"fastfetch-gpu -i $i\"
    }"
        fi
    done
    
    if [ -n "$modules" ]; then
        modules="$modules,"
    fi
    
    echo "$modules"
}

GPU_MODULES_FIXED=$(generate_gpu_modules "$GPU_COUNT")

# Replace __GPU__ placeholder
NEW_CONFIG=$(echo "$TEMPLATE_CONTENT" | python3 -c "
import sys
template = sys.stdin.read()
gpu_modules = '''$GPU_MODULES_FIXED'''
result = template.replace('__GPU__', gpu_modules)
print(result, end='')
")

# Write final config
echo "$NEW_CONFIG" > "$FINAL_CONFIG"

# Run fastfetch with the generated config
fastfetch "$@"