package com.vtcdeploy.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.vtcdeploy.data.DeviceManager
import com.vtcdeploy.data.ConfigManager
import com.vtcdeploy.domain.PatchUseCase
import kotlinx.coroutines.launch

class MainViewModel(
    private val deviceManager: DeviceManager,
    private val patchUseCase: PatchUseCase,
    private val config: ConfigManager
) : ViewModel() {

    // Main screen state
    val devices = mutableStateListOf<DeviceManager.Device>()
    val selectedDevices = mutableStateListOf<String>()
    val isScanning = mutableStateOf(false)
    val isPatching = mutableStateOf(false)
    val logs = mutableStateListOf<String>()
    val adbPath = mutableStateOf<String?>(null)

    init {
        loadSettings()
    }

    private fun loadSettings() {
        adbPath.value = config.getAdbPath()
    }

    // Main screen actions
    fun refreshDevices() {
        isScanning.value = true
        addLog("[*] Scanning for devices...")
        viewModelScope.launch {
            val result = deviceManager.refreshDevices()
            isScanning.value = false
            result.fold(
                onSuccess = { deviceList ->
                    devices.clear()
                    devices.addAll(deviceList)
                    // Auto-select all
                    selectedDevices.clear()
                    selectedDevices.addAll(deviceList.map { it.serial })
                    addLog("[OK] Found ${deviceList.size} device(s)")
                },
                onFailure = { e ->
                    addLog("[ERROR] Scan failed: ${e.message}")
                }
            )
        }
    }

    fun toggleDevice(serial: String, selected: Boolean) {
        if (selected) selectedDevices.add(serial) else selectedDevices.remove(serial)
    }

    fun isDeviceSelected(serial: String): Boolean = selectedDevices.contains(serial)

    fun onAdbPathChanged(path: String) {
        adbPath.value = path
    }

    fun startPatch() {
        if (isPatching.value) return
        if (selectedDevices.isEmpty()) {
            addLog("[ERROR] No devices selected")
            return
        }
        if (adbPath.value.isNullOrBlank()) {
            addLog("[ERROR] ADB path not set")
            return
        }

        isPatching.value = true
        logs.clear()
        addLog("[*] Starting patch process...")

        val patchConfig = PatchUseCase.PatchConfig(
            devices = devices.filter { selectedDevices.contains(it.serial) },
            partySlots = listOf("", "", "", "", ""),
            catHp = 75,
            catSp = 75,
            dungeonCount = 0,
            fleeNoParty = false,
            gamePackage = "com.vtcmobile.gz06"
        )

        viewModelScope.launch {
            val results = patchUseCase.executePatch(patchConfig, object : PatchUseCase.PatchCallback {
                override fun onLog(message: String) {
                    addLog(message)
                }

                override fun onProgress(device: String, current: Int, total: Int) {
                    addLog("[${current}/${total}] Processing: $device")
                }

                override fun onComplete(results: List<PatchUseCase.PatchResult>) {
                    isPatching.value = false
                    val successCount = results.count { it.success }
                    addLog("[COMPLETE] $successCount/${results.size} devices patched successfully")
                }
            })
        }
    }

    fun onAdbPathChanged(path: String) {
        adbPath.value = path
    }

    private fun addLog(message: String) {
        val timestamp = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.getDefault()).format(java.util.Date())
        logs.add(0, "[$timestamp] $message")
    }
}