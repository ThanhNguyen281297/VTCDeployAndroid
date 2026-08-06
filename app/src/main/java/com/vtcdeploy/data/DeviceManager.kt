package com.vtcdeploy.data

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

class DeviceManager(
    private val context: Context,
    private val shell: ShellExecutor,
    private val config: ConfigManager
) {

    data class Device(
        val serial: String,
        val displayName: String,
        val isSelected: Boolean = true
    )

    suspend fun refreshDevices(): Result<List<Device>> = withContext(Dispatchers.IO) {
        try {
            val adbPath = config.getAdbPath() ?: return@withContext Result.failure(IllegalStateException("ADB path not set"))
            val adbDir = File(adbPath).parent ?: return@withContext Result.failure(IllegalStateException("Invalid ADB path"))

            // Start adb server
            shell.execute("$adbPath start-server", 15000).getOrThrow()

            // Connect common emulator ports
            val ports = listOf(5555, 5557, 5559, 5561, 5563, 5565, 5567, 62001, 62025)
            for (port in ports) {
                shell.execute("$adbPath connect 127.0.0.1:$port", 5000)
            }

            // Cloud ADB
            config.getCloudAdb()?.let { cloudAdb ->
                shell.execute("$adbPath connect $cloudAdb", 5000)
            }

            // Get device list
            val devicesOutput = shell.execute("$adbPath devices", 60000).getOrThrow()
            val devices = mutableListOf<Device>()
            val seenBootIds = mutableSetOf<String>()

            devicesOutput.lines().forEach { line ->
                val trimmed = line.trim()
                if (trimmed.endsWith("device") && !trimmed.startsWith("List")) {
                    val serial = trimmed.substringBefore(" ").trim()
                    val bootIdResult = shell.execute("$adbPath -s $serial shell cat /proc/sys/kernel/random/boot_id", 60000)
                    val bootId = if (bootIdResult.isSuccess) bootIdResult.getOrNull()?.trim() ?: serial else serial

                    if (bootId !in seenBootIds) {
                        seenBootIds.add(bootId)
                        val displayName = getDisplayName(adbDir, serial)
                        devices.add(Device(serial, displayName))
                    }
                }
            }

            Result.success(devices)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    private fun getDisplayName(adbDir: File, serial: String): String {
        // Try to get LDPlayer console name
        val consoleExe = listOf("ldconsole.exe", "dnconsole.exe")
            .map { File(adbDir, it) }
            .firstOrNull { it.exists() }

        consoleExe?.let { console ->
            try {
                val process = ProcessBuilder(console.absolutePath, "list2").start()
                val output = process.inputStream.bufferedReader().readText()
                process.waitFor()

                output.lines().forEach { line ->
                    val parts = line.split(",")
                    if (parts.size > 2) {
                        val index = parts[0].toIntOrNull()
                        val name = parts[1]
                        val port = when {
                            serial.startsWith("127.0.0.1:") -> serial.substringAfter(":").toIntOrNull()
                            serial.startsWith("emulator-") -> serial.substringAfter("emulator-").toIntOrNull()
                            else -> null
                        }
                        port?.let { p ->
                            val calcIndex = if (p in 5555..5599 && (p - 5555) % 2 == 0) (p - 5555) / 2
                            else if (p in 5554..5598 && (p - 5554) % 2 == 0) (p - 5554) / 2
                            else null
                            if (calcIndex == index) {
                                return "[${name}] (${serial})"
                            }
                        }
                    }
                }
            } catch (e: Exception) {
                // Ignore
            }
        }
        return serial
    }
}