# Kernel Panic Fix

## Problem
The VM was experiencing a kernel panic with "invalid opcode" errors. This was caused by:
- Incompatible CPU emulation model for SL-Micro
- Wrong machine type configuration
- Running x86_64 image on Apple M1 (ARM) requires proper emulation

## Solution Applied

Created `start-vm-fixed.sh` with:
1. **Raw image support**: Uses the original `.raw` image directly (more compatible than qcow2)
2. **Compatible CPU model**: Uses `Haswell-v4` CPU with proper x86_64 features
3. **Standard machine type**: Uses `pc-q35-7.2` (well-tested, compatible)
4. **Proper CPU features**: Added `+ssse3,+sse4.1,+sse4.2,+x2apic` for compatibility
5. **TCG emulation**: Multi-threaded TCG for x86_64 emulation on ARM

## Usage

Run the fixed version:
```bash
./scripts/start-vm-fixed.sh
```

## What Changed

**Before:**
- Machine: `q35` (generic)
- CPU: `qemu64` (too generic, caused invalid opcodes)
- Image: qcow2 only

**After:**
- Machine: `pc-q35-7.2` (specific, compatible version)
- CPU: `Haswell-v4` with explicit x86_64 features
- Image: Prefers raw, falls back to qcow2

## If Still Having Issues

1. **Check the QEMU window** - Does it show boot messages or still panic?
2. **Try different CPU models**:
   - `Westmere` (older, more compatible)
   - `SandyBridge` (mid-range)
   - `Haswell` (current - should work)
3. **Verify image integrity**: The raw image should be 3.3GB uncompressed

## Alternative: Use UTM

If QEMU continues to have issues, consider using UTM (macOS virtualization app):
- Download from: https://mac.getutm.app/
- More user-friendly GUI
- Better M1 compatibility
- Can import the raw image directly


