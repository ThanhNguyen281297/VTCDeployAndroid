package com.vtcdeploy

import android.app.Application
import com.vtcdeploy.data.ConfigManager
import com.vtcdeploy.data.ConfigProvider
import com.vtcdeploy.data.DeviceManager
import com.vtcdeploy.data.LuaScriptProvider
import com.vtcdeploy.data.ShellExecutor
import com.vtcdeploy.domain.PatchUseCase
import dagger.hilt.android.HiltAndroidApp
import dagger.hilt.android.components.ApplicationComponent
import dagger.hilt.android.components.ActivityComponent
import dagger.hilt.android.scopes.ActivityRetainedScoped
import javax.inject.Inject
import javax.inject.Singleton

@HiltAndroidApp
class VtcDeployApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // Initialize any global state here
    }
}

// Manual dependency injection (no Hilt for simplicity)
class AppContainer(private val application: VtcDeployApplication) {
    val shellExecutor = ShellExecutor(application)
    val configProvider = ConfigProvider(application)
    val configManager = configProvider.config
    val luaScriptProvider = LuaScriptProvider(application.assets)
    val deviceManager = DeviceManager(application, shellExecutor, configManager)
    val patchUseCase = PatchUseCase(shellExecutor, deviceManager, luaScriptProvider, configManager)
}

class MainApplication : Application() {
    lateinit var container: AppContainer

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
    }

    companion object {
        fun getContainer(context: android.content.Context): AppContainer {
            return (context.applicationContext as MainApplication).container
        }
    }
}