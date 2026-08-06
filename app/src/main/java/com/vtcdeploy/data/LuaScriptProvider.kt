package com.vtcdeploy.data

import android.content.Context
import android.content.res.AssetManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.BufferedReader
import java.io.InputStreamReader

class LuaScriptProvider(private val assets: AssetManager) {

    private val scriptPaths = mapOf(
        "Common/CGTimer.lua" to "lua/Common/CGTimer.lua",
        "Controller/RoleController.lua" to "lua/Controller/RoleController.lua",
        "Logic/Game.lua" to "lua/Logic/Game.lua",
        "Logic/VtcMod.lua" to "lua/Logic/VtcMod.lua",
        "Logic/MainAutoBuffAI.lua" to "lua/Logic/MainAutoBuffAI.lua",
        "UI/UIDebug.lua" to "lua/UI/UIDebug.lua",
        "UI/UITeleport.lua" to "lua/UI/UITeleport.lua",
        "UI/UISetting.lua" to "lua/UI/UISetting.lua",
        "UI/UIMiniMap.lua" to "lua/UI/UIMiniMap.lua",
        "UI/UISlotMachine.lua" to "lua/UI/UISlotMachine.lua"
    )

    suspend fun getScript(name: String): Result<String> = withContext(Dispatchers.IO) {
        val path = scriptPaths[name] ?: return@withContext Result.failure(IllegalArgumentException("Unknown script: $name"))
        try {
            assets.open(path).use { inputStream ->
                BufferedReader(InputStreamReader(inputStream)).use { reader ->
                    Result.success(reader.readText())
                }
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun getAllScripts(): Result<Map<String, String>> = withContext(Dispatchers.IO) {
        try {
            val result = mutableMapOf<String, String>()
            scriptPaths.forEach { (name, path) ->
                assets.open(path).use { inputStream ->
                    BufferedReader(InputStreamReader(inputStream)).use { reader ->
                        result[name] = reader.readText()
                    }
                }
            }
            Result.success(result)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun getDaemonScript(): Result<String> = withContext(Dispatchers.IO) {
        try {
            assets.open("lua/daemon.sh").use { inputStream ->
                BufferedReader(InputStreamReader(inputStream)).use { reader ->
                    Result.success(reader.readText())
                }
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
}