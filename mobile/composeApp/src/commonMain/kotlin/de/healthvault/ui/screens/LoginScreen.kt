package de.healthvault.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Info
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import de.healthvault.data.repository.AuthRepository
import io.ktor.client.request.get
import io.ktor.http.HttpStatusCode
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.koin.compose.viewmodel.koinViewModel

data class LoginUiState(
    val email: String = "",
    val password: String = "",
    val serverUrl: String = "https://health.p37.nexus",
    val isLoading: Boolean = false,
    val error: String? = null,
    val isLoggedIn: Boolean = false
)

class LoginViewModel(private val authRepo: AuthRepository) : ViewModel() {
    private val _state = MutableStateFlow(LoginUiState())
    val state = _state.asStateFlow()

    fun onEmailChange(email: String) { _state.value = _state.value.copy(email = email) }
    fun onPasswordChange(pw: String) { _state.value = _state.value.copy(password = pw) }
    fun onServerUrlChange(url: String) { _state.value = _state.value.copy(serverUrl = url) }

    /**
     * Try to discover the correct API base URL from user input.
     * Accepts various formats:
     *   - health.example.com          -> tries https://health.example.com/api/v1, then :3101
     *   - https://health.example.com  -> tries /api/v1 path
     *   - http://10.0.2.2:3101       -> direct API access
     *   - health.example.com/api      -> strips /api, uses base
     */
    private suspend fun discoverBaseUrl(input: String): String {
        val trimmed = input.trim().trimEnd('/')

        // Add scheme if missing
        val withScheme = when {
            trimmed.startsWith("http://") || trimmed.startsWith("https://") -> trimmed
            trimmed.contains("localhost") || trimmed.contains("10.0.2.2") || trimmed.contains("127.0.0.1") -> "http://$trimmed"
            else -> "https://$trimmed"
        }

        // Strip trailing /api or /api/v1 — we add it ourselves in API paths
        val base = withScheme
            .removeSuffix("/api/v1")
            .removeSuffix("/api")
            .trimEnd('/')

        // Try candidates in order: direct health check
        val candidates = mutableListOf<String>()

        // If URL already has a port, try it directly
        if (base.contains(":\\d".toRegex())) {
            candidates.add(base)
        }

        // Standard: API behind reverse proxy at /api/v1
        val baseNoPort = base.replace(Regex(":\\d+$"), "")
        candidates.add(baseNoPort)

        // Direct API port (common self-hosted setup)
        if (!base.contains(":\\d".toRegex())) {
            candidates.add("$baseNoPort:3101")
            candidates.add("${baseNoPort.replace("https://", "http://")}:3101")
        }

        for (candidate in candidates) {
            try {
                val response = de.healthvault.data.api.ApiClient.client.get("$candidate/health")
                if (response.status.value == 200) {
                    return candidate
                }
            } catch (_: Exception) {
                // Try next candidate
            }
        }

        // Fallback: return the cleaned base, let login fail with a clear error
        return base
    }

    fun login() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            try {
                val baseUrl = discoverBaseUrl(_state.value.serverUrl)
                de.healthvault.data.api.ApiClient.baseUrl = baseUrl
                authRepo.login(_state.value.email, _state.value.password)
                _state.value = _state.value.copy(isLoading = false, isLoggedIn = true)
            } catch (e: Exception) {
                _state.value = _state.value.copy(isLoading = false, error = e.message ?: "Login failed")
            }
        }
    }
}

@Composable
fun LoginScreen(
    onLoginSuccess: () -> Unit,
    viewModel: LoginViewModel = koinViewModel()
) {
    val state by viewModel.state.collectAsState()
    var showPassword by remember { mutableStateOf(false) }

    LaunchedEffect(state.isLoggedIn) {
        if (state.isLoggedIn) onLoginSuccess()
    }

    Scaffold { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(24.dp),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            // Logo / Title
            Icon(
                imageVector = Icons.Default.Favorite,
                contentDescription = null,
                modifier = Modifier.size(64.dp),
                tint = MaterialTheme.colorScheme.primary
            )
            Spacer(Modifier.height(16.dp))
            Text("HealthVault", style = MaterialTheme.typography.headlineLarge)
            Text(
                "Your health, your data",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(Modifier.height(48.dp))

            // Email
            OutlinedTextField(
                value = state.email,
                onValueChange = viewModel::onEmailChange,
                label = { Text("Email") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                modifier = Modifier.fillMaxWidth()
            )
            Spacer(Modifier.height(12.dp))

            // Password
            OutlinedTextField(
                value = state.password,
                onValueChange = viewModel::onPasswordChange,
                label = { Text("Password") },
                singleLine = true,
                visualTransformation = if (showPassword) VisualTransformation.None else PasswordVisualTransformation(),
                trailingIcon = {
                    IconButton(onClick = { showPassword = !showPassword }) {
                        Icon(
                            imageVector = if (showPassword) Icons.Default.Info else Icons.Default.Lock,
                            contentDescription = if (showPassword) "Hide password" else "Show password"
                        )
                    }
                },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                modifier = Modifier.fillMaxWidth()
            )
            Spacer(Modifier.height(12.dp))

            // Server
            OutlinedTextField(
                value = state.serverUrl,
                onValueChange = viewModel::onServerUrlChange,
                label = { Text("Server") },
                placeholder = { Text("health.example.com") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth()
            )
            Spacer(Modifier.height(24.dp))

            // Error message
            if (state.error != null) {
                Text(
                    text = state.error!!,
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodySmall
                )
                Spacer(Modifier.height(8.dp))
            }

            // Login button
            Button(
                onClick = viewModel::login,
                enabled = !state.isLoading && state.email.isNotBlank() && state.password.isNotBlank(),
                modifier = Modifier
                    .fillMaxWidth()
                    .height(48.dp)
            ) {
                if (state.isLoading) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(20.dp),
                        strokeWidth = 2.dp,
                        color = MaterialTheme.colorScheme.onPrimary
                    )
                } else {
                    Text("Sign In")
                }
            }
        }
    }
}
