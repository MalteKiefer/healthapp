package de.healthvault.ui.navigation

import androidx.compose.runtime.Composable
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import de.healthvault.ui.screens.AllergiesScreen
import de.healthvault.ui.screens.AppointmentsScreen
import de.healthvault.ui.screens.ContactsScreen
import de.healthvault.ui.screens.DiagnosesScreen
import de.healthvault.ui.screens.DiaryScreen
import de.healthvault.ui.screens.DocumentsScreen
import de.healthvault.ui.screens.HomeScreen
import de.healthvault.ui.screens.LabsScreen
import de.healthvault.ui.screens.LoginScreen
import de.healthvault.ui.screens.MedicationsScreen
import de.healthvault.ui.screens.SymptomsScreen
import de.healthvault.ui.screens.TasksScreen
import de.healthvault.ui.screens.VaccinationsScreen
import de.healthvault.ui.screens.VitalsScreen

@Composable
fun AppNavigation() {
    val navController = rememberNavController()

    NavHost(navController = navController, startDestination = "login") {
        composable("login") {
            LoginScreen(
                onLoginSuccess = {
                    navController.navigate("home") {
                        popUpTo("login") { inclusive = true }
                    }
                },
            )
        }
        composable("home") {
            HomeScreen(navController = navController)
        }
        composable("vitals/{profileId}") { entry ->
            VitalsScreen(
                profileId = entry.arguments?.getString("profileId") ?: "",
                onBack = { navController.popBackStack() },
            )
        }
        composable("labs/{profileId}") { entry ->
            LabsScreen(
                profileId = entry.arguments?.getString("profileId") ?: "",
                onBack = { navController.popBackStack() },
            )
        }
        composable("medications/{profileId}") { entry ->
            MedicationsScreen(
                profileId = entry.arguments?.getString("profileId") ?: "",
                onBack = { navController.popBackStack() },
            )
        }
        composable("allergies/{profileId}") { entry ->
            AllergiesScreen(
                profileId = entry.arguments?.getString("profileId") ?: "",
                onBack = { navController.popBackStack() },
            )
        }
        composable("diagnoses/{profileId}") { entry ->
            DiagnosesScreen(
                profileId = entry.arguments?.getString("profileId") ?: "",
                onBack = { navController.popBackStack() },
            )
        }
        composable("vaccinations/{profileId}") { entry ->
            VaccinationsScreen(
                profileId = entry.arguments?.getString("profileId") ?: "",
                onBack = { navController.popBackStack() },
            )
        }
        composable("appointments/{profileId}") { entry ->
            AppointmentsScreen(
                profileId = entry.arguments?.getString("profileId") ?: "",
                onBack = { navController.popBackStack() },
            )
        }
        composable("contacts/{profileId}") { entry ->
            ContactsScreen(
                profileId = entry.arguments?.getString("profileId") ?: "",
                onBack = { navController.popBackStack() },
            )
        }
        composable("tasks/{profileId}") { entry ->
            TasksScreen(
                profileId = entry.arguments?.getString("profileId") ?: "",
                onBack = { navController.popBackStack() },
            )
        }
        composable("diary/{profileId}") { entry ->
            DiaryScreen(
                profileId = entry.arguments?.getString("profileId") ?: "",
                onBack = { navController.popBackStack() },
            )
        }
        composable("symptoms/{profileId}") { entry ->
            SymptomsScreen(
                profileId = entry.arguments?.getString("profileId") ?: "",
                onBack = { navController.popBackStack() },
            )
        }
        composable("documents/{profileId}") { entry ->
            DocumentsScreen(
                profileId = entry.arguments?.getString("profileId") ?: "",
                onBack = { navController.popBackStack() },
            )
        }
    }
}
