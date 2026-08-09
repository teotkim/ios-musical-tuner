# iOS Musical Tuner

An iOS musical tuner built in Swift that analyzes live microphone audio using Fast Fourier Transform (FFT) and digital signal processing. The app detects dominant frequencies in real time, supports detection of up to two simultaneous notes, and presents the results through a live visualization interface.

## Features

* Captures and analyzes live microphone audio
* Performs real-time FFT frequency analysis
* Displays detected frequencies numerically
* Detects up to two simultaneous notes
* Provides a responsive visualization for easier pitch reading
* Implements custom audio-processing logic for identifying dominant frequency peaks

## Demo

<!-- Add a screenshot or short GIF of the app here. -->

## How It Works

1. The app receives live audio samples from the device microphone.
2. An FFT converts the audio from the time domain into a frequency spectrum.
3. The signal-processing algorithm searches the spectrum for dominant frequency peaks.
4. The detected frequencies are displayed and updated in real time.
5. When multiple strong peaks are present, the algorithm can identify two simultaneous notes.

## Engineering Highlights

The initial pitch-detection system was designed to identify one dominant frequency at a time. I extended the audio-processing algorithm to distinguish two significant frequency peaks, allowing the app to detect up to two simultaneous notes.

This project provided hands-on experience with real-time audio processing, frequency-domain analysis, FFT-based pitch detection, and interactive iOS interface development.

## Technologies

* Swift
* Xcode
* Fast Fourier Transform
* Digital signal processing
* Real-time audio analysis
* iOS microphone input

## Getting Started

### Requirements

* macOS
* Xcode
* An iPhone or other microphone-enabled iOS device

### Installation

Clone the repository:

```bash
git clone https://github.com/teotkim/ios-musical-tuner.git
cd ios-musical-tuner
```

Open the project’s `.xcodeproj` file in Xcode.

Select an available iOS device, build the project, and allow microphone access when prompted.

## Future Improvements

* Improve pitch-detection stability in noisy environments
* Refine simultaneous-note detection
* Add more detailed tuning feedback
* Add automated tests using reference audio samples

## Author

Teo Kim

[GitHub](https://github.com/teotkim)
