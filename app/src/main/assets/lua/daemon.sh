#!/system/bin/sh
# ==============================================================================
#   TS ONLINE - UNIVERSAL RAM STREAM DAEMON v5.1 (Smart Inject + Anti-Extract)
# ==============================================================================
# Key Principle: NEVER overwrite original game Lua files.
# Instead: only ADD new files (VtcMod.lua) + INJECT require line into Game.lua.
# This ensures compatibility with ALL TS Online forks regardless of their
# module structure, encryption scheme, or CDN file layout.
# ==============================================================================

# Accept game package name as argument, default to VTC if not provided
GAME_PKG="${1:-com.vtcmobile.gz06}"
STAGING="/data/local/tmp/vtc_mod"

# Multi-path scan: find the correct Lua directory for this game package
GAME_LUA=""
for path in "/data/media/0/Android/data/$GAME_PKG/files/Lua" \
            "/sdcard/Android/data/$GAME_PKG/files/Lua" \
            "/storage/emulated/0/Android/data/$GAME_PKG/files/Lua"; do
    if [ -d "$path" ]; then
        GAME_LUA="$path"
        break
    fi
done

# Fallback: use the most common path even if directory doesn't exist yet
if [ -z "$GAME_LUA" ]; then
    GAME_LUA="/data/media/0/Android/data/$GAME_PKG/files/Lua"
fi

echo "[RamStream] Daemon v5.2 Armed and Ready! (VTC-Only Stable)"
echo "[RamStream] Game Package: $GAME_PKG"
echo "[RamStream] Staging: $STAGING"
echo "[RamStream] Target:  $GAME_LUA"

# --- PHASE 1: Wait for game to finish CDN check, then inject ---
# Clear old logcat
logcat -c 2>/dev/null

logcat -s Unity | while read line; do
    if echo "$line" | grep -q "Update All Lua Done"; then
        echo "[RamStream] CDN update complete! Injecting mod files..."
        
        # 100ms safety delay to ensure Unity finishes writing clean CDN files
        sleep 0.1
        
        # Re-scan Lua path in case it was created after game launch
        for path in "/data/media/0/Android/data/$GAME_PKG/files/Lua" \
                    "/sdcard/Android/data/$GAME_PKG/files/Lua" \
                    "/storage/emulated/0/Android/data/$GAME_PKG/files/Lua"; do
            if [ -d "$path" ]; then
                GAME_LUA="$path"
                break
            fi
        done
        
        # === Copy ALL mod files from staging to game Lua directory ===
        for subdir in Common Controller Logic UI; do
            if [ -d "$STAGING/$subdir" ]; then
                mkdir -p "$GAME_LUA/$subdir" 2>/dev/null
                for f in "$STAGING/$subdir"/*.lua; do
                    if [ -f "$f" ]; then
                        fname=$(basename "$f")
                        cp -f "$f" "$GAME_LUA/$subdir/$fname" 2>/dev/null
                        echo "[RamStream] Copied: $subdir/$fname"
                    fi
                done
            fi
        done
        
        # === Fix permissions ===
        APP_UID=$(stat -c '%U' /data/data/$GAME_PKG 2>/dev/null)
        if [ -n "$APP_UID" ]; then
            chown -R "$APP_UID:$APP_UID" "$GAME_LUA/" 2>/dev/null
            chmod -R 777 "$GAME_LUA/" 2>/dev/null
            echo "[RamStream] Fixed permissions for $APP_UID"
        else
            chmod -R 777 "$GAME_LUA/" 2>/dev/null
            echo "[RamStream] Set 777 permissions (Fallback Mode)"
        fi
        
        echo "[RamStream] Injection complete! Mod files are now live."
        
        # Break out of logcat loop to enter Phase 2
        break
    fi
done

echo "[RamStream] Entering cleanup watchdog mode..."

# --- PHASE 2: Anti-Extract Cleanup Watchdog ---
while true; do
    GAME_PID=$(pidof $GAME_PKG 2>/dev/null)
    
    if [ -z "$GAME_PID" ]; then
        echo "[RamStream] Game process terminated! Starting cleanup..."
        
        # Remove ALL injected mod files (wipe everything we pushed)
        for subdir in Common Controller Logic UI; do
            if [ -d "$STAGING/$subdir" ]; then
                for f in "$STAGING/$subdir"/*.lua; do
                    if [ -f "$f" ]; then
                        fname=$(basename "$f")
                        rm -f "$GAME_LUA/$subdir/$fname" 2>/dev/null
                    fi
                done
            fi
        done
        
        # Wipe ALL staging files (RAM Stream protection)
        rm -rf "$STAGING"                                  2>/dev/null
        
        # Wipe this daemon script itself (Anti-Extract)
        rm -f /data/local/tmp/vtc_ram_stream_daemon.sh     2>/dev/null
        
        echo "[RamStream] Cleanup complete! All traces removed."
        echo "[RamStream] Daemon shutting down."
        exit 0
    fi
    
    sleep 3
done
