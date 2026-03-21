// Web Audio API implementation for odin-wgpu audio package
// This file provides audio functionality that can be called from Odin/WASM

const engineAudio = {
  // Audio context and nodes
  audioContext: null,
  masterGain: null,
  listener: null,

  // State
  initialized: false,
  nextSourceHandle: 1,
  nextInstanceHandle: 1,
  nextBusHandle: 2, // 1 is reserved for master bus

  // Storage
  sources: new Map(), // handle -> { buffer: AudioBuffer, duration: f32 }
  instances: new Map(), // handle -> { source, sourceNode, gainNode, pannerNode, spatialPanner, ... }
  buses: new Map(), // handle -> { gainNode, volume, muted }

  // Callback queue - instances that have finished and need callbacks
  finishedCallbacks: [],

  // Pending plays - queued when source isn't ready yet or context is suspended
  pendingPlays: [],

  // Listener position for spatial audio
  listenerX: 0,
  listenerY: 0,

  // ==========================================
  // LIFECYCLE
  // ==========================================

  init_audio: function () {
    if (this.initialized) return true

    try {
      this.audioContext = new (window.AudioContext ||
        window.webkitAudioContext)()

      // Create master gain (bus 1)
      this.masterGain = this.audioContext.createGain()
      this.masterGain.connect(this.audioContext.destination)

      // Store main bus
      this.buses.set(1, {
        gainNode: this.masterGain,
        volume: 1.0,
        muted: false,
      })

      // Set up listener for spatial audio
      this.listener = this.audioContext.listener
      if (this.listener.positionX) {
        // Modern API
        this.listener.positionX.value = 0
        this.listener.positionY.value = 0
        this.listener.positionZ.value = 0
      } else {
        // Legacy API
        this.listener.setPosition(0, 0, 0)
      }

      this.initialized = true

      // Resume audio context on user interaction (required by browsers)
      const resumeAudio = () => {
        if (this.audioContext.state === "suspended") {
          this.audioContext.resume().then(() => {
            // Process any pending plays now that context is running
            if (this.pendingPlays.length > 0) {
              this.processPendingPlays()
            }
          })
        }
      }
      document.addEventListener("click", resumeAudio)
      document.addEventListener("keydown", resumeAudio)
      document.addEventListener("touchstart", resumeAudio)

      return true
    } catch (e) {
      console.error("Failed to initialize Web Audio:", e)
      return false
    }
  },

  shutdown: function () {
    if (!this.initialized) return

    // Stop all instances
    for (const [handle, instance] of this.instances) {
      this.stopInstance(instance)
    }

    this.sources.clear()
    this.instances.clear()
    this.buses.clear()
    this.finishedCallbacks = []
    this.nextSourceHandle = 1
    this.nextInstanceHandle = 1
    this.nextBusHandle = 2

    if (this.audioContext) {
      this.audioContext.close()
      this.audioContext = null
    }

    this.initialized = false
  },

  // ==========================================
  // SOURCE MANAGEMENT
  // ==========================================

  loadAudio: async function (data, isStream) {
    if (!this.initialized) return 0

    // Resume context if suspended
    if (this.audioContext.state === "suspended") {
      await this.audioContext.resume()
    }

    try {
      // Create a copy of the data as an ArrayBuffer
      const arrayBuffer = data.buffer.slice(
        data.byteOffset,
        data.byteOffset + data.byteLength,
      )
      const audioBuffer = await this.audioContext.decodeAudioData(arrayBuffer)

      const handle = this.nextSourceHandle++
      this.sources.set(handle, {
        buffer: audioBuffer,
        duration: audioBuffer.duration,
      })
      return handle
    } catch (e) {
      console.error("Failed to load audio:", e)
      return 0
    }
  },

  destroyAudio: function (sourceHandle) {
    this.sources.delete(sourceHandle)
  },

  getAudioDuration: function (sourceHandle) {
    const source = this.sources.get(sourceHandle)
    if (!source) return 0
    return source.duration
  },

  // ==========================================
  // PLAYBACK
  // ==========================================

  playAudio: function (
    sourceHandle,
    busHandle,
    volume,
    pan,
    pitch,
    loop,
    delay,
    isSpatial,
    posX,
    posY,
    minDistance,
    maxDistance,
    hasCallback,
  ) {
    if (!this.initialized) return 0

    const source = this.sources.get(sourceHandle)
    if (!source) {
      // Source not ready yet (still decoding) - queue the play request
      const handle = this.nextInstanceHandle++
      this.pendingPlays.push({
        handle,
        sourceHandle,
        busHandle,
        volume,
        pan,
        pitch,
        loop,
        delay,
        isSpatial,
        posX,
        posY,
        minDistance,
        maxDistance,
        hasCallback,
        retries: 0,
      })
      // Retry after a delay (only schedule once)
      if (this.pendingPlays.length === 1) {
        setTimeout(() => this.processPendingPlays(), 500)
      }
      return handle
    }

    // Resume context if suspended
    if (this.audioContext.state === "suspended") {
      this.audioContext.resume()
    }

    // Source is ready, play immediately
    const handle = this.nextInstanceHandle++
    this.playAudioInternal(
      {
        handle,
        sourceHandle,
        busHandle,
        volume,
        pan,
        pitch,
        loop,
        delay,
        isSpatial,
        posX,
        posY,
        minDistance,
        maxDistance,
        hasCallback,
      },
      source,
    )
    return handle
  },

  stopInstance: function (instance) {
    if (!instance || instance.stopped) return

    instance.stopped = true
    try {
      instance.sourceNode.stop()
    } catch (e) {
      // Ignore errors if already stopped
    }

    // Disconnect nodes
    try {
      instance.sourceNode.disconnect()
      instance.gainNode.disconnect()
      if (instance.pannerNode) instance.pannerNode.disconnect()
      if (instance.spatialPanner) instance.spatialPanner.disconnect()
    } catch (e) {
      // Ignore disconnect errors
    }
  },

  stopAudio: function (instanceHandle) {
    const instance = this.instances.get(instanceHandle)
    if (!instance) return

    this.stopInstance(instance)
    this.instances.delete(instanceHandle)
  },

  pauseAudio: function (instanceHandle) {
    const instance = this.instances.get(instanceHandle)
    if (!instance || instance.paused || instance.stopped) return

    // Web Audio doesn't have native pause, so we stop and record position
    instance.paused = true
    instance.pauseTime = this.audioContext.currentTime - instance.startTime

    try {
      instance.sourceNode.stop()
    } catch (e) {
      // Ignore
    }
  },

  resumeAudio: function (instanceHandle) {
    const instance = this.instances.get(instanceHandle)
    if (!instance || !instance.paused || instance.stopped) return

    const source = this.sources.get(instance.sourceHandle)
    if (!source) return

    // Create new source node and resume from pause position
    const newSourceNode = this.audioContext.createBufferSource()
    newSourceNode.buffer = source.buffer
    newSourceNode.loop = instance.loop
    newSourceNode.playbackRate.value =
      instance.pitch === 0 ? 1.0 : instance.pitch

    // Reconnect
    let lastNode = newSourceNode
    if (instance.spatialPanner) {
      lastNode.connect(instance.spatialPanner)
      lastNode = instance.spatialPanner
    } else if (instance.pannerNode) {
      lastNode.connect(instance.pannerNode)
      lastNode = instance.pannerNode
    }
    lastNode.connect(instance.gainNode)

    // Update instance
    instance.sourceNode = newSourceNode
    instance.paused = false
    instance.startTime = this.audioContext.currentTime - instance.pauseTime

    // Set up onended again
    newSourceNode.onended = () => {
      if (!instance.stopped && !instance.loop) {
        if (instance.hasCallback) {
          this.finishedCallbacks.push(instanceHandle)
        }
        this.instances.delete(instanceHandle)
      }
    }

    // Start from pause position
    newSourceNode.start(0, instance.pauseTime)
  },

  stopAllAudio: function (busHandle) {
    for (const [handle, instance] of this.instances) {
      // If busHandle is 0, stop all. Otherwise filter by bus
      if (busHandle === 0 || instance.busHandle === busHandle) {
        this.stopInstance(instance)
        this.instances.delete(handle)
      }
    }
  },

  // ==========================================
  // LIVE CONTROL
  // ==========================================

  setAudioVolume: function (instanceHandle, volume) {
    const instance = this.instances.get(instanceHandle)
    if (!instance) return

    instance.volume = volume
    instance.gainNode.gain.value = volume
  },

  setAudioPan: function (instanceHandle, pan) {
    const instance = this.instances.get(instanceHandle)
    if (!instance || !instance.pannerNode) return

    instance.pannerNode.pan.value = pan
  },

  setAudioPitch: function (instanceHandle, pitch) {
    const instance = this.instances.get(instanceHandle)
    if (!instance) return

    instance.pitch = pitch
    instance.sourceNode.playbackRate.value = pitch === 0 ? 1.0 : pitch
  },

  setAudioLooping: function (instanceHandle, loop) {
    const instance = this.instances.get(instanceHandle)
    if (!instance) return

    instance.loop = loop
    instance.sourceNode.loop = loop
  },

  setAudioPosition: function (instanceHandle, x, y) {
    const instance = this.instances.get(instanceHandle)
    if (!instance || !instance.spatialPanner) return

    if (instance.spatialPanner.positionX) {
      instance.spatialPanner.positionX.value = x
      instance.spatialPanner.positionY.value = y
    } else {
      instance.spatialPanner.setPosition(x, y, 0)
    }
  },

  // ==========================================
  // QUERIES
  // ==========================================

  isAudioPlaying: function (instanceHandle) {
    const instance = this.instances.get(instanceHandle)
    if (!instance) return false
    return !instance.paused && !instance.stopped
  },

  isAudioPaused: function (instanceHandle) {
    const instance = this.instances.get(instanceHandle)
    if (!instance) return false
    return instance.paused
  },

  getAudioTime: function (instanceHandle) {
    const instance = this.instances.get(instanceHandle)
    if (!instance) return 0

    if (instance.paused) {
      return instance.pauseTime
    }

    if (instance.stopped) {
      return 0
    }

    const elapsed = this.audioContext.currentTime - instance.startTime
    const source = this.sources.get(instance.sourceHandle)
    if (source && instance.loop) {
      return elapsed % source.duration
    }
    return Math.min(elapsed, source ? source.duration : elapsed)
  },

  // ==========================================
  // BUSES
  // ==========================================

  createAudioBus: function () {
    if (!this.initialized) return 0

    const handle = this.nextBusHandle++

    const gainNode = this.audioContext.createGain()
    gainNode.connect(this.masterGain)

    this.buses.set(handle, {
      gainNode: gainNode,
      volume: 1.0,
      muted: false,
    })

    return handle
  },

  destroyAudioBus: function (busHandle) {
    if (busHandle <= 1) return // Can't destroy main bus

    const bus = this.buses.get(busHandle)
    if (!bus) return

    bus.gainNode.disconnect()
    this.buses.delete(busHandle)
  },

  setAudioBusVolume: function (busHandle, volume) {
    const bus = this.buses.get(busHandle)
    if (!bus) return

    bus.volume = volume
    if (!bus.muted) {
      bus.gainNode.gain.value = volume
    }
  },

  getAudioBusVolume: function (busHandle) {
    const bus = this.buses.get(busHandle)
    if (!bus) return 1.0
    return bus.volume
  },

  setAudioBusMuted: function (busHandle, muted) {
    const bus = this.buses.get(busHandle)
    if (!bus) return

    bus.muted = muted
    bus.gainNode.gain.value = muted ? 0 : bus.volume
  },

  isAudioBusMuted: function (busHandle) {
    const bus = this.buses.get(busHandle)
    if (!bus) return false
    return bus.muted
  },

  // ==========================================
  // LISTENER
  // ==========================================

  setListenerPosition: function (x, y) {
    if (!this.initialized || !this.listener) return

    this.listenerX = x
    this.listenerY = y

    if (this.listener.positionX) {
      this.listener.positionX.value = x
      this.listener.positionY.value = y
      this.listener.positionZ.value = 0
    } else {
      this.listener.setPosition(x, y, 0)
    }
  },

  // ==========================================
  // CALLBACK POLLING
  // ==========================================

  pollFinishedCallback: function () {
    if (this.finishedCallbacks.length === 0) {
      return 0
    }
    return this.finishedCallbacks.shift()
  },

  // Process any pending play requests where source is now ready
  processPendingPlays: function () {
    // Don't process if context is suspended - wait for user interaction
    if (this.audioContext.state === "suspended") {
      // Reschedule check for later
      if (this.pendingPlays.length > 0) {
        setTimeout(() => this.processPendingPlays(), 500)
      }
      return
    }

    const stillPending = []
    for (const pending of this.pendingPlays) {
      const source = this.sources.get(pending.sourceHandle)
      if (source) {
        // Source is ready, play it now
        this.playAudioInternal(pending, source)
      } else {
        // Still not ready, keep in queue if we haven't retried too many times
        pending.retries = (pending.retries || 0) + 1
        if (pending.retries < 10) {
          // Max ~5 seconds of retries (10 * 500ms)
          stillPending.push(pending)
        } else {
          console.error(
            "Gave up waiting for audio source:",
            pending.sourceHandle,
          )
        }
      }
    }
    this.pendingPlays = stillPending
    // Schedule next check if there are still pending plays
    if (stillPending.length > 0) {
      setTimeout(() => this.processPendingPlays(), 500)
    }
  },

  // Internal play function used for both immediate and deferred plays
  playAudioInternal: function (params, source) {
    const {
      handle,
      busHandle,
      volume,
      pan,
      pitch,
      loop,
      delay,
      isSpatial,
      posX,
      posY,
      minDistance,
      maxDistance,
      hasCallback,
    } = params

    try {
      // Create source node
      const sourceNode = this.audioContext.createBufferSource()
      sourceNode.buffer = source.buffer
      sourceNode.loop = loop
      // Treat pitch of 0 as 1.0 (normal speed) since 0 means "not specified"
      sourceNode.playbackRate.value = pitch === 0 ? 1.0 : pitch

      // Create gain node for volume
      const gainNode = this.audioContext.createGain()
      gainNode.gain.value = volume

      // Determine output node (bus or master)
      let outputNode = this.masterGain
      if (busHandle > 1) {
        const bus = this.buses.get(busHandle)
        if (bus) {
          outputNode = bus.gainNode
        }
      }

      // Build audio graph
      let lastNode = sourceNode
      let pannerNode = null
      let spatialPanner = null

      if (isSpatial) {
        // Use PannerNode for spatial audio
        spatialPanner = this.audioContext.createPanner()
        spatialPanner.panningModel = "HRTF"
        spatialPanner.distanceModel = "linear"
        spatialPanner.refDistance = minDistance
        spatialPanner.maxDistance = maxDistance
        spatialPanner.rolloffFactor = 1

        if (spatialPanner.positionX) {
          spatialPanner.positionX.value = posX
          spatialPanner.positionY.value = posY
          spatialPanner.positionZ.value = 0
        } else {
          spatialPanner.setPosition(posX, posY, 0)
        }

        lastNode.connect(spatialPanner)
        lastNode = spatialPanner
      } else if (pan !== 0) {
        pannerNode = this.audioContext.createStereoPanner()
        pannerNode.pan.value = pan
        lastNode.connect(pannerNode)
        lastNode = pannerNode
      }

      lastNode.connect(gainNode)
      gainNode.connect(outputNode)

      // Store instance data
      const instance = {
        sourceHandle: params.sourceHandle,
        sourceNode: sourceNode,
        gainNode: gainNode,
        pannerNode: pannerNode,
        spatialPanner: spatialPanner,
        outputNode: outputNode,
        busHandle: busHandle,
        startTime: this.audioContext.currentTime + delay,
        pauseTime: 0,
        paused: false,
        stopped: false,
        loop: loop,
        volume: volume,
        pitch: pitch,
        hasCallback: hasCallback,
      }

      this.instances.set(handle, instance)

      // Handle callback when sound ends
      sourceNode.onended = () => {
        if (!instance.stopped && !instance.loop) {
          if (instance.hasCallback) {
            this.finishedCallbacks.push(handle)
          }
          this.instances.delete(handle)
        }
      }

      // Start playback
      const startTime = this.audioContext.currentTime + delay
      sourceNode.start(startTime)
    } catch (e) {
      console.error("Failed to play audio:", e)
    }
  },
}

