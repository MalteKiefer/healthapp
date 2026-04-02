package de.healthvault

import androidx.compose.runtime.Composable
import de.healthvault.ui.navigation.AppNavigation
import de.healthvault.ui.theme.HealthVaultTheme

@Composable
fun App() {
    HealthVaultTheme {
        AppNavigation()
    }
}
