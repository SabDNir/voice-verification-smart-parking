# Two-Stage Voice Verification for a Smart Parking System

**EEE 312 — Digital Signal Processing I Laboratory | Group 04 | BUET | October 2026**

A MATLAB-based proof of concept for verifying a vehicle owner's claimed identity through speech. The implemented system performs **two sequential voice-verification stages** and distinguishes **what was said** from **who said it**. This repository contains source code only; it does **not** include any participants' voice recordings, biometric templates, trained models, or authentication logs.

> **Status:** Software prototype demonstrated and evaluated for a course project. The ESP32/physical-barrier architecture described in the original report was proposed **but not implemented or tested**. This is not a deployment-ready security product.

## Overview

1. **Factor 1 — Identity claim:** The user provides a claimed student ID and speaks their roll number and full name. The system assesses **content** via DTW on MFCC sequences and **speaker identity** via an adapted GMM-UBM likelihood-ratio model.
2. **Factor 2 — Fresh challenge:** On passing Factor 1, the system generates a random three-digit code. The speaker says the code, which is segmented and verified digit-by-digit (MFCC + DTW), followed by a separate digit-trained speaker-verification model (GMM-UBM).
3. **Noise handling:** A three-second recording of ambient noise is used to estimate a power spectrum for spectral subtraction across the session. Pre-emphasis, voice activity trimming, MFCC extraction, and score normalization support the two stages.
4. **Fail closed:** Any failed gate returns an access-denied decision; no PIN fallback is implemented.

```text
Claimed ID
   |
   v
3-s ambient noise profile --> spectral subtraction
   |
   v
Roll number + full name
   |-- Content: MFCC + CMVN + DTW, cohort normalization
   `-- Speaker: MFCC + GMM-UBM + MAP adaptation
   |
   v
Random three-digit challenge
   |-- Segment + verify three digits (DTW)
   `-- Verify speaker again (digit-specific GMM-UBM)
   |
   v
ACCESS GRANTED / ACCESS DENIED (software decision only)
```

## Implementation

- **Environment:** MATLAB; the report describes an implementation without additional MATLAB Signal Processing, Statistics, or Image Processing toolboxes.
- **Signal processing:** mono 8 kHz front end, short-time framing, pre-emphasis, mel filterbanks, MFCCs and delta coefficients, energy-based segmentation, spectral subtraction.
- **Content verification:** time-ordered DTW, utterance-level cepstral normalization and cohort-adjusted scoring.
- **Speaker verification:** 128-component diagonal-covariance Gaussian mixture universal background model (GMM-UBM), MAP adaptation, per-frame log-likelihood ratio decision.
- **Thresholds:** phrase threshold obtained via five-fold outsider simulation; voice and digit gates are baseline engineering choices and require further live-data calibration.

## Reported evaluation

The following results come from the **October 2026 Group 04 course report** and are not independently reproduced here.

| Evaluation | Reported result | Key qualification |
| --- | --- | --- |
| Enrollment cohort | 29 students, 493 recordings | Recordings made within a single enrollment sitting per student |
| Held-out genuine logins | 0 rejected out of 348 | Same-session recordings; does not establish field FRR |
| Held-out unregistered speakers saying their own details | 0 accepted out of 87 | Does not establish field FAR; 95% upper confidence bound 4.2% |
| Held-out informed-outsider scenario | 24 accepted out of 87 at Factor 1 | 27.6%; second factor not evaluated in this scenario |
| Live recorded GUI sessions | 5 grants out of 29 attempts | True speaker labels absent; **not** an estimate of FAR/FRR |
| Challenge digit recognition | 42 correct out of 45 segmented digits | 93.3%, small sample |

The main practical limitation reported was the digit-specific speaker model: only **5 of 11** live sessions that reached the final voice gate passed it. The report describes the small amount of digit training audio (roughly 2–4 seconds per participant) as a likely cause. Controlled noise studies, replay tests, and labeled multi-day live verification remain unperformed.

## Repository contents

```text
codes/          MATLAB algorithms, model enrollment, verification, GUI
raw_records/    intentionally empty — private enrollment audio omitted
database/       intentionally empty — trained biometric models omitted
docs/           methodology, results/limitations, privacy notes
.gitignore      blocks accidental commit of recordings and models
```

## Running with your own consenting participants

**This source-only repository will not run a completed login without enrollment audio and trained models.** You must collect your own dataset with informed consent. Do not use another group's recordings without explicit permission.

1. Install MATLAB and provide a working microphone.
2. Prepare `raw_records/<participant_folder>/` with 17 WAV recordings per participant: three roll-number takes, three full-name takes, one 0–9 digit sequence, and one isolated recording for each digit. Name recordings `<7-digit-id>_<utterance>_<take>.wav` (see `codes/enrollTemplates.m`). Use fictional IDs for a public demonstration. The code expects seven-digit identifiers.
3. Open MATLAB, set its Current Folder to `codes/`, and run `ENROLL_STUDENTS.m` to train the enrolled models into the sibling `database/` folder.
4. Run `RUN_ME.m` for the GUI, or `RUN_ME_COMMAND_WINDOW.m` for the command-line session.
5. See `codes/vsConfig.m` to select an input microphone and inspect the decision parameters.

## Privacy and disclosure

Voice recordings and voice models are biometric data. The original project report restricts collected recordings and trained models to the project group and instructors. This public-facing source package **deliberately excludes** original `.wav`, `.mat`, and session-log `.csv` files. Before publication, ensure all team members approve sharing the code and that any screenshots or demonstration videos do not reveal personal information or participants who have not consented to public distribution.

## Project Documentation

[Full Technical Report](EEE312_Group04_Final_Project_Report.pdf)

[Demonstration Video](https://youtu.be/20vIgqYNTaI)

The report includes the system architecture, DSP algorithms,
mathematical methodology, experimental evaluation,
performance analysis, limitations, and proposed future work.