// Make it globally available
window.engineAudio = engineAudio

// ==========================================
// WASM BRIDGE - Import functions for Odin
// ==========================================

;(function () {
  let wasmMemory = null

  // Expose setter globally so the HTML entry can call it after WASM instantiation
  window.setAudioWasmMemory = function (memory) {
    wasmMemory = memory
  }

  // Create the imports object for WebAssembly.instantiate
  window.audioJsImports = {
    audio_js: {
      _js_audio_init: () => {
        return engineAudio.init_audio() ? 1 : 0
      },
      _js_audio_shutdown: () => {
        engineAudio.shutdown()
      },
      _js_load_audio: (dataPtr, dataLen, isStream) => {
        if (!wasmMemory) {
          console.error("audio.js: WASM memory not available")
          return 0
        }

        // Make sure audio is initialized
        if (!engineAudio.initialized) {
          engineAudio.init_audio()
        }

        if (!engineAudio.audioContext) {
          return 0
        }

        const data = new Uint8Array(wasmMemory.buffer, dataPtr, dataLen)
        const dataCopy = new Uint8Array(data)

        // Reserve handle immediately, decode in background
        const handle = engineAudio.nextSourceHandle++

        // Decode audio data - need to copy to a new ArrayBuffer
        const arrayBuffer = new ArrayBuffer(dataCopy.length)
        const view = new Uint8Array(arrayBuffer)
        view.set(dataCopy)

        engineAudio.audioContext
          .decodeAudioData(arrayBuffer)
          .then((buffer) => {
            engineAudio.sources.set(handle, {
              buffer: buffer,
              duration: buffer.duration,
            })
          })
          .catch((e) => {
            console.error("Failed to decode audio:", e)
          })

        return handle
      },
      _js_destroy_audio: (source) => {
        engineAudio.destroyAudio(source)
      },
      _js_get_audio_duration: (source) => {
        return engineAudio.getAudioDuration(source)
      },
      _js_play_audio: (
        source,
        bus,
        volume,
        pan,
        pitch,
        loop,
        delay,
        isSpatial,
        posX,
        posY,
        minDistance,
        maxDistance,
        hasCallback,
      ) => {
        return engineAudio.playAudio(
          source,
          bus,
          volume,
          pan,
          pitch,
          loop !== 0,
          delay,
          isSpatial !== 0,
          posX,
          posY,
          minDistance,
          maxDistance,
          hasCallback !== 0,
        )
      },
      _js_stop_audio: (instance) => {
        engineAudio.stopAudio(instance)
      },
      _js_pause_audio: (instance) => {
        engineAudio.pauseAudio(instance)
      },
      _js_resume_audio: (instance) => {
        engineAudio.resumeAudio(instance)
      },
      _js_stop_all_audio: (bus) => {
        engineAudio.stopAllAudio(bus)
      },
      _js_set_audio_volume: (instance, volume) => {
        engineAudio.setAudioVolume(instance, volume)
      },
      _js_set_audio_pan: (instance, pan) => {
        engineAudio.setAudioPan(instance, pan)
      },
      _js_set_audio_pitch: (instance, pitch) => {
        engineAudio.setAudioPitch(instance, pitch)
      },
      _js_set_audio_looping: (instance, loop) => {
        engineAudio.setAudioLooping(instance, loop !== 0)
      },
      _js_set_audio_position: (instance, x, y) => {
        engineAudio.setAudioPosition(instance, x, y)
      },
      _js_is_audio_playing: (instance) => {
        return engineAudio.isAudioPlaying(instance) ? 1 : 0
      },
      _js_is_audio_paused: (instance) => {
        return engineAudio.isAudioPaused(instance) ? 1 : 0
      },
      _js_get_audio_time: (instance) => {
        return engineAudio.getAudioTime(instance)
      },
      _js_create_audio_bus: () => {
        return engineAudio.createAudioBus()
      },
      _js_destroy_audio_bus: (bus) => {
        engineAudio.destroyAudioBus(bus)
      },
      _js_set_audio_bus_volume: (bus, volume) => {
        engineAudio.setAudioBusVolume(bus, volume)
      },
      _js_get_audio_bus_volume: (bus) => {
        return engineAudio.getAudioBusVolume(bus)
      },
      _js_set_audio_bus_muted: (bus, muted) => {
        engineAudio.setAudioBusMuted(bus, muted !== 0)
      },
      _js_is_audio_bus_muted: (bus) => {
        return engineAudio.isAudioBusMuted(bus) ? 1 : 0
      },
      _js_set_listener_position: (x, y) => {
        engineAudio.setListenerPosition(x, y)
      },
      _js_poll_finished_callback: () => {
        const result = engineAudio.pollFinishedCallback() | 0
        return result
      },
    },
  }
})()
