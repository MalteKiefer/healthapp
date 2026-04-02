package de.healthvault.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

val Blue600 = Color(0xFF2563EB)
val Green500 = Color(0xFF10B981)
val Red500 = Color(0xFFEF4444)
val Yellow500 = Color(0xFFFACC15)

private val LightColors = lightColorScheme(
    primary = Blue600,
    secondary = Green500,
    error = Red500,
    surface = Color.White,
    background = Color(0xFFF8FAFC),
)

private val DarkColors = darkColorScheme(
    primary = Color(0xFF60A5FA),
    secondary = Color(0xFF34D399),
    error = Color(0xFFF87171),
    surface = Color(0xFF1E293B),
    background = Color(0xFF0F172A),
)

@Composable
fun HealthVaultTheme(darkTheme: Boolean = false, content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkColors else LightColors,
        content = content,
    )
}
