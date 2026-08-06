package com.vtcdeploy.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val DarkColorScheme = darkColorScheme(
    primary = Color(0xFF81C784),
    primaryContainer = Color(0xFF2E7D32),
    secondary = Color(0xFF64B5F6),
    surface = Color(0xFF121212),
    error = Color(0xFFEF5350),
    onPrimary = Color(0xFF000000),
    onPrimaryContainer = Color(0xFFFFFFFF),
    onSecondary = Color(0xFF000000),
    onSurface = Color(0xFFFFFFFF),
    onError = Color(0xFF000000),
)

private val LightColorScheme = lightColorScheme(
    primary = Color(0xFF2E7D32),
    primaryContainer = Color(0xFFA5D6A7),
    secondary = Color(0xFF1565C0),
    surface = Color(0xFFFFFFFF),
    error = Color(0xFFD32F2F),
    onPrimary = Color(0xFFFFFFFF),
    onPrimaryContainer = Color(0xFF000000),
    onSecondary = Color(0xFFFFFFFF),
    onSurface = Color(0xFF000000),
    onError = Color(0xFFFFFFFF),
)

@Composable
fun VtcDeployTheme(
    darkTheme: Boolean = false,
    content: @Composable () -> Unit
) {
    val colorScheme = if (darkTheme) DarkColorScheme else LightColorScheme
    MaterialTheme(
        colorScheme = colorScheme,
        content = content
    )
}