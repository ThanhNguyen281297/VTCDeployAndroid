package com.vtcdeploy

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.vtcdeploy.ui.MainScreen
import com.vtcdeploy.ui.MainViewModel
import com.vtcdeploy.ui.SettingsScreen
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            VtcDeployTheme {
                val container = MainApplication.getContainer(this)
                val viewModel = MainViewModel(
                    deviceManager = container.deviceManager,
                    patchUseCase = container.patchUseCase,
                    config = container.configManager
                )

                val navController = rememberNavController()
                NavHost(navController, startDestination = "main") {
                    composable("main") {
                        MainScreen(
                            viewModel = viewModel,
                            onNavigateToSettings = { navController.navigate("settings") }
                        )
                    }
                    composable("settings") {
                        SettingsScreen(viewModel = viewModel)
                    }
                }
            }
        }
    }
}