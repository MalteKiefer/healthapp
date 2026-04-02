package de.healthvault.ui.screens

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import de.healthvault.data.model.LabResult
import de.healthvault.data.model.LabValue
import de.healthvault.data.repository.LabsRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.koin.compose.viewmodel.koinViewModel
import org.koin.core.parameter.parametersOf

// ── UiState & ViewModel ───────────────────────────────────────────────────────

data class LabsUiState(
    val items: List<LabResult> = emptyList(),
    val isLoading: Boolean = false,
    val error: String? = null,
)

class LabsViewModel(private val profileId: String, private val repo: LabsRepository) : ViewModel() {
    private val _state = MutableStateFlow(LabsUiState())
    val state = _state.asStateFlow()

    init { load() }

    private fun load() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            try {
                val response = repo.list(profileId)
                _state.value = _state.value.copy(items = response.items, isLoading = false)
            } catch (e: Exception) {
                _state.value = _state.value.copy(isLoading = false, error = e.message ?: "Failed to load")
            }
        }
    }

    fun create(labName: String, sampleDate: String) {
        viewModelScope.launch {
            try {
                repo.create(profileId, LabResult(id = "", labName = labName, sampleDate = sampleDate))
                load()
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = e.message ?: "Failed to create")
            }
        }
    }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

private fun flagColor(flag: String?, scheme: ColorScheme): Color = when {
    flag == null || flag.equals("normal", ignoreCase = true) -> scheme.primary
    flag.equals("critical", ignoreCase = true) -> scheme.error
    else -> Color(0xFFFACC15) // high / low
}

// ── Screen ────────────────────────────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LabsScreen(
    profileId: String,
    onBack: () -> Unit,
    viewModel: LabsViewModel = koinViewModel(parameters = { parametersOf(profileId) }),
) {
    val state by viewModel.state.collectAsState()
    var showAddDialog by remember { mutableStateOf(false) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Lab Results") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
        floatingActionButton = {
            FloatingActionButton(onClick = { showAddDialog = true }) {
                Icon(Icons.Default.Add, contentDescription = "Add lab result")
            }
        },
    ) { padding ->
        Box(modifier = Modifier.fillMaxSize().padding(padding)) {
            when {
                state.isLoading -> CircularProgressIndicator(modifier = Modifier.align(Alignment.Center))
                state.error != null -> Text(
                    text = state.error!!,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.align(Alignment.Center).padding(16.dp),
                )
                state.items.isEmpty() -> Text(
                    text = "No lab results yet.",
                    modifier = Modifier.align(Alignment.Center),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                else -> LazyColumn(
                    contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    items(state.items, key = { it.id }) { lab -> LabResultCard(lab) }
                }
            }
        }
    }

    if (showAddDialog) {
        AddLabDialog(
            onDismiss = { showAddDialog = false },
            onConfirm = { name, date -> viewModel.create(name, date); showAddDialog = false },
        )
    }
}

// ── Cards ─────────────────────────────────────────────────────────────────────

@Composable
private fun LabResultCard(lab: LabResult) {
    var expanded by remember { mutableStateOf(false) }

    Card(
        modifier = Modifier.fillMaxWidth().clickable { expanded = !expanded },
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(lab.labName ?: "Unknown lab", style = MaterialTheme.typography.titleMedium)
                    Text(
                        lab.sampleDate,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Badge { Text("${lab.values.size} markers") }
            }

            AnimatedVisibility(visible = expanded) {
                Column(modifier = Modifier.padding(top = 12.dp)) {
                    HorizontalDivider(modifier = Modifier.padding(bottom = 8.dp))
                    lab.values.forEach { marker ->
                        MarkerRow(marker)
                        Spacer(Modifier.height(4.dp))
                    }
                }
            }
        }
    }
}

@Composable
private fun MarkerRow(marker: LabValue) {
    val color = flagColor(marker.flag, MaterialTheme.colorScheme)
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(marker.marker, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
        Column(horizontalAlignment = Alignment.End) {
            Text(
                text = buildString {
                    append(marker.value?.toString() ?: "—")
                    if (!marker.unit.isNullOrBlank()) append(" ${marker.unit}")
                },
                style = MaterialTheme.typography.bodyMedium,
                color = color,
            )
            if (marker.referenceLow != null || marker.referenceHigh != null) {
                Text(
                    text = "Ref: ${marker.referenceLow ?: "?"} – ${marker.referenceHigh ?: "?"}",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

// ── Add Dialog ────────────────────────────────────────────────────────────────

@Composable
private fun AddLabDialog(onDismiss: () -> Unit, onConfirm: (name: String, date: String) -> Unit) {
    var labName by remember { mutableStateOf("") }
    var sampleDate by remember { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Add Lab Result") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedTextField(
                    value = labName, onValueChange = { labName = it },
                    label = { Text("Lab name") }, singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = sampleDate, onValueChange = { sampleDate = it },
                    label = { Text("Sample date (YYYY-MM-DD)") }, singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = { onConfirm(labName.trim(), sampleDate.trim()) },
                enabled = labName.isNotBlank() && sampleDate.isNotBlank(),
            ) { Text("Add") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}
