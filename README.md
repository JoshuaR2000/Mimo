# Mimo

Mimo is an AI assistant with a face. Instead of a chat window, you talk to an animated 3D character that listens, thinks, answers out loud, and reacts with facial expressions and body language. It can also act for you: set reminders, add calendar events, take notes, start timers, check the weather, search the web, and open Maps.

Built with SwiftUI and RealityKit for **iPhone, iPad, Mac, and Apple Vision Pro**.

## Characters

| Zuri | Bolt | Ava |
|---|---|---|
| Curious alien | Precise robot | Friendly human |

Each character has its own personality, voice, color options, and world. All three share one animation rig with seven moods (neutral, happy, laughing, sad, surprised, thinking, concerned) and five gestures (wave, nod, shake, jump, shrug).

## How it works

```
You (voice or text)
   │  Speech framework (on-device speech-to-text)
   ▼
Conversation ──► AssistantBrain (protocol)
   │                └─ OpenAIBrain: Responses API + structured output
   │                     { reply, mood, gesture } + tool calls
   │                     └─ ToolBox: Reminders, Calendar, Notes, Timer,
   │                                 Weather, Maps, Memory, Web search
   ▼
SpeechOutput (OpenAI text-to-speech) ──► audio loudness ──► lip sync
CharacterController (mood, gesture) ──► BipedRig (RealityKit, 60 fps)
```

- **Swappable brain:** the app only talks to the `AssistantBrain` protocol. `OpenAIBrain` is one implementation; `OfflineBrain` keeps the character usable without a key.
- **Structured replies:** every answer comes back as JSON with the spoken reply, a mood, and an optional gesture, so the character's body language matches what it says.
- **Tool use:** the model calls Swift functions (EventKit, notifications, Open-Meteo weather) and only confirms an action after the tool succeeds.
- **Memory:** lasting facts about the user and notes are stored on the device and added to the assistant's instructions.
- **Conversations persist:** chat history is saved on the device, and recent turns are sent as context after a relaunch or a character switch.
- **Fast replies:** light reasoning for quick spoken answers; the caption appears immediately and speech starts with the first sentence while the rest is generated.
- **Accessibility:** VoiceOver labels and announcements, Dynamic Type captions, and Reduce Motion support (no bouncing, swaying or glancing).
- **Lip sync:** the mouth follows the real loudness of the speech audio.
- **Privacy:** the API key is stored in the keychain and only sent to OpenAI. Speech recognition runs on the device when the device supports it; otherwise Apple's speech service handles it.
- **Siri and Shortcuts:** "Ask Mimo" opens the app and asks your question.
- **Switch by asking:** say "Can I talk to Bolt?" and the current character hands the conversation over.
- **Timers that speak up:** when a timer ends while the app is open, the character announces it.

## Running it

1. Open `Mimo.xcodeproj` in Xcode 26 or later.
2. Choose an iPhone, iPad, Mac, or Vision Pro destination and press Run.
3. On first launch, pick a character, enter your name, and paste an OpenAI API key from [platform.openai.com](https://platform.openai.com). You can skip the key and use offline mode.

The model can be changed in Settings (default: `gpt-5-mini`).

## Tests

Unit tests use Swift Testing and cover reply cleanup, date parsing for tool calls, character definitions, and the offline brain.

```bash
xcodebuild test -project Mimo.xcodeproj -scheme Mimo -destination 'platform=iOS Simulator,name=iPhone 18 Pro'
```

## Project layout

```
Mimo/
  Brain/      AssistantBrain protocol, OpenAI client, tools
  Character/  Character definitions, materials, 3D rig and animation
  Core/       App state, conversation flow, memory, keychain
  Voice/      Text-to-speech playback and speech recognition
  Views/      Onboarding, main screen, settings, 3D stage
  Intents/    Siri / Shortcuts integration
MimoTests/    Unit tests (Swift Testing)
tools/        make-icon.swift draws the app icon
prototypes/   Early browser prototypes of the character designs
```

## Roadmap

- Professionally modeled and rigged characters (Blender → USDZ)
- Home Screen widget
- Optional server so users don't need their own API key
- More tests around the OpenAI client and tools (with a mocked network)
