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
    val selectedGamePackage = mutableStateOf("[Auto-Detect Running Game]")
    val adbPath = mutableStateOf<String?>(null)

    // Settings state
    val partySlots = mutableStateListOf<String>("", "", "", "", "")
    val catHp = mutableStateOf(75)
    val catSp = mutableStateOf(75)
    val dungeonCount = mutableStateOf(0)
    val fleeNoParty = mutableStateOf(false)
    val isEnglish = mutableStateOf(false)

    // Game packages
    val gamePackages = listOf(
        "[Auto-Detect Running Game]",
        "com.vtcmobile.gz06 (TS VTC)",
        "net.chinesegamer.tsn (TS China)",
        "com.sohagame.tsonline",
        "com.gameark.tsonline",
        "com.sohagame.ts"
    )

    init {
        loadSettings()
        adbPath.value = config.getAdbPath()
    }

    private fun loadSettings() {
        isEnglish.value = config.isEnglish()
        partySlots.forEachIndexed { i, _ ->
            partySlots[i] = config.getPartySlot(i + 1) ?: ""
        }
        catHp.value = config.getCatBinhHp()
        catSp.value = config.getCatBinhSp()
        dungeonCount.value = config.getDailyDungeon()
        fleeNoParty.value = config.isFleeNoParty()
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

    fun onGamePackageChanged(pkg: String) {
        selectedGamePackage.value = pkg
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
            partySlots = partySlots.toList(),
            catHp = catHp.value,
            catSp = catSp.value,
            dungeonCount = dungeonCount.value,
            fleeNoParty = fleeNoParty.value,
            gamePackage = selectedGamePackage.value
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

    // Settings actions
    fun onPartySlotChanged(index: Int, name: String) {
        partySlots[index] = name
    }

    fun onCatHpChanged(value: Int) {
        catHp.value = value
    }

    fun onCatSpChanged(value: Int) {
        catSp.value = value
    }

    fun onDungeonCountChanged(value: Int) {
        dungeonCount.value = value
    }

    fun onFleeNoPartyChanged(enabled: Boolean) {
        fleeNoParty.value = enabled
    }

    fun onLanguageChanged(english: Boolean) {
        isEnglish.value = english
    }

    fun saveSettings() {
        config.setAdbPath(adbPath.value ?: "")
        config.setGamePackage(selectedGamePackage.value)
        config.setEnglish(isEnglish.value)
        config.setFleeNoParty(fleeNoParty.value)
        config.setCatBinhHp(catHp.value)
        config.setCatBinhSp(catSp.value)
        config.setDailyDungeon(dungeonCount.value)
        partySlots.forEachIndexed { i, name ->
            config.setPartySlot(i + 1, name)
        }
        addLog("[OK] Settings saved")
    }

    private fun addLog(message: String) {
        val timestamp = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.getDefault()).format(java.util.Date())
        logs.add(0, "[$timestamp] $message")
    }
}