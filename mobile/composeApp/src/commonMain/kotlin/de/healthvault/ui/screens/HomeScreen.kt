package de.healthvault.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.navigation.NavController
import de.healthvault.data.model.Profile
import de.healthvault.data.repository.ProfileRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.koin.compose.viewmodel.koinViewModel

data class HomeUiState(
    val profiles: List<Profile> = emptyList(),
    val selectedProfile: Profile? = null,
    val isLoading: Boolean = true,
    val error: String? = null
)

class HomeViewModel(private val profileRepo: ProfileRepository) : ViewModel() {
    private val _state = MutableStateFlow(HomeUiState())
    val state = _state.asStateFlow()

    init { loadProfiles() }

    private fun loadProfiles() {
        viewModelScope.launch {
            try {
                val response = profileRepo.getProfiles()
                val profiles = response.items
                _state.value = _state.value.copy(
                    profiles = profiles,
                    selectedProfile = profiles.firstOrNull(),
                    isLoading = false
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(isLoading = false, error = e.message)
            }
        }
    }

    fun selectProfile(profile: Profile) {
        _state.value = _state.value.copy(selectedProfile = profile)
    }
}

data class HealthModule(
    val title: String,
    val icon: androidx.compose.ui.graphics.vector.ImageVector,
    val route: String
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(
    navController: NavController,
    viewModel: HomeViewModel = koinViewModel()
) {
    val state by viewModel.state.collectAsState()
    var selectedTab by remember { mutableIntStateOf(0) }

    val modules = remember {
        listOf(
            HealthModule("Vitals", Icons.Default.Favorite, "vitals"),
            HealthModule("Labs", Icons.Default.Star, "labs"),
            HealthModule("Medications", Icons.Default.Build, "medications"),
            HealthModule("Allergies", Icons.Default.Warning, "allergies"),
            HealthModule("Diagnoses", Icons.Default.Info, "diagnoses"),
            HealthModule("Vaccinations", Icons.Default.Done, "vaccinations"),
            HealthModule("Appointments", Icons.Default.DateRange, "appointments"),
            HealthModule("Contacts", Icons.Default.Phone, "contacts"),
            HealthModule("Tasks", Icons.Default.Check, "tasks"),
            HealthModule("Diary", Icons.Default.Edit, "diary"),
            HealthModule("Symptoms", Icons.Default.List, "symptoms"),
            HealthModule("Documents", Icons.Default.Search, "documents"),
        )
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("HealthVault") },
                actions = {
                    if (state.profiles.size > 1) {
                        var expanded by remember { mutableStateOf(false) }
                        Box {
                            TextButton(onClick = { expanded = true }) {
                                Text(state.selectedProfile?.displayName ?: "")
                                Icon(Icons.Default.ArrowDropDown, contentDescription = null)
                            }
                            DropdownMenu(
                                expanded = expanded,
                                onDismissRequest = { expanded = false }
                            ) {
                                state.profiles.forEach { profile ->
                                    DropdownMenuItem(
                                        text = { Text(profile.displayName) },
                                        onClick = {
                                            viewModel.selectProfile(profile)
                                            expanded = false
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
            )
        },
        bottomBar = {
            NavigationBar {
                NavigationBarItem(
                    selected = selectedTab == 0,
                    onClick = { selectedTab = 0 },
                    icon = { Icon(Icons.Default.Home, contentDescription = null) },
                    label = { Text("Home") }
                )
                NavigationBarItem(
                    selected = selectedTab == 1,
                    onClick = {
                        selectedTab = 1
                        state.selectedProfile?.let { navController.navigate("vitals/${it.id}") }
                    },
                    icon = { Icon(Icons.Default.Favorite, contentDescription = null) },
                    label = { Text("Vitals") }
                )
                NavigationBarItem(
                    selected = selectedTab == 2,
                    onClick = {
                        selectedTab = 2
                        state.selectedProfile?.let { navController.navigate("labs/${it.id}") }
                    },
                    icon = { Icon(Icons.Default.Star, contentDescription = null) },
                    label = { Text("Labs") }
                )
                NavigationBarItem(
                    selected = selectedTab == 3,
                    onClick = {
                        selectedTab = 3
                        state.selectedProfile?.let { navController.navigate("medications/${it.id}") }
                    },
                    icon = { Icon(Icons.Default.Build, contentDescription = null) },
                    label = { Text("Meds") }
                )
                NavigationBarItem(
                    selected = selectedTab == 4,
                    onClick = { selectedTab = 4 },
                    icon = { Icon(Icons.Default.MoreVert, contentDescription = null) },
                    label = { Text("More") }
                )
            }
        }
    ) { padding ->
        when {
            state.isLoading -> Box(
                modifier = Modifier.fillMaxSize().padding(padding),
                contentAlignment = Alignment.Center
            ) {
                CircularProgressIndicator()
            }

            state.error != null -> Box(
                modifier = Modifier.fillMaxSize().padding(padding),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = state.error!!,
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodyMedium
                )
            }

            else -> LazyVerticalGrid(
                columns = GridCells.Fixed(2),
                contentPadding = PaddingValues(16.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
                modifier = Modifier.fillMaxSize().padding(padding)
            ) {
                items(modules) { module ->
                    Card(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable {
                                state.selectedProfile?.let {
                                    navController.navigate("${module.route}/${it.id}")
                                }
                            }
                    ) {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(16.dp),
                            horizontalAlignment = Alignment.CenterHorizontally
                        ) {
                            Icon(
                                imageVector = module.icon,
                                contentDescription = module.title,
                                modifier = Modifier.size(32.dp),
                                tint = MaterialTheme.colorScheme.primary
                            )
                            Spacer(Modifier.height(8.dp))
                            Text(
                                text = module.title,
                                style = MaterialTheme.typography.titleSmall
                            )
                        }
                    }
                }
            }
        }
    }
}
