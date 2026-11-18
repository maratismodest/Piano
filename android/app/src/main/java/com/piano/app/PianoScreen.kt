package com.piano.app

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.PointerId
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.abs
import kotlin.math.roundToInt

@Composable
fun PianoScreen(
    synth: PianoSynth,
    startWhite: Int,
    visibleWhiteKeys: Int,
    onStartWhiteChange: (Int) -> Unit,
    onVisibleWhiteKeysChange: (Int) -> Unit
) {
    // Zoom limits: 7 to 14 visible white keys
    val minVisibleKeys = 7
    val maxVisibleKeys = 14

    // Allowed range for startWhite: from C1 (14) up to keeping C8 (63) visible
    val minStartWhite = 14
    val maxStartWhite = 63 - visibleWhiteKeys + 1

    // Multi-touch tracking: PointerId -> note
    var touchNotes by remember { mutableStateOf<Map<PointerId, Int>>(emptyMap()) }
    val pressedNotes by remember { derivedStateOf { touchNotes.values.toSet() } }

    fun releaseAll() {
        pressedNotes.forEach { synth.noteOff(it) }
        touchNotes = emptyMap()
    }

    fun updateTouch(id: PointerId, note: Int?) {
        val oldNote = touchNotes[id]
        if (oldNote == note) return

        val wasHeld = note != null && pressedNotes.contains(note)
        val newMap = touchNotes.toMutableMap()
        if (note != null) {
            newMap[id] = note
        } else {
            newMap.remove(id)
        }
        touchNotes = newMap

        val newPressed = newMap.values.toSet()
        if (oldNote != null && !newPressed.contains(oldNote)) {
            synth.noteOff(oldNote)
        }
        if (note != null && !wasHeld) {
            synth.noteOn(note)
        }
    }

    // Keep startWhite within bounds when visibleWhiteKeys changes
    LaunchedEffect(visibleWhiteKeys) {
        val clamped = startWhite.coerceIn(minStartWhite, maxStartWhite)
        if (clamped != startWhite) {
            onStartWhiteChange(clamped)
        }
        releaseAll()
    }

    LaunchedEffect(startWhite) {
        releaseAll()
    }

    DisposableEffect(Unit) {
        onDispose {
            releaseAll()
        }
    }

    val keys = remember(startWhite, visibleWhiteKeys) {
        val startNote = PianoKey.whiteNote(startWhite - 1)
        PianoKey.keys(startNote = startNote, whiteCount = visibleWhiteKeys + 2)
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFF1F1F1F))
            .padding(top = 16.dp)
    ) {
        // Top Bar
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "🎹 Piano",
                color = Color.White,
                fontSize = 24.sp,
                fontWeight = FontWeight.Bold
            )

            Spacer(modifier = Modifier.weight(1f))

            // Zoom Stepper
            Icon(
                imageVector = Icons.Default.Search,
                contentDescription = null,
                tint = Color.White.copy(alpha = 0.7f),
                modifier = Modifier.size(20.dp)
            )
            Spacer(modifier = Modifier.width(4.dp))
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .clip(RoundedCornerShape(8.dp))
                    .background(Color(0xFF2C2C2E))
            ) {
                IconButton(
                    onClick = {
                        // Inverted matching iOS: "-" zooms out (more keys)
                        if (visibleWhiteKeys < maxVisibleKeys) {
                            onVisibleWhiteKeysChange(visibleWhiteKeys + 1)
                        }
                    },
                    modifier = Modifier.size(36.dp)
                ) {
                    Icon(
                        Icons.Default.Remove,
                        contentDescription = "Zoom out",
                        tint = if (visibleWhiteKeys < maxVisibleKeys) Color.White else Color.Gray,
                        modifier = Modifier.size(18.dp)
                    )
                }

                if (FeatureFlags.SHOW_ZOOM_LABEL) {
                    Text(
                        text = "$visibleWhiteKeys",
                        color = Color.White,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Medium,
                        modifier = Modifier.padding(horizontal = 4.dp)
                    )
                }

                IconButton(
                    onClick = {
                        // "+" zooms in (fewer, wider keys)
                        if (visibleWhiteKeys > minVisibleKeys) {
                            onVisibleWhiteKeysChange(visibleWhiteKeys - 1)
                        }
                    },
                    modifier = Modifier.size(36.dp)
                ) {
                    Icon(
                        Icons.Default.Add,
                        contentDescription = "Zoom in",
                        tint = if (visibleWhiteKeys > minVisibleKeys) Color.White else Color.Gray,
                        modifier = Modifier.size(18.dp)
                    )
                }
            }

            Spacer(modifier = Modifier.width(12.dp))

            // Shift Stepper
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .clip(RoundedCornerShape(8.dp))
                    .background(Color(0xFF2C2C2E))
            ) {
                IconButton(
                    onClick = {
                        if (startWhite > minStartWhite) {
                            onStartWhiteChange(startWhite - 1)
                        }
                    },
                    modifier = Modifier.size(36.dp)
                ) {
                    Icon(
                        Icons.AutoMirrored.Filled.ArrowBack,
                        contentDescription = "Shift left",
                        tint = if (startWhite > minStartWhite) Color.White else Color.Gray,
                        modifier = Modifier.size(18.dp)
                    )
                }

                if (FeatureFlags.SHOW_START_NOTE_NAME) {
                    val currentStartKey = PianoKey(
                        note = PianoKey.whiteNote(startWhite),
                        isBlack = false,
                        whiteIndex = 0
                    )
                    Text(
                        text = currentStartKey.fullName,
                        color = Color.White,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Medium,
                        modifier = Modifier.padding(horizontal = 4.dp)
                    )
                }

                IconButton(
                    onClick = {
                        if (startWhite < maxStartWhite) {
                            onStartWhiteChange(startWhite + 1)
                        }
                    },
                    modifier = Modifier.size(36.dp)
                ) {
                    Icon(
                        Icons.AutoMirrored.Filled.ArrowForward,
                        contentDescription = "Shift right",
                        tint = if (startWhite < maxStartWhite) Color.White else Color.Gray,
                        modifier = Modifier.size(18.dp)
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        // Keyboard Area
        BoxWithConstraints(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
                .padding(horizontal = 8.dp)
                .padding(bottom = 8.dp),
            contentAlignment = Alignment.BottomCenter
        ) {
            val totalWidthPx = constraints.maxWidth.toFloat()
            val totalHeightPx = constraints.maxHeight.toFloat()
            val isPortrait = totalHeightPx > totalWidthPx

            // iOS logic: In portrait, max keyboard height is 0.6 of width
            val keyboardHeightPx = if (isPortrait) {
                minOf(totalHeightPx, totalWidthPx * 0.6f)
            } else {
                totalHeightPx
            }

            val density = LocalDensity.current
            val keyboardHeightDp = with(density) { keyboardHeightPx.toDp() }

            val whiteWidth = totalWidthPx / visibleWhiteKeys.toFloat()
            val blackWidthRatio = 0.6f
            val blackHeightRatio = 0.6f
            val blackWidth = whiteWidth * blackWidthRatio
            val blackHeight = keyboardHeightPx * blackHeightRatio

            fun findNoteAt(point: Offset): Int? {
                if (point.x < 0 || point.x >= totalWidthPx || point.y < 0 || point.y >= keyboardHeightPx) {
                    return null
                }
                // Check black keys first (they sit on top)
                if (point.y < blackHeight) {
                    val black = keys.firstOrNull { key ->
                        key.isBlack && abs(point.x - key.whiteIndex.toFloat() * whiteWidth) < blackWidth / 2f
                    }
                    if (black != null) return black.note
                }
                // +1 skips the off-screen buffer key on the left
                val whiteIdx = (point.x / whiteWidth).toInt() + 1
                return keys.firstOrNull { !it.isBlack && it.whiteIndex == whiteIdx }?.note
            }

            val animatedStartWhite by animateFloatAsState(
                targetValue = startWhite.toFloat(),
                animationSpec = tween(durationMillis = 200),
                label = "startWhiteShift"
            )

            // Shift offset for sliding keys smoothly
            val shiftOffset = (startWhite.toFloat() - animatedStartWhite) * whiteWidth

            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(keyboardHeightDp)
                    .clipToBounds()
                    .pointerInput(keys, totalWidthPx, keyboardHeightPx, whiteWidth) {
                        awaitEachGesture {
                            while (true) {
                                val event = awaitPointerEvent()
                                for (change in event.changes) {
                                    if (change.pressed) {
                                        val n = findNoteAt(change.position)
                                        updateTouch(change.id, n)
                                    } else {
                                        updateTouch(change.id, null)
                                    }
                                }
                                val anyPressed = event.changes.any { it.pressed }
                                if (!anyPressed) {
                                    releaseAll()
                                }
                            }
                        }
                    }
            ) {
                val whiteKeys = remember(keys) { keys.filter { !it.isBlack } }
                val blackKeys = remember(keys) { keys.filter { it.isBlack } }

                // White Keys
                for (key in whiteKeys) {
                    val x = (key.whiteIndex - 1) * whiteWidth + shiftOffset
                    val isPressed = pressedNotes.contains(key.note)
                    val keyWidthDp = with(density) { whiteWidth.toDp() }

                    Box(
                        modifier = Modifier
                            .offset { IntOffset(x.roundToInt(), 0) }
                            .width(keyWidthDp)
                            .fillMaxHeight()
                            .padding(horizontal = 0.5.dp)
                            .clip(RoundedCornerShape(bottomStart = 6.dp, bottomEnd = 6.dp))
                            .background(if (isPressed) Color(0xFFCCCCCC) else Color.White)
                            .border(1.dp, Color.Black, RoundedCornerShape(bottomStart = 6.dp, bottomEnd = 6.dp))
                    ) {
                        if (FeatureFlags.SHOW_KEY_LABELS) {
                            Text(
                                text = key.name,
                                color = Color.Gray,
                                fontSize = 11.sp,
                                modifier = Modifier
                                    .align(Alignment.BottomCenter)
                                    .padding(bottom = 8.dp)
                            )
                        }
                    }
                }

                // Black Keys
                for (key in blackKeys) {
                    val x = key.whiteIndex * whiteWidth - (blackWidth / 2f) + shiftOffset
                    val isPressed = pressedNotes.contains(key.note)
                    val keyWidthDp = with(density) { blackWidth.toDp() }
                    val keyHeightDp = with(density) { blackHeight.toDp() }

                    Box(
                        modifier = Modifier
                            .offset { IntOffset(x.roundToInt(), 0) }
                            .width(keyWidthDp)
                            .height(keyHeightDp)
                            .clip(RoundedCornerShape(bottomStart = 4.dp, bottomEnd = 4.dp))
                            .background(if (isPressed) Color(0xFF595959) else Color.Black)
                            .border(1.dp, Color.Black, RoundedCornerShape(bottomStart = 4.dp, bottomEnd = 4.dp))
                    )
                }
            }
        }
    }
}
