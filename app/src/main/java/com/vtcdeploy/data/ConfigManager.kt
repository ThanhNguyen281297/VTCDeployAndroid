package com.vtcdeploy.data

import android.content.Context
import android.content.SharedPreferences
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json

class ConfigManager(private val prefs: SharedPreferences) {

    companion object {
        private const val PREFS_NAME = "VtcDeployPrefs"
        const val KEY_ADB_PATH = "AdbPath"
        const val KEY_GAME_PACKAGE = "GamePackage"
        const val KEY_IS_ENGLISH = "IsEnglish"
        const val KEY_FLEE_NO_PARTY = "FleeNoParty"
        const val KEY_CLOUD_ADB = "CloudAdb"
        const val KEY_CAT_BINH_HP = "CatBinhHp"
        const val KEY_CAT_BINH_SP = "CatBinhSp"
        const val KEY_DAILY_DUNGEON = "DailyDungeonCount"
        const val KEY_PARTY_PREFIX = "PartySlot"
    }

    fun getAdbPath(): String? = prefs.getString(KEY_ADB_PATH, null)
    fun setAdbPath(path: String) = prefs.edit().putString(KEY_ADB_PATH, path).apply()

    fun getGamePackage(): String? = prefs.getString(KEY_GAME_PACKAGE, null)
    fun setGamePackage(pkg: String) = prefs.edit().putString(KEY_GAME_PACKAGE, pkg).apply()

    fun isEnglish(): Boolean = prefs.getBoolean(KEY_IS_ENGLISH, false)
    fun setEnglish(english: Boolean) = prefs.edit().putBoolean(KEY_IS_ENGLISH, english).apply()

    fun isFleeNoParty(): Boolean = prefs.getBoolean(KEY_FLEE_NO_PARTY, false)
    fun setFleeNoParty(enabled: Boolean) = prefs.edit().putBoolean(KEY_FLEE_NO_PARTY, enabled).apply()

    fun getCloudAdb(): String? = prefs.getString(KEY_CLOUD_ADB, null)
    fun setCloudAdb(adb: String) = prefs.edit().putString(KEY_CLOUD_ADB, adb).apply()

    fun getCatBinhHp(): Int = prefs.getInt(KEY_CAT_BINH_HP, 75)
    fun setCatBinhHp(value: Int) = prefs.edit().putInt(KEY_CAT_BINH_HP, value).apply()

    fun getCatBinhSp(): Int = prefs.getInt(KEY_CAT_BINH_SP, 75)
    fun setCatBinhSp(value: Int) = prefs.edit().putInt(KEY_CAT_BINH_SP, value).apply()

    fun getDailyDungeon(): Int = prefs.getInt(KEY_DAILY_DUNGEON, 0)
    fun setDailyDungeon(value: Int) = prefs.edit().putInt(KEY_DAILY_DUNGEON, value).apply()

    fun getPartySlot(slot: Int): String? = prefs.getString("$KEY_PARTY_PREFIX$slot", null)
    fun setPartySlot(slot: Int, name: String) = prefs.edit().putString("$KEY_PARTY_PREFIX$slot", name).apply()

    fun getAllPartySlots(): List<String> = (1..5).map { getPartySlot(it) ?: "" }
}

class ConfigProvider(private val context: Context) {
    private val prefs by lazy { context.getSharedPreferences(ConfigManager.PREFS_NAME, Context.MODE_PRIVATE) }
    val config = ConfigManager(prefs)
}