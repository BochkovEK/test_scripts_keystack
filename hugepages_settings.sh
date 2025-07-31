#!/bin/bash

# The script define
# Run on hyper
# Validate input argument
if [ "$#" -ne 1 ] || ! [[ "$1" =~ ^[0-9]+$ ]]; then
    echo "Error: You must specify reserved memory in GB as argument" >&2
    echo "Usage: $0 <reserved_memory_gb>" >&2
    echo "Example: $0 2" >&2
    exit 1
fi

mem_reserved="$1"                # Reserved memory in GB (from argument)
huge_pages_size=$((2048*1024))   # Hugepage size in bytes (2MB)
mem_reserved_bytes=$((mem_reserved*1024*1024*1024))  # Convert GB to bytes

# Get total host memory in bytes
total_memory=$(free -b | awk '/^Mem:/ {print $2}')

# Calculate recommended hugepages
vm_nr_hugepages=$(((total_memory-mem_reserved_bytes)/huge_pages_size))

# Get current hugepages setting
current_hugepages=$(sysctl -n vm.nr_hugepages)

# Display results
#clear
echo "========== HugePages Calculator =========="
echo "Total host memory:    $(numfmt --to=si $total_memory)"
echo "Reserved memory:      ${mem_reserved} GB ($(numfmt --to=si $mem_reserved_bytes))"
echo "Hugepage size:        2MB ($huge_pages_size bytes)"
echo "------------------------------------------"
echo "Current setting:      vm.nr_hugepages = $current_hugepages"
echo "Recommended setting:  vm.nr_hugepages = $vm_nr_hugepages"
echo ""
echo "For OpenStack Nova, set in nova.conf:"
echo "nova_compute_hugepages_numbers = $vm_nr_hugepages"
echo "=========================================="

# Safety check
if (( vm_nr_hugepages <= 0 )); then
    echo ""
    echo "WARNING: Calculated value is zero or negative!" >&2
    echo "Check your reserved memory value." >&2
    exit 2
fi