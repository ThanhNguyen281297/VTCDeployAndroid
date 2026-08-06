package com.vtcdeploy.domain

import com.vtcdeploy.data.DeviceManager
import com.vtcdeploy.data.LuaScriptProvider
import com.vtcdeploy.data.ShellExecutor
import com.vtcdeploy.data.ConfigManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

class PatchUseCase(
    private val shell: ShellExecutor,
    private val deviceManager: DeviceManager,
    private val luaProvider: LuaScriptProvider,
    private val config: ConfigManager
) {

    data class PatchConfig(
        val devices: List<DeviceManager.Device>,
        val partySlots: List<String>,
        val catHp: Int,
        val catSp: Int,
        val dungeonCount: Int,
        val fleeNoParty: Boolean,
        val gamePackage: String
    )

    data class PatchResult(
        val success: Boolean,
        val message: String,
        val deviceSerial: String? = null
    )

    interface PatchCallback {
        fun onLog(message: String)
        fun onProgress(device: String, current: Int, total: Int)
        fun onComplete(results: List<PatchResult>)
    }

    suspend fun executePatch(patchConfig: PatchConfig, callback: PatchCallback): List<PatchResult> = withContext(Dispatchers.IO) {
        val results = mutableListOf<PatchResult>()
        val adbPath = config.getAdbPath() ?: return@withContext listOf(PatchResult(false, "ADB path not configured"))
        val tempDir = File(config.getAdbPath()?.let { File(it).parent } ?: File("/data/local/tmp"), "VtcTemp")
        tempDir.mkdirs()

        try {
            // Load all scripts
            val scriptsResult = luaProvider.getAllScripts().getOrThrow()
            val daemonScript = luaProvider.getDaemonScript().getOrThrow()

            for ((index, device) in patchConfig.devices.withIndex()) {
                callback.onProgress(device.displayName, index + 1, patchConfig.devices.size)
                callback.onLog("[*] Processing ${device.displayName}...")

                val deviceResult = patchSingleDevice(
                    adbPath = adbPath,
                    device = device,
                    scripts = scriptsResult,
                    daemonScript = daemonScript,
                    config = patchConfig,
                    tempDir = tempDir,
                    callback = callback
                )
                results.add(deviceResult)

                if (!deviceResult.success) {
                    callback.onLog("[ERROR] Failed on ${device.displayName}: ${deviceResult.message}")
                    break
                }

                // Delay between devices
                if (index < patchConfig.devices.size - 1) {
                    callback.onLog("[PACKING] Waiting 20 seconds before next device...")
                    Thread.sleep(20000)
                }
            }

            callback.onComplete(results)
            results
        } catch (e: Exception) {
            val errorResults = listOf(PatchResult(false, "Patch failed: ${e.message}"))
            callback.onComplete(errorResults)
            errorResults
        } finally {
            // Cleanup temp files
            tempDir.listFiles()?.forEach { it.delete() }
        }
    }

    private suspend fun patchSingleDevice(
        adbPath: String,
        device: DeviceManager.Device,
        scripts: Map<String, String>,
        daemonScript: String,
        config: PatchConfig,
        tempDir: File,
        callback: PatchCallback
    ): PatchResult {
        val serial = device.serial

        try {
            // Determine game package
            var gamePkg = config.gamePackage
            if (gamePkg == "[Auto-Detect Running Game]") {
                callback.onLog("[*] Auto-detecting running game...")
                val dumpsys = shell.execute("$adbPath -s $serial shell \"dumpsys activity activities | grep ResumedActivity\"", 60000).getOrThrow()
                val regex = "u\\d+\\s+([a-zA-Z0-9\\._]+)/".toRegex()
                val match = regex.find(dumpsys)
                if (match == null) {
                    return PatchResult(false, "Could not detect running game", serial)
                }
                gamePkg = match.groupValues[1]
                callback.onLog("[OK] Auto-Detected: $gamePkg")
            }

            // Get device MAC for token
            var mac = shell.execute("$adbPath -s $serial shell cat /sys/class/net/wlan0/address", 60000).getOrThrow().trim()
            if (mac.contains("No such file") || mac.contains("error") || mac.isBlank()) {
                mac = "00:00:00:00:00:00"
            }
            mac = mac.lines().first().trim()

            // Generate device token (DJB2 hash)
            val tokenInput = mac + "VTC_SALT_KEY_2024"
            val deviceToken = "DEVLOCK-${djb2Hash(tokenInput).toString(16).uppercase().padStart(8, '0')}"

            // Create directories on device
            shell.execute("$adbPath -s $serial shell su 0 mkdir -p /data/local/tmp/vtc_mod/Common /data/local/tmp/vtc_mod/Controller /data/local/tmp/vtc_mod/Logic /data/local/tmp/vtc_mod/UI", 60000).getOrThrow()

            // Process each script
            scripts.forEach { (scriptName, scriptContent) ->
                var processedContent = scriptContent

                if (scriptName == "Logic/VtcMod.lua") {
                    processedContent = processedContent
                        .replace("__VTC_DEVICE_TOKEN__", deviceToken)
                        .replace("__AUTO_FLEE_NO_PARTY__", config.fleeNoParty.toString().lowercase())
                        .replace("__CATBINH_HP_TRIGGER__", (config.catHp / 100.0).toString().replace(",", "."))
                        .replace("__CATBINH_SP_TRIGGER__", (config.catSp / 100.0).toString().replace(",", "."))
                    config.partySlots.forEachIndexed { i, name ->
                        processedContent = processedContent.replace("__PARTY_SLOT_${i + 1}__", name)
                    }
                } else if (scriptName == "UI/UIDebug.lua") {
                    processedContent = processedContent
                        .replace("__AUTO_BUY_DUNGEON__", config.dungeonCount.toString())
                        .replace("__LANGUAGE__", if (config.isEnglish) "EN" else "VN")
                }

                // Encrypt and push (using simple AES - in production use proper key derivation)
                val encrypted = encryptScript(processedContent)
                val tempFile = File(tempDir, "${scriptName.replace("/", "_")}.dat")
                tempFile.writeBytes(encrypted)

                val pushResult = shell.execute("$adbPath -s $serial push \"${tempFile.absolutePath}\" \"/data/local/tmp/vtc_mod/$scriptName\"", 60000)
                if (!pushResult.isSuccess || pushResult.getOrNull()?.lowercase()?.contains("error") == true) {
                    throw RuntimeException("Failed to push $scriptName: ${pushResult.exceptionOrNull()?.message ?? pushResult.getOrNull()}")
                }
                tempFile.delete()
            }

            // Push and run daemon
            val daemonFile = File(tempDir, "daemon.sh")
            daemonFile.writeText(daemonScript
                .replace("\r\n", "\n")
                .replace("\r", "")
            )
            shell.execute("$adbPath -s $serial push \"${daemonFile.absolutePath}\" /data/local/tmp/vtc_ram_stream_daemon.sh", 60000).getOrThrow()
            daemonFile.delete()

            shell.execute("$adbPath -s $serial shell su 0 chmod +x /data/local/tmp/vtc_ram_stream_daemon.sh", 5000).getOrThrow()
            shell.execute("$adbPath -s $serial shell su 0 pkill -f vtc_ram_stream", 5000)
            shell.execute("$adbPath -s $serial shell \"su 0 kill -9 \\$(ps | grep vtc_ram_stream | awk '{print \\$2}')\"", 5000)

            // Start daemon in background
            shell.executeNoWait("$adbPath -s $serial shell su 0 sh /data/local/tmp/vtc_ram_stream_daemon.sh $gamePkg")

            Thread.sleep(500)

            // Restart game
            callback.onLog("[*] Restarting game...")
            shell.execute("$adbPath -s $serial shell am force-stop $gamePkg", 60000).getOrThrow()
            Thread.sleep(500)
            shell.execute("$adbPath -s $serial shell monkey -p $gamePkg -c android.intent.category.LAUNCHER 1", 60000).getOrThrow()

            return PatchResult(true, "Success", serial)
        } catch (e: Exception) {
            return PatchResult(false, e.message ?: "Unknown error", serial)
        }
    }

    private fun djb2Hash(input: String): Int {
        var hash = 5381
        for (c in input.toCharArray()) {
            hash = ((hash shl 5) + hash) + c.toInt() // hash * 33 + c
        }
        return hash and 0xFFFFFFFF
    }

    private fun encryptScript(content: String): ByteArray {
        // Simple encryption placeholder - in production use proper AES
        return content.toByteArray()
    }
}