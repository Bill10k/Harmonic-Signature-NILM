# Harmonic Signature Based NILM

**COE 472 — Digital Signal Processing, Mini Project 3**
Harmonic Signature Disaggregation for Load Monitoring on an Unstable Feeder
Department of Computer Engineering, KNUST

---

## What this does

Identifies which household appliances are running from a **single aggregate current measurement**, without a meter on each device, while the supply itself is distorted by voltage sags, background harmonics and brief interruptions.

Four appliances are modelled, chosen to cover every load class the brief names:

| Appliance | Load type | RMS current | What identifies it |
|---|---|---|---|
| Electric kettle | Resistive | 6.0 A | Large fundamental, almost no harmonics |
| Refrigerator compressor | Inductive motor | 2.0 A | Phase lag of 35°, start-up inrush |
| LED lamp bank | Rectifier | 0.7 A | Dominant 3rd harmonic |
| Laptop charger | Switch-mode supply | 1.1 A | 5th and 7th exceed the 3rd, content to the 15th |

---

## Running it

Open MATLAB in the project folder and run:

```matlab
main
```

That regenerates every number and figure in the report. To run on the blind benchmark waveform:

```matlab
runBlindTest('path/to/blind_data.mat')
runBlindTest('path/to/blind_data.csv', 'path/to/blind_truth.mat')   % if labels are supplied
```

No parameter is changed between the two. `main` and `runBlindTest` both call `runPipeline`, which is the entire DSP chain, so the blind waveform runs through identical code.

No toolboxes are required. Every window, filter and transform is implemented from base MATLAB.

---

## Pipeline

```
Appliance models  →  Aggregate current  →  Disturbances (sag, harmonics,
interruption, noise)  →  FIR low-pass  →  Windowing  →  FFT per window  →
Harmonic phasors  →  Feature extraction  →  Classification  →  Evaluation
```

---

## Key design decisions

**Sampling at 4 kHz.** The highest harmonic modelled is the 15th at 750 Hz, so Nyquist needs more than 1500 Hz. 4000 Hz gives 5.3× headroom, which leaves room for a realistic anti-aliasing roll-off rather than a brick wall, and stays within a low-cost metering ADC.

**A 200 ms window, hopping 100 ms.** 200 ms is exactly ten cycles of 50 Hz. A whole number of cycles makes the analysis *coherent*: every harmonic lands precisely on an FFT bin centre, so there is no leakage between harmonics. At 4 kHz that is 800 samples and a 5 Hz bin spacing. The 100 ms hop is five cycles, so harmonic phases stay comparable from window to window.

**Odd harmonics only, 1 to 15.** A load with half-wave symmetry produces no even harmonics. Reading them would add noise and no information.

**Classification by combination matching, not per-appliance rules.** Asking "does this window look like a kettle?" fails on an aggregate measurement, because when three appliances run together the meter sees their *sum*, which resembles none of them. Instead we ask which of the 2⁴ = 16 possible on/off combinations best explains the measured harmonic phasors. Phasors rather than magnitudes, because harmonics from different appliances add as vectors and can partially cancel.

**The classifier holds state through an outage.** No current does not mean no load. Windows where the fundamental has collapsed are flagged and the previous decision is retained.

---

## Measured performance

On our own 12-second recording with a 30% sag, 8% background THD, a 100 ms interruption and 35 dB SNR:

| Metric | Result |
|---|---|
| Overall accuracy | 97.9% |
| Macro-F1 | 0.983 |
| Exact-match windows | ~81% |

Robustness, measured by re-running the whole pipeline with one condition changed at a time:

| Condition swept | Range tested | Macro-F1 |
|---|---|---|
| Sag depth | 10% to 60% | 0.978 – 0.983 |
| Measurement noise | 45 dB down to 15 dB SNR | 0.962 – 0.985 |
| Background THD | 2% to 8% | 0.983 – 0.993 |
| Background THD | 15% to 25% | 0.888 – 0.842 ← degrades |

**Known limitation.** Background supply distortion above roughly 15% THD breaks the method, because injected harmonics at the 5th, 7th and 11th are indistinguishable from harmonics drawn by a rectifier load at the same orders. This is a property of any harmonic-signature NILM method, not of this implementation.

---

## Project structure

```
main.m                      run everything on our own data
runBlindTest.m              run everything on an unseen waveform
runPipeline.m               the shared DSP chain
defaultParameters.m         every setting, with its justification
model_four_appliances.m     appliance models and ground truth

src/
  disturbances/             sag, background harmonics, interruption, noise
  preprocessing/            FIR filter design, windowing
  fft/                      FFT, harmonic phasors, blind-data loader
  feature_extraction/       per-window features
  classification/           appliance library, combination matcher
  evaluation/               confusion matrices, metrics, report figures
```

---

## Team

| Module | Member |
|---------|--------|
| Signal Generation | Joseph Lebuni Daveson, Edmund Kwame Denteh |
| Disturbances | Tetteh Prince Djangmah |
| Preprocessing | Joseph Maxwell Donkor |
| FFT | Jojo Selasie Amani Dogbo |
| Feature Extraction | Papa Kojo Afoa Eshun |
| Classification | Owusu Kelvin Frimpong |
| Evaluation | Reginald Jojo Gwira |
| Research | Benjamin Darko, Kwaku Agyemang Darko |
| Documentation | Felix Gyamfi |
| Technical Lead | Bill Etornam Kwame Gbadago |
