package com.vtcdeploy.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vtcdeploy.data.DeviceManager
import com.vtcdeploy.domain.PatchUseCase
import com.vtcdeploy.data.ConfigManager

@Composable
fun MainScreen(
    viewModel: MainViewModel
) {
    val devices by viewModel.devices.collectAsStateWithLifecycle()
    val isScanning by viewModel.isScanning.collectAsStateWithLifecycle()
    val isPatching by viewModel.isPatching.collectAsStateWithLifecycle()
    val logs by viewModel.logs.collectAsStateWithLifecycle()
    val adbPath by viewModel.adbPath.collectAsStateWithLifecycle()

    Column(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // Title
        Text(
            text = "GAME PERFORMANCE OPTIMIZER",
            fontSize = 20.sp,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.fillMaxWidth().wrapContentWidth(Alignment.CenterHorizontally)
        )

        // ADB Path Row
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(text = "Emulator Directory", fontWeight = FontWeight.Medium)
            OutlinedTextField(
                value = adbPath ?: "",
                onValueChange = { viewModel.onAdbPathChanged(it) },
                modifier = Modifier.weight(1f),
                label = { Text("ADB directory") },
                isEnabled = !isPatching
            )
        }

        // Game Package Info
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(text = "Game: com.vtcmobile.gz06", fontWeight = FontWeight.Medium)
        }

        // Device List
        Card(
            modifier = Modifier.fillMaxWidth().weight(1f, true),
            elevation = CardDefaults.cardElevation(defaultElevation = 4.dp)
        ) {
            Column(modifier = Modifier.padding(16.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(text = "Emulator List (Check to Patch)", fontWeight = FontWeight.Bold, fontSize = 16.sp)
                    Button(onClick = { viewModel.refreshDevices() }, enabled = !isScanning && !isPatching) {
                        if (isScanning) CircularProgressIndicator(modifier = Modifier.size(20.dp)) else Text("Refresh")
                    }
                }

                if (devices.isEmpty() && !isScanning) {
                    Text(text = "No devices found. Click Refresh.", color = Color.Gray, modifier = Modifier.fillMaxWidth().padding(vertical = 32.dp).wrapContentWidth(Alignment.CenterHorizontally))
                } else {
                    LazyColumn(modifier = Modifier.fillMaxWidth()) {
                        items(devices) { device ->
                            DeviceRow(
                                device = device,
                                isChecked = viewModel.isDeviceSelected(device.serial),
                                onCheckedChange = { viewModel.toggleDevice(device.serial, it) },
                                enabled = !isPatching
                            )
                        }
                    }
                }
            }
        }

        // Log View
        Card(
            modifier = Modifier.fillMaxWidth().height(200.dp),
            elevation = CardDefaults.cardElevation(defaultElevation = 4.dp)
        ) {
            Column(modifier = Modifier.padding(8.dp)) {
                Text(text = "LOG", fontWeight = FontWeight.Bold)
                androidx.compose.foundation.Text(
                    text = logs.joinToString("\n"),
                    modifier = Modifier
                        .fillMaxSize()
                        .background(Color.Black)
                        .padding(8.dp),
                    color = Color.Green,
                    fontSize = 12.sp
                )
            }
        }

        // Patch Button
        Button(
            onClick = { viewModel.startPatch() },
            enabled = !isPatching && devices.any { viewModel.isDeviceSelected(it.serial) },
            modifier = Modifier.fillMaxWidth().height(56.dp),
            colors = ButtonDefaults.buttonColors(
                containerColor = MaterialTheme.colorScheme.primary,
                contentColor = MaterialTheme.colorScheme.onPrimary
            )
        ) {
            if (isPatching) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    CircularProgressIndicator(color = MaterialTheme.colorScheme.onPrimary, modifier = Modifier.size(24.dp))
                    Text("PATCH (ACTIVATE OPTIMIZATION)")
                }
            } else {
                Text("PATCH (ACTIVATE OPTIMIZATION)", fontSize = 16.sp, fontWeight = FontWeight.Bold)
            }
        }

        // Instructions
        Text(
            text = "INSTRUCTIONS:\n1. ALWAYS CLICK [PATCH] WHILE IN GAME, EVERY TIME GAME RESTARTS.\n2. IF TOOL HANGS, ONLY RESTART GAME APP, NOT THE ENTIRE EMULATOR.",
            fontSize = 12.sp,
            color = Color.Gray,
            modifier = Modifier.fillMaxWidth().padding(top = 16.dp)
        )
    }
}

@Composable
fun DeviceRow(
    device: DeviceManager.Device,
    isChecked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    enabled: Boolean
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(12.dp)
            .background(Color.White)
    ) {
        Checkbox(checked = isChecked, onCheckedChange = onCheckedChange, enabled = enabled)
        Spacer(modifier = Modifier.width(12.dp))
        Column {
            Text(text = device.displayName, fontWeight = FontWeight.Medium)
            Text(text = device.serial, fontSize = 12.sp, color = Color.Gray)
        }
    }
}