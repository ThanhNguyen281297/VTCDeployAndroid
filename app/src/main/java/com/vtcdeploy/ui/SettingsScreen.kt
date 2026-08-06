package com.vtcdeploy.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vtcdeploy.data.ConfigManager

@Composable
fun SettingsScreen(
    viewModel: MainViewModel
) {
    val partySlots by viewModel.partySlots.collectAsStateWithLifecycle()
    val catHp by viewModel.catHp.collectAsStateWithLifecycle()
    val catSp by viewModel.catSp.collectAsStateWithLifecycle()
    val dungeonCount by viewModel.dungeonCount.collectAsStateWithLifecycle()
    val fleeNoParty by viewModel.fleeNoParty.collectAsStateWithLifecycle()
    val isEnglish by viewModel.isEnglish.collectAsStateWithLifecycle()

    Column(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // Party Configuration
        Card(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.padding(16.dp)) {
                Text(text = "Auto Party Configuration (Case-Sensitive)", fontWeight = FontWeight.Bold, fontSize = 16.sp)
                LazyColumn(modifier = Modifier.fillMaxWidth()) {
                    itemsIndexed(partySlots) { index, name ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(vertical = 8.dp),
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            Text(text = when (index) {
                                0 -> "👑 Leader (Slot 1):"
                                1 -> "🧠 Adviser (Slot 2):"
                                2 -> "🤝 Member (Slot 3):"
                                3 -> "🤝 Member (Slot 4):"
                                else -> "🤝 Member (Slot 5):"
                            }, fontWeight = FontWeight.Medium, modifier = Modifier.width(140.dp))
                            OutlinedTextField(
                                value = name,
                                onValueChange = { viewModel.onPartySlotChanged(index, it) },
                                modifier = Modifier.weight(1f),
                                label = { Text("Slot ${index + 1}") }
                            )
                        }
                    }
                }
            }
        }

        // Pet AutoBuff
        Card(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.padding(16.dp)) {
                Text(text = "Pet AutoBuff (Trigger %)", fontWeight = FontWeight.Bold, fontSize = 16.sp)
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(text = "HP: ${catHp}%", fontWeight = FontWeight.Medium)
                        Slider(value = catHp.toFloat(), onValueChange = { viewModel.onCatHpChanged(it.roundToInt()) }, valueRange = 0f..100f)
                    }
                    Column(modifier = Modifier.weight(1f)) {
                        Text(text = "SP: ${catSp}%", fontWeight = FontWeight.Medium)
                        Slider(value = catSp.toFloat(), onValueChange = { viewModel.onCatSpChanged(it.roundToInt()) }, valueRange = 0f..100f)
                    }
                }
            }
        }

        // Daily Quests
        Card(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.padding(16.dp)) {
                Text(text = "Daily Quests", fontWeight = FontWeight.Bold, fontSize = 16.sp)
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    Text(text = "Buy Extra Dungeon Runs (0/1/2):", modifier = Modifier.weight(1f))
                    DropdownMenuButton(
                        text = dungeonCount.toString(),
                        onValueChange = viewModel.onDungeonCountChanged
                    ) {
                        listOf(0, 1, 2).forEach { count ->
                            DropdownMenuItem(text = count.toString(), onClick = { viewModel.onDungeonCountChanged(count) })
                        }
                    }
                }
            }
        }

        // Auto-Flee
        Card(modifier = Modifier.fillMaxWidth()) {
            Row(
                modifier = Modifier.fillMaxWidth().padding(16.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(text = "[*] Auto-Flee when No Party", fontWeight = FontWeight.Bold)
                Switch(checked = fleeNoParty, onCheckedChange = viewModel.onFleeNoPartyChanged)
            }
        }

        // Language Toggle
        Card(modifier = Modifier.fillMaxWidth()) {
            Row(
                modifier = Modifier.fillMaxWidth().padding(16.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(text = "Language", fontWeight = FontWeight.Bold)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(text = if (isEnglish) "EN" else "VN")
                    Switch(checked = isEnglish, onCheckedChange = viewModel.onLanguageChanged)
                    Text(text = if (isEnglish) "EN" else "VN")
                }
            }
        }

        Spacer(modifier = Modifier.weight(1f))

        // Save Button
        Button(
            onClick = { viewModel.saveSettings() },
            modifier = Modifier.fillMaxWidth().height(56.dp)
        ) {
            Text("Save Settings", fontSize = 16.sp, fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
fun DropdownMenuButton(
    text: String,
    onValueChange: (Int) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    MenuButton(onClick = { expanded = !expanded }) {
        Text(text = text, fontWeight = FontWeight.Medium)
    }
    DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
        listOf(0, 1, 2).forEach { count ->
            DropdownMenuItem(text = count.toString(), onClick = { onValueChange(count); expanded = false })
        }
    }
}