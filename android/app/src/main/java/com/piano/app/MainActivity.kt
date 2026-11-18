package com.piano.app

import android.content.Context
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat

class MainActivity : ComponentActivity() {
    private lateinit var synth: PianoSynth

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        // Hide system status/navigation bars for immersive piano experience
        WindowCompat.setDecorFitsSystemWindows(window, false)
        val controller = WindowCompat.getInsetsController(window, window.decorView)
        controller.systemBarsBehavior =
            WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        controller.hide(WindowInsetsCompat.Type.systemBars())

        synth = PianoSynth(this)

        val prefs = getSharedPreferences("piano_prefs", Context.MODE_PRIVATE)

        setContent {
            // Absolute index of the leftmost white key (35 = C4). Persisted between launches.
            var startWhite by remember {
                mutableIntStateOf(prefs.getInt("startWhite", 35))
            }
            // How many white keys fit on screen (7..14). Persisted between launches.
            var visibleWhiteKeys by remember {
                mutableIntStateOf(prefs.getInt("visibleWhiteKeys", 14))
            }

            MaterialTheme(
                colorScheme = darkColorScheme(
                    background = Color(0xFF1F1F1F),
                    surface = Color(0xFF1F1F1F)
                )
            ) {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = Color(0xFF1F1F1F)
                ) {
                    PianoScreen(
                        synth = synth,
                        startWhite = startWhite,
                        visibleWhiteKeys = visibleWhiteKeys,
                        onStartWhiteChange = { newStart ->
                            startWhite = newStart
                            prefs.edit().putInt("startWhite", newStart).apply()
                        },
                        onVisibleWhiteKeysChange = { newZoom ->
                            visibleWhiteKeys = newZoom
                            prefs.edit().putInt("visibleWhiteKeys", newZoom).apply()
                        }
                    )
                }
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        synth.release()
    }
}
