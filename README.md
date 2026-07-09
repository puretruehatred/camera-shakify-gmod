# Camera Shakify (GMod)

This is a port of the [Camera Shakify](https://github.com/EatTheFuture/camera_shakify) Blender addon by Nathan Vegdahl and Ian Hubert. I wanted actual handheld motion in GMod instead of the usual procedural noise, so I brought the Blender math over to `CalcView`.

The shake data itself is CC0 (from the original addon). held together by luaglue tradmeark patent pending

## How it works
The addon watches your movement speed and blends between three presets: **Idle**, **Walk**, and **Run**. 
* **Blend:** There's a half second crossfade so it doesn't jolt to the next preset when you start moving. It actually plays both presets at once during the transition, which sounds messy but actually makes the layering feel much more natural.
* **Debounce:** I added a centisecond delay so it doesn't flicker if you're jittering around a speed threshold.
* **Logic:** It automatically cuts out if you're in a vehicle, dead, falling, or in noclip. (midair support soon idk)

## The Settings (Q Menu)
You can find the config under **Options > Camera Shakify**.
* **General:** Global scale/speed. You can also swap which presets are used for the idle/walk/run states here.
* **Shake Layers:** This is the best part. You can stack as many extra shake layers as you want on top of the auto-movement. If you want your camera to look like it's being held by someone having a seizure, or emulate earthquakes, you can do that.
* **Misc:** Ambient tilt (view lean) and Re-Gripping.

### A note on Re-grips
Every 5-14 seconds (faster if you're sprinting), the camera will do a little hand adjustment like the cameraman (skibidi toilet lol) fumbled his handling. It picks a random slice of a preset you allowed, speeds it up, and plays a foley sound. It's subtle but makes the camera feel like a camera.

## Technical stuff for Nerds
* **Math:** Blender uses a different coordinate system than Source. Mapping the XYZ Euler rotations to GMod's Pitch/Yaw/Roll was a lot of trial and error. It's a "close enough" approximation—if an axis feels weird, you can probably just flip a sign in `CameraShakify.Sample`.
* **Convar Stuffs:** `RunConsoleCommand` doesn't update immediately. If you try to load a preset and read the values back in the same frame, it'll fail. I had to wrap the readbacks in `timer.Simple(0)` to wait for the next tick.
* **Performance:** Everything passes through a low-pass filter (`SMOOTH_TIME = 0.12`) to kill any weird jumps. You can lower this in `cl_camerashakify.lua` if you want it to feel "raw," but expect jitters.

## API / Scripting
If you're making a cinematic or a custom camera tool, you can just call the sampler directly:

```lua
--adds a layer
local id = CameraShakify.Add("HANDYCAM_RUN", {
    influence = 1, 
    scale = 1, 
    speed = 1, 
    fadeIn = 0.5
})

--stops it
CameraShakify.Remove(id, 0.5) -- Fades out over 0.5s
```

Check `cl_camerashakify.lua` for the rest of the functions. It's pretty straightforward.
