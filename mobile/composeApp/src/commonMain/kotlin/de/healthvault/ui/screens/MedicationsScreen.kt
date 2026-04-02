package de.healthvault.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import de.healthvault.data.model.Medication
import de.healthvault.data.repository.MedicationsRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.koin.compose.viewmodel.koinViewModel
import org.koin.core.parameter.parametersOf

// ── State ────────────────────────────────────────────────────────────────────

data class MedicationsUiState(
    val items: List<Medication> = emptyList(),
    val showAll: Boolean = false,
    val isLoading: Boolean = false,
    val error: String? = null,
)

// ── ViewModel ────────────────────────────────────────────────────────────────

class MedicationsViewModel(
    private val profileId: String,
    private val repo: MedicationsRepository,
) : ViewModel() {

    private val _state = MutableStateFlow(MedicationsUiState())
    val state = _state.asStateFlow()

    init { load() }

    private fun load() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            try {
                val response = repo.list(profileId)
                _state.value = _state.value.copy(isLoading = false, items = response.items)
            } catch (e: Exception) {
                _state.value = _state.value.copy(isLoading = false, error = e.message)
            }
        }
    }

    fun toggleShowAll(showAll: Boolean) {
        _state.value = _state.value.copy(showAll = showAll)
    }

    fun add(name: String, dosage: String, frequency: String, startedAt: String) {
        viewModelScope.launch {
            try {
                val med = Medication(
                    id = "",
                    name = name,
                    dosage = dosage.ifBlank { null },
                    frequency = frequency.ifBlank { null },
                    startedAt = startedAt.ifBlank { null },
                    isActive = true,
                )
                val created = repo.create(profileId, med)
                _state.value = _state.value.copy(items = _state.value.items + created)
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = e.message)
            }
        }
    }

    fun delete(medId: String) {
        viewModelScope.launch {
            try {
                repo.delete(profileId, medId)
                _state.value = _state.value.copy(items = _state.value.items.filter { it.id != medId })
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = e.message)
            }
        }
    }
}

// ── Screen ───────────────────────────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MedicationsScreen(
    profileId: String,
    onBack: () -> Unit,
    viewModel: MedicationsViewModel = koinViewModel(parameters = { parametersOf(profileId) }),
) {
    val state by viewModel.state.collectAsState()
    var showDialog by remember { mutableStateOf(false) }

    val visible = remember(state.items, state.showAll) {
        if (state.showAll) state.items else state.items.filter { it.isActive }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Medications") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
        floatingActionButton = {
            FloatingActionButton(onClick = { showDialog = true }) {
                Icon(Icons.Default.Add, contentDescription = "Add medication")
            }
        },
    ) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding)) {

            // Active / All toggle
            Row(
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                FilterChip(
                    selected = !state.showAll,
                    onClick = { viewModel.toggleShowAll(false) },
                    label = { Text("Active") },
                )
                FilterChip(
                    selected = state.showAll,
                    onClick = { viewModel.toggleShowAll(true) },
                    label = { Text("All") },
                )
            }

            when {
                state.isLoading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
                state.error != null -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text(state.error!!, color = MaterialTheme.colorScheme.error)
                }
                visible.isEmpty() -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text(
                        if (state.showAll) "No medications recorded." else "No active medications.",
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                else -> LazyColumn(
                    contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    items(visible, key = { it.id }) { med ->
                        MedicationCard(med = med, onDelete = { viewModel.delete(med.id) })
                    }
                }
            }
        }
    }

    if (showDialog) {
        AddMedicationDialog(
            onDismiss = { showDialog = false },
            onConfirm = { name, dosage, frequency, startedAt ->
                viewModel.add(name, dosage, frequency, startedAt)
                showDialog = false
            },
        )
    }
}

// ── Card ─────────────────────────────────────────────────────────────────────

@Composable
private fun MedicationCard(med: Medication, onDelete: () -> Unit) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(med.name, style = MaterialTheme.typography.titleMedium)
                    ActiveBadge(active = med.isActive)
                }
                if (!med.dosage.isNullOrBlank()) {
                    Spacer(Modifier.height(2.dp))
                    Text(med.dosage, style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                if (!med.frequency.isNullOrBlank()) {
                    Text(med.frequency, style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            IconButton(onClick = onDelete) {
                Icon(Icons.Default.Delete, contentDescription = "Delete", tint = MaterialTheme.colorScheme.error)
            }
        }
    }
}

@Composable
private fun ActiveBadge(active: Boolean) {
    val containerColor = if (active) MaterialTheme.colorScheme.primaryContainer
    else MaterialTheme.colorScheme.surfaceVariant
    val labelColor = if (active) MaterialTheme.colorScheme.onPrimaryContainer
    else MaterialTheme.colorScheme.onSurfaceVariant
    Surface(shape = MaterialTheme.shapes.small, color = containerColor) {
        Text(
            text = if (active) "Active" else "Inactive",
            color = labelColor,
            style = MaterialTheme.typography.labelSmall,
            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
        )
    }
}

// ── Add dialog ───────────────────────────────────────────────────────────────

@Composable
private fun AddMedicationDialog(
    onDismiss: () -> Unit,
    onConfirm: (name: String, dosage: String, frequency: String, startedAt: String) -> Unit,
) {
    var name by remember { mutableStateOf("") }
    var dosage by remember { mutableStateOf("") }
    var frequency by remember { mutableStateOf("") }
    var startedAt by remember { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Add Medication") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(value = name, onValueChange = { name = it },
                    label = { Text("Name *") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(value = dosage, onValueChange = { dosage = it },
                    label = { Text("Dosage") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(value = frequency, onValueChange = { frequency = it },
                    label = { Text("Frequency") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(value = startedAt, onValueChange = { startedAt = it },
                    label = { Text("Start date (YYYY-MM-DD)") }, singleLine = true,
                    modifier = Modifier.fillMaxWidth())
            }
        },
        confirmButton = {
            TextButton(onClick = { onConfirm(name, dosage, frequency, startedAt) }, enabled = name.isNotBlank()) {
                Text("Add")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        },
    )
}
