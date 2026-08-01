# Harmonic Signature Based NILM

## Project Overview

This project implements a Non-Intrusive Load Monitoring (NILM) system capable of identifying household appliances from a single aggregate current waveform under unstable feeder conditions.

The system applies Digital Signal Processing techniques including:

- Sampling Theory
- FFT Harmonic Analysis
- FIR Filtering
- Windowing
- Harmonic Feature Extraction
- Rule-Based Classification

---

## System Pipeline

Appliance Models
↓

Signal Generation
↓

Aggregate Current
↓

Disturbance Modelling
↓

Windowing
↓

FIR Filtering
↓

FFT Analysis
↓

Feature Extraction
↓

Classification
↓

Performance Evaluation

---

## Project Structure

```text
src/
signal_generation/
disturbances/
preprocessing/
fft/
feature_extraction/
classification/
evaluation/
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

---

## Running the Project

Open MATLAB

Run

```matlab
main
```